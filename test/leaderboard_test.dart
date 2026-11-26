import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/backend/auth_service.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/data/leaderboard_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/progress_sync.dart';
import 'package:quizzeo/leaderboard/leaderboard_controller.dart';
import 'package:quizzeo/models/quiz_submission.dart';
import 'package:quizzeo/models/weekly_leaderboard.dart';
import 'package:quizzeo/screens/leaderboard_screen.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fonts.dart';

// Heure UTC : temps restant indépendant du fuseau de la machine de test.
final _now = DateTime.utc(2026, 11, 26, 9);

/// Horloge des tests, avancée à la main (remise à [_now] avant chaque test).
var _clock = _now;

Map<String, dynamic> _board({
  List<Map<String, dynamic>>? entries,
  Map<String, dynamic>? me,
}) =>
    {
      'week_start': '2026-11-23',
      'week_end': '2026-11-29',
      'ends_at': '2026-11-29T23:00:00+00:00',
      'entries': entries ??
          [
            {'rank': 1, 'display_name': 'Camille', 'xp': 630, 'is_me': false},
            {'rank': 2, 'display_name': 'Yanis', 'xp': 580, 'is_me': false},
            {'rank': 2, 'display_name': 'Inès', 'xp': 580, 'is_me': false},
            {
              'rank': 4,
              'display_name': 'Joueur123456',
              'xp': 520,
              'is_me': true
            },
            {'rank': 5, 'display_name': 'Sofia', 'xp': 490, 'is_me': false},
          ],
      'me': me ?? {'rank': 4, 'xp': 520, 'display_name': 'Joueur123456'},
    };

/// Faux serveur PostgREST : RPC `weekly_leaderboard` et `submit_quiz`.
class _FakeServer {
  int leaderboardCalls = 0;
  bool offline = false;
  Map<String, dynamic> board = _board();

  late final client = MockClient((request) async {
    if (offline) throw const SocketException('hors ligne');
    final path = request.url.path;
    if (path == '/rest/v1/rpc/weekly_leaderboard') {
      leaderboardCalls++;
      return http.Response(jsonEncode(board), 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request);
    }
    if (path == '/rest/v1/rpc/submit_quiz') {
      return http.Response(
          jsonEncode({
            'quiz_id': (jsonDecode(request.body) as Map)['quiz_id'],
            'duplicate': false,
            'score': 8,
            'total': 10,
            'xp_gained': 120,
            'xp_capped': false,
            'profile': {
              'xp': 120,
              'streak': 1,
              'freezes': 0,
              'last_played_day': '2026-11-26',
              'daily_goal': 2,
              'quiz_day': '2026-11-26',
              'quiz_count': 1,
              'last_quiz_at': '2026-11-26T09:00:00+00:00',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    if (path == '/rest/v1/profiles') {
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
    }
    return http.Response('{"message":"interdit"}', 403, request: request);
  });
}

/// Dépôt factice pour les tests d'écran : le client Supabase décode ses
/// réponses dans un isolate, qui n'avance pas sous le temps simulé de
/// `testWidgets`. Mêmes données que [_FakeServer].
class _FakeRepository implements LeaderboardRepository {
  _FakeRepository(this.server);

  final _FakeServer server;

  @override
  Future<WeeklyLeaderboard> fetchWeekly() async {
    if (server.offline) throw const SocketException('hors ligne');
    server.leaderboardCalls++;
    return WeeklyLeaderboard.fromJson(server.board);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;
  setUp(() {
    server = _FakeServer();
    _clock = _now;
  });

  Future<List<Override>> overrides({
    bool withClient = true,
    String? userId = 'joueur-1',
    bool fakeRepository = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Tests d'écran : pas de vrai client (son isolate de décodage JSON et sa
    // fermeture n'avancent pas sous le temps simulé de `testWidgets`).
    final client = withClient && !fakeRepository
        ? SupabaseClient(
            'https://exemple.supabase.co',
            'sb_publishable_test',
            httpClient: server.client,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          )
        : null;
    if (client != null) addTearDown(client.dispose);
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _clock),
      supabaseClientProvider.overrideWithValue(client),
      authUserIdProvider.overrideWithValue(userId),
      if (fakeRepository) ...[
        backendAvailableProvider.overrideWithValue(withClient),
        leaderboardRepositoryProvider
            .overrideWithValue(withClient ? _FakeRepository(server) : null),
      ],
    ];
  }

  Future<ProviderContainer> container({
    bool withClient = true,
    String? userId = 'joueur-1',
  }) async {
    final c = ProviderContainer(
      overrides: await overrides(withClient: withClient, userId: userId),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('modèle et formats', () {
    test('fromJson : top, ex-aequo et joueur', () {
      final b = WeeklyLeaderboard.fromJson(_board());
      expect(b.weekStart, DateTime(2026, 11, 23));
      expect(b.weekEnd, DateTime(2026, 11, 29));
      expect(b.endsAt, DateTime.utc(2026, 11, 29, 23));
      expect(b.entries.map((e) => e.rank), [1, 2, 2, 4, 5]);
      expect(b.entries.where((e) => e.isMe).single.displayName, 'Joueur123456');
      expect(b.myRank, 4);
      expect(b.myXp, 520);
    });

    test('fromJson : joueur sans XP cette semaine', () {
      final b = WeeklyLeaderboard.fromJson(_board(
        entries: [],
        me: {'rank': null, 'xp': 0, 'display_name': 'Joueur000001'},
      ));
      expect(b.entries, isEmpty);
      expect(b.myRank, isNull);
      expect(b.myXp, 0);
    });

    test('période de la semaine', () {
      expect(formatWeekRange(DateTime(2026, 11, 23), DateTime(2026, 11, 29)),
          'Semaine du 23 au 29 nov.');
      expect(formatWeekRange(DateTime(2026, 11, 30), DateTime(2026, 12, 6)),
          'Semaine du 30 nov. au 6 déc.');
    });

    test('temps restant', () {
      final end = DateTime.utc(2026, 11, 29, 23);
      expect(formatTimeLeft(end, DateTime.utc(2026, 11, 25, 16, 30)),
          'Fin dans 4 j 6 h');
      expect(formatTimeLeft(end, DateTime.utc(2026, 11, 29, 16, 48)),
          'Fin dans 6 h 12 min');
      expect(formatTimeLeft(end, DateTime.utc(2026, 11, 29, 22, 59, 30)),
          'Fin dans 1 min');
      expect(formatTimeLeft(end, end), 'Semaine terminée');
    });
  });

  group('contrôleur', () {
    test('mode local : aucun classement, aucun appel', () async {
      final c = await container(withClient: false, userId: null);
      expect(await c.read(leaderboardProvider.future), isNull);
      expect(server.leaderboardCalls, 0);
    });

    test('sans session : aucun appel', () async {
      final c = await container(userId: null);
      expect(await c.read(leaderboardProvider.future), isNull);
      expect(server.leaderboardCalls, 0);
    });

    test('chargement depuis la RPC', () async {
      final c = await container();
      final b = await c.read(leaderboardProvider.future);
      expect(b!.entries, hasLength(5));
      expect(server.leaderboardCalls, 1);
    });

    test('hors ligne : erreur, dernier classement conservé', () async {
      final c = await container();
      c.listen(leaderboardProvider, (_, __) {});
      await c.read(leaderboardProvider.future);
      server.offline = true;
      _clock = _now.add(LeaderboardController.minRefreshInterval);
      await c.read(leaderboardProvider.notifier).refresh();
      final state = c.read(leaderboardProvider);
      expect(state.hasError, isTrue);
      expect(state.valueOrNull!.myRank, 4);
    });

    test('rechargé après un quiz validé par le serveur', () async {
      final c = await container();
      c.listen(leaderboardProvider, (_, __) {});
      await c.read(leaderboardProvider.future);
      expect(server.leaderboardCalls, 1);

      await c.read(progressSyncProvider)!.submitQuiz(QuizSubmission(
            id: '00000000-0000-4000-8000-000000000001',
            userId: 'joueur-1',
            playedAt: _now,
          ));
      await c.read(leaderboardProvider.future);
      expect(c.read(validatedQuizzesProvider), 1);
      expect(server.leaderboardCalls, 2,
          reason: 'quiz validé : rechargé même moins de 10 s après');
    });

    test('tirage : ignoré moins de 10 s après un chargement réussi', () async {
      final c = await container();
      c.listen(leaderboardProvider, (_, __) {});
      await c.read(leaderboardProvider.future);

      _clock = _now.add(const Duration(seconds: 9));
      await c.read(leaderboardProvider.notifier).refresh();
      expect(server.leaderboardCalls, 1, reason: 'moins de 10 s');

      _clock = _now.add(LeaderboardController.minRefreshInterval);
      await c.read(leaderboardProvider.notifier).refresh();
      expect(server.leaderboardCalls, 2);

      // Après une erreur, le tirage réessaie aussitôt.
      server.offline = true;
      _clock = _clock.add(LeaderboardController.minRefreshInterval);
      await c.read(leaderboardProvider.notifier).refresh();
      server.offline = false;
      await c.read(leaderboardProvider.notifier).refresh();
      expect(server.leaderboardCalls, 3);
      expect(c.read(leaderboardProvider).hasError, isFalse);
    });

    test('onglet ouvert : rechargé seulement s\'il date', () async {
      final c = await container();
      c.listen(leaderboardProvider, (_, __) {});
      await c.read(leaderboardProvider.future);

      c.read(leaderboardProvider.notifier).refreshIfStale();
      await c.read(leaderboardProvider.future);
      expect(server.leaderboardCalls, 1, reason: 'chargé à l\'instant');

      _clock = _now.add(LeaderboardController.maxAge);
      c.read(leaderboardProvider.notifier).refreshIfStale();
      await c.read(leaderboardProvider.future);
      expect(server.leaderboardCalls, 2);
    });
  });

  group('écran', () {
    setUpAll(loadFonts);

    Future<void> pump(
      WidgetTester tester, {
      bool withClient = true,
      String? userId = 'joueur-1',
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: await overrides(
          withClient: withClient,
          userId: userId,
          fakeRepository: true,
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: LeaderboardScreen()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mode local : message clair, aucun faux classement',
        (tester) async {
      await pump(tester, withClient: false, userId: null);
      expect(find.text('Classement indisponible'), findsOneWidget);
      expect(find.textContaining('mode local'), findsOneWidget);
      expect(find.text('Camille'), findsNothing);
      expect(find.text('Toi'), findsNothing);
    });

    testWidgets('sans session : message et bouton Réessayer', (tester) async {
      await pump(tester, userId: null);
      expect(find.text('Pas encore connecté'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(server.leaderboardCalls, 0);
    });

    testWidgets('classement : podium, liste, joueur mis en évidence',
        (tester) async {
      await pump(tester);
      expect(find.text('Semaine du 23 au 29 nov.'), findsOneWidget);
      expect(find.text('Fin dans 3 j 14 h'), findsOneWidget);
      expect(find.text('Camille'), findsOneWidget);
      expect(find.text('Inès'), findsOneWidget);
      expect(find.text('Sofia'), findsOneWidget);
      // Ligne du joueur dans la liste (pseudo remplacé par « Toi ») et ligne
      // épinglée, avec son pseudo public en sous-titre.
      expect(find.text('Toi'), findsNWidgets(2));
      expect(find.text('Joueur123456'), findsOneWidget);
      expect(find.bySemanticsLabel('Ta position : 4e, 520 XP'), findsWidgets);
      expect(find.byType(ColoredBox), findsWidgets);
      expect(find.textContaining('fictives'), findsNothing);
    });

    testWidgets('semaine vide : message, joueur pas encore classé',
        (tester) async {
      server.board = _board(
        entries: [],
        me: {'rank': null, 'xp': 0, 'display_name': 'Joueur000001'},
      );
      await pump(tester);
      expect(find.text('Personne n\'a encore d\'XP cette semaine'),
          findsOneWidget);
      expect(find.text('–'), findsOneWidget);
      expect(
          find.text('Joue un quiz pour entrer au classement'), findsOneWidget);
    });

    testWidgets('hors ligne sans données : message et réessai', (tester) async {
      server.offline = true;
      await pump(tester);
      expect(find.text('Classement indisponible'), findsOneWidget);
      expect(find.textContaining('Vérifie ta connexion'), findsOneWidget);

      server.offline = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Camille'), findsOneWidget);
    });

    testWidgets('tirer pour rafraîchir ; hors ligne : bandeau, données gardées',
        (tester) async {
      await pump(tester);
      expect(server.leaderboardCalls, 1);

      server.offline = true;
      _clock = _now.add(LeaderboardController.minRefreshInterval);
      await tester.fling(find.text('Camille'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.textContaining('Hors ligne'), findsOneWidget);
      expect(find.text('Camille'), findsOneWidget);

      server.offline = false;
      await tester.fling(find.text('Camille'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(server.leaderboardCalls, 2);
      expect(find.textContaining('Hors ligne'), findsNothing);
    });
  });
}
