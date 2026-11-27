import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizzeo/backend/auth_service.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:quizzeo/data/pending_offline_day_repository.dart';
import 'package:quizzeo/data/pending_quiz_repository.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/progress_sync.dart';
import 'package:quizzeo/models/offline_day.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_submission.dart';
import 'package:quizzeo/models/server_profile.dart';
import 'package:quizzeo/models/streak.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime(2026, 11, 26, 10);
final _today = dayOf(_now);

/// Faux serveur PostgREST : `profiles` en lecture, RPC `set_daily_goal`,
/// `answer_question` (bonne réponse : position 0) et `submit_quiz`.
class _FakeServer {
  final requests = <http.Request>[];
  bool offline = false;
  bool rpcOffline = false;
  Map<String, dynamic>? profile = _profile();

  /// Réponse d'erreur de `submit_quiz` (code SQLSTATE), null = succès.
  String? submitError;

  /// Quiz validés (réponse 200), dans l'ordre.
  final accepted = <String>[];

  /// Réponse d'erreur de `validate_offline_day` (code SQLSTATE), null = succès.
  String? validateError;

  /// Refus « propre » forcé de `validate_offline_day` (ex. `limit`).
  String? validateRefusal;

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('hors ligne');
    final path = request.url.path;
    if (path == '/rest/v1/profiles' && request.method == 'GET') {
      return http.Response(jsonEncode([if (profile != null) profile]), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }
    if (path == '/rest/v1/rpc/set_daily_goal' && request.method == 'POST') {
      if (rpcOffline) throw const SocketException('hors ligne');
      final goal = (jsonDecode(request.body) as Map)['goal'] as int;
      profile?['daily_goal'] = goal;
      return http.Response('', 204, request: request);
    }
    if (path == '/rest/v1/rpc/answer_question' && request.method == 'POST') {
      if (rpcOffline) throw const SocketException('hors ligne');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'quiz_id': body['quiz_id'],
            'position': body['position'],
            'choice': body['choice'],
            'correct': body['choice'] == 0,
            'correct_choice': 0,
            'explanation': 'Explication ${body['position']}',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    if (path == '/rest/v1/rpc/submit_quiz' && request.method == 'POST') {
      if (rpcOffline) throw const SocketException('hors ligne');
      final error = submitError;
      if (error != null) {
        return http.Response(jsonEncode({'code': error, 'message': 'refusé'}),
            error == 'PT429' ? 429 : 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
      accepted.add((jsonDecode(request.body) as Map)['quiz_id'] as String);
      // Le serveur ajoute 100 XP par quiz et valide la série du jour.
      final p = profile!
        ..['xp'] = (profile!['xp'] as int) + 100
        ..['streak'] = 13
        ..['last_played_day'] = dayKey(_today)
        ..['quiz_day'] = dayKey(_today)
        ..['quiz_count'] = 1
        ..['last_quiz_at'] = '2026-11-26T09:00:00+00:00';
      return http.Response(
          jsonEncode({
            'quiz_id': (jsonDecode(request.body) as Map)['quiz_id'],
            'duplicate': false,
            'score': 10,
            'total': 10,
            'xp_gained': 100,
            'xp_capped': false,
            'profile': p,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    if (path == '/rest/v1/rpc/validate_offline_day' &&
        request.method == 'POST') {
      if (rpcOffline) throw const SocketException('hors ligne');
      final error = validateError;
      if (error != null) {
        return http.Response(jsonEncode({'code': error, 'message': 'refusé'}),
            error == 'PT429' ? 429 : 400,
            headers: {'content-type': 'application/json'}, request: request);
      }
      // Comme le serveur : 1 validation par jour, série +1 (jours
      // consécutifs ici), compteur du jour, ni XP ni gel.
      final playedAt = (jsonDecode(request.body) as Map)['played_at'] as String;
      final day = dayOf(DateTime.parse(playedAt).toLocal());
      final p = profile!;
      final last = p['last_played_day'] as String?;
      final validated = validateRefusal == null &&
          (last == null || daysBetween(parseDayKey(last), day) > 0);
      if (validated) {
        p
          ..['streak'] = (p['streak'] as int) + 1
          ..['quiz_count'] =
              p['quiz_day'] == dayKey(day) ? (p['quiz_count'] as int) + 1 : 1
          ..['last_played_day'] = dayKey(day)
          ..['quiz_day'] = dayKey(day)
          ..['last_quiz_at'] = playedAt;
      }
      return http.Response(
          jsonEncode({
            'validated': validated,
            'reason': validated ? null : validateRefusal ?? 'already_validated',
            'day': dayKey(day),
            'profile': p,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    if (path == '/rest/v1/rpc/grant_rewarded_freeze' &&
        request.method == 'POST') {
      if (rpcOffline) throw const SocketException('hors ligne');
      final p = profile!;
      final reason =
          grantRefusal ?? ((p['freezes'] as int) >= 2 ? 'full' : null);
      if (reason == null) p['freezes'] = (p['freezes'] as int) + 1;
      return http.Response(
          jsonEncode(
              {'granted': reason == null, 'reason': reason, 'profile': p}),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }
    return http.Response('{"message":"interdit"}', 403, request: request);
  });

  /// Refus « propre » forcé de `grant_rewarded_freeze` (ex. `daily_limit`).
  String? grantRefusal;

  List<Map<String, dynamic>> get offlineDaysSent => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/validate_offline_day'))
            jsonDecode(r.body) as Map<String, dynamic>,
      ];

  /// Chemins appelés, dans l'ordre (RPC et lectures de profiles).
  List<String> get paths => [for (final r in requests) r.url.path];

  List<Map<String, dynamic>> get quizzesSent => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/submit_quiz'))
            jsonDecode(r.body) as Map<String, dynamic>,
      ];

  List<Map<String, dynamic>> get answersSent => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/answer_question'))
            jsonDecode(r.body) as Map<String, dynamic>,
      ];

  List<int> get goalsSent => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/set_daily_goal'))
            (jsonDecode(r.body) as Map)['goal'] as int,
      ];
}

Map<String, dynamic> _profile({String? lastQuizAt, int dailyGoal = 2}) => {
      'xp': 900,
      'streak': 12,
      'freezes': 2,
      'last_played_day': dayKey(addDays(_today, -1)),
      'daily_goal': dailyGoal,
      'quiz_day': dayKey(addDays(_today, -1)),
      'quiz_count': 3,
      'last_quiz_at': lastQuizAt,
    };

final _local = PlayerProgress(
  onboardingDone: true,
  dailyGoal: 2,
  totalXp: 150,
  streak: Streak(count: 3, lastPlayed: _today, freezes: 1, playedDays: {
    _today,
  }),
  quizzesDay: _today,
  quizzesCount: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;

  Future<ProviderContainer> container({
    bool withClient = true,
    String? userId = 'joueur-1',
    PlayerProgress? local,
  }) async {
    SharedPreferences.setMockInitialValues({
      'progress_v1': jsonEncode((local ?? _local).toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final client = withClient
        ? SupabaseClient(
            'https://exemple.supabase.co',
            'sb_publishable_test',
            httpClient: server.client,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          )
        : null;
    if (client != null) addTearDown(client.dispose);
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _now),
      supabaseClientProvider.overrideWithValue(client),
      authUserIdProvider.overrideWithValue(userId),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => server = _FakeServer());

  test('mode local : pas de sync, aucun appel', () async {
    final c = await container(withClient: false, userId: null);
    expect(c.read(progressSyncProvider), isNull);
    c.read(progressControllerProvider.notifier).setGoalAndReminder(
          dailyGoal: 3,
          reminder: null,
        );
    await pumpEventQueue();
    expect(server.requests, isEmpty);
    expect(c.read(progressControllerProvider).totalXp, 150);
  });

  test('client configuré mais pas de session : aucun appel', () async {
    final c = await container(userId: null);
    final sync = c.read(progressSyncProvider)!;
    await sync.sync(force: true);
    await sync.pushDailyGoal(3);
    expect(server.requests, isEmpty);
  });

  test('serveur sans quiz (last_quiz_at null) : local conservé', () async {
    final c = await container();
    await c.read(progressSyncProvider)!.sync(force: true);

    final p = c.read(progressControllerProvider);
    expect(server.requests, isNotEmpty, reason: 'profil lu au lancement');
    expect(p.totalXp, 150);
    expect(p.streak.count, 3);
    expect(p.streak.freezes, 1);
    expect(p.quizzesOn(_today), 1);
  });

  test('serveur avec quiz (last_quiz_at renseigné) : local remplacé', () async {
    server.profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00');
    final c = await container();
    await c.read(progressSyncProvider)!.sync(force: true);

    final p = c.read(progressControllerProvider);
    expect(p.totalXp, 900);
    expect(p.streak.count, 12);
    expect(p.streak.freezes, 2);
    expect(p.streak.lastPlayed, addDays(_today, -1));
    expect(p.quizzesOn(_today), 1,
        reason: 'serveur à hier, local à aujourd\'hui : jauge locale gardée');
    expect(p.dailyGoal, 2, reason: 'objectif : choix local');
    // Cache local mis à jour.
    expect(c.read(progressRepositoryProvider).load().totalXp, 900);
  });

  test('changement d\'objectif : RPC set_daily_goal appelée', () async {
    final c = await container();
    c.read(progressSyncProvider);
    await pumpEventQueue();
    expect(server.goalsSent, isEmpty, reason: 'objectif identique');

    c.read(progressControllerProvider.notifier).setGoalAndReminder(
          dailyGoal: 3,
          reminder: null,
        );
    await pumpEventQueue();
    expect(server.goalsSent, [3]);
  });

  test('premier sync : objectif local différent envoyé', () async {
    server.profile = _profile(dailyGoal: 1);
    final c = await container();
    await c.read(progressSyncProvider)!.sync(force: true);
    expect(server.goalsSent, [2]);
  });

  test('échec réseau : objectif renvoyé au sync suivant', () async {
    final c = await container();
    final sync = c.read(progressSyncProvider)!;
    await pumpEventQueue();
    server.rpcOffline = true;

    c.read(progressControllerProvider.notifier).setGoalAndReminder(
          dailyGoal: 3,
          reminder: null,
        );
    await pumpEventQueue();
    expect(server.profile!['daily_goal'], 2, reason: 'envoi échoué');

    server.rpcOffline = false;
    await sync.sync(force: true);
    expect(server.goalsSent, [3, 3]);
    expect(server.profile!['daily_goal'], 3);
  });

  test('hors ligne : pas de crash, progression locale intacte', () async {
    server.offline = true;
    final c = await container();
    await c.read(progressSyncProvider)!.sync(force: true);
    expect(c.read(progressControllerProvider).totalXp, 150);
  });

  test('retour au premier plan : au plus un sync par intervalle', () async {
    final c = await container();
    final sync = c.read(progressSyncProvider)!;
    await pumpEventQueue();
    final before = server.requests.length;

    await sync.sync();
    await sync.sync();
    expect(server.requests.length, before, reason: 'délai minimal');
  });

  test('aucune écriture directe sur profiles (requêtes)', () async {
    server.profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00');
    final c = await container();
    await c.read(progressSyncProvider)!.sync(force: true);
    c.read(progressControllerProvider.notifier).setGoalAndReminder(
          dailyGoal: 1,
          reminder: null,
        );
    await pumpEventQueue();

    final onTable =
        server.requests.where((r) => r.url.path == '/rest/v1/profiles');
    expect(onTable, isNotEmpty);
    expect(onTable.every((r) => r.method == 'GET'), isTrue);
  });

  test('aucune écriture directe sur profiles (code source)', () {
    final write = RegExp(r'\.(update|insert|upsert|delete)\(');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in RegExp("from\\(\\s*['\"]profiles['\"]\\s*\\)")
          .allMatches(source)) {
        final end = source.indexOf(';', match.end);
        final chain = source.substring(match.end, end);
        expect(write.hasMatch(chain), isFalse, reason: file.path);
      }
    }
  });

  group('submit_quiz', () {
    QuizSubmission submission(
            [String id = 'quiz-1',
            String userId = 'joueur-1',
            DateTime? playedAt]) =>
        QuizSubmission(
          id: id,
          userId: userId,
          playedAt: playedAt ?? _now,
        );

    /// Sync créé et sync initial (lancement) terminé.
    Future<ProgressSync> started(ProviderContainer c) async {
      final sync = c.read(progressSyncProvider)!;
      await pumpEventQueue();
      return sync;
    }

    test('quiz terminé : envoyé, profil serveur appliqué', () async {
      final c = await container();
      expect(await (await started(c)).submitQuiz(submission()), 100,
          reason: 'XP accordés par le serveur renvoyés');

      expect(server.quizzesSent, hasLength(1));
      expect(server.quizzesSent.single, {'quiz_id': 'quiz-1'});

      final p = c.read(progressControllerProvider);
      expect(p.totalXp, 1000, reason: 'XP du serveur');
      expect(p.streak.count, 13);
      expect(p.quizzesOn(_today), 1);
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
    });

    test('hors ligne : mis en file, envoyé au sync suivant', () async {
      server.rpcOffline = true;
      final c = await container();
      final sync = await started(c);
      expect(await sync.submitQuiz(submission()), isNull,
          reason: 'pas encore validé');

      expect(c.read(progressControllerProvider).totalXp, 150,
          reason: 'calcul local conservé');
      expect(c.read(pendingQuizRepositoryProvider).load().single.id, 'quiz-1');

      server.rpcOffline = false;
      await sync.sync(force: true);
      expect(server.accepted, ['quiz-1'],
          reason: 'même identifiant (idempotence)');
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).totalXp, 1000);
    });

    test('file non vide : la progression locale n\'est pas remplacée',
        () async {
      server
        ..profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00')
        ..submitError = 'PT429';
      final c = await container();
      final sync = await started(c);
      expect(c.read(progressControllerProvider).totalXp, 900);

      server.profile!['xp'] = 5000;
      await sync.submitQuiz(submission());
      await sync.sync(force: true);

      expect(server.quizzesSent, hasLength(2), reason: 'réessayé au sync');
      expect(c.read(pendingQuizRepositoryProvider).load(), hasLength(1));
      expect(c.read(progressControllerProvider).totalXp, 900,
          reason: 'quiz en attente : local en avance, pas remplacé');
    });

    test('quiz refusé (22023) : abandonné, profil serveur appliqué', () async {
      server
        ..profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00')
        ..submitError = '22023';
      final c = await container();
      final sync = await started(c);
      await sync.submitQuiz(submission());
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);

      await sync.sync(force: true);
      expect(server.quizzesSent, hasLength(1), reason: 'pas renvoyé');
      expect(c.read(progressControllerProvider).totalXp, 900);
    });

    test('plusieurs quiz en attente : envoyés dans l\'ordre', () async {
      server.rpcOffline = true;
      final c = await container();
      final sync = await started(c);
      await sync.submitQuiz(submission('quiz-1'));
      await sync.submitQuiz(submission('quiz-2'));

      server.rpcOffline = false;
      await sync.sync(force: true);
      expect(server.accepted, ['quiz-1', 'quiz-2']);
      expect(c.read(progressControllerProvider).totalXp, 1100);
    });

    test('sans session : ni appel ni mise en file', () async {
      final c = await container(userId: null);
      await (await started(c)).submitQuiz(submission());
      expect(server.requests, isEmpty);
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
    });

    test('quiz d\'un autre compte : ignoré', () async {
      final c = await container();
      await (await started(c)).submitQuiz(submission('quiz-1', 'autre'));
      expect(server.quizzesSent, isEmpty);
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
    });

    test('file : quiz d\'un autre compte abandonné sans envoi', () async {
      final c = await container();
      final queue = c.read(pendingQuizRepositoryProvider);
      await queue.add(submission('ancien-compte', 'autre'));
      await queue.add(submission('quiz-1'));
      await (await started(c)).sync(force: true);

      expect(server.accepted, ['quiz-1']);
      expect(queue.isEmpty, isTrue);
    });

    test('file : quiz de plus de 6 h abandonné sans envoi', () async {
      final c = await container();
      final queue = c.read(pendingQuizRepositoryProvider);
      await queue.add(submission(
          'trop-vieux', 'joueur-1', _now.subtract(const Duration(hours: 7))));
      await queue.add(submission(
          'recent', 'joueur-1', _now.subtract(const Duration(hours: 5))));
      await (await started(c)).sync(force: true);

      expect(server.accepted, ['recent']);
      expect(queue.isEmpty, isTrue);
    });

    for (final code in ['22P02', '22003', '23505', 'P0002']) {
      test('refus définitif ($code) : la file n\'est pas bloquée', () async {
        server.submitError = code;
        final c = await container();
        final sync = await started(c);
        await sync.submitQuiz(submission('quiz-1'));
        server.submitError = null;
        await sync.submitQuiz(submission('quiz-2'));

        expect(server.accepted, ['quiz-2']);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
      });
    }

    group('fin de quiz (QuizController)', () {
      // Quiz servi : questions sans bonne réponse, corrigées par le serveur.
      final served = [
        for (var i = 1; i <= 10; i++)
          Question.fromServerJson({
            'position': i,
            'category': 'divers',
            'question': 'Question $i',
            'answers': ['a', 'b', 'c', 'd'],
            'difficulty': 1,
          }),
      ];

      /// Bonne réponse (position 0) partout, sauf à la 2e question.
      Future<void> play(ProviderContainer c, List<Question> questions,
          {String? quizId}) async {
        final quiz = c.read(quizControllerProvider.notifier)
          ..start(questions,
              mode: QuizMode.mix,
              quizId: quizId,
              userId: quizId == null ? null : 'joueur-1');
        for (var i = 0; i < questions.length; i++) {
          final q = c.read(quizControllerProvider).current;
          final good = quizId == null ? q.correctIndex : 0;
          await quiz.answer(i == 1 ? (good + 1) % 4 : good);
          expect(quiz.next(), i < questions.length - 1);
        }
      }

      test('quiz servi : réponses corrigées puis quiz soumis', () async {
        final c = await container();
        await started(c);
        await play(c, served, quizId: 'quiz-servi');
        final state = c.read(quizControllerProvider);
        expect(state.isFinished, isTrue);
        expect(state.score, 9);
        expect(state.questions.every((q) => q.isRevealed), isTrue,
            reason: 'corrections gardées pour l\'écran Résultats');
        expect(state.questions.first.explanation, 'Explication 1');
        await pumpEventQueue();

        expect(server.answersSent, hasLength(10));
        expect(server.answersSent[1]['choice'], 1);
        expect([
          for (final a in server.answersSent) a['position']
        ], [
          for (var i = 1; i <= 10; i++) i
        ], reason: 'réponse envoyée par position, jamais par identifiant');
        expect(server.answersSent.every((a) => !a.containsKey('question_id')),
            isTrue);
        expect(server.answersSent.every((a) => a['quiz_id'] == 'quiz-servi'),
            isTrue);
        expect(
            server.answersSent.every((a) =>
                a['time_ms'] is int &&
                (a['time_ms'] as int) >= QuizSubmission.minMs &&
                (a['time_ms'] as int) <= QuizSubmission.maxMs),
            isTrue);
        expect(server.quizzesSent.single, {'quiz_id': 'quiz-servi'});
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
        expect(c.read(quizControllerProvider).serverXp, 100,
            reason: 'XP du serveur affichés sur l\'écran Résultats');
      });

      test('quiz local en mode Supabase : jamais soumis (hors classement)',
          () async {
        final c = await container();
        await started(c);
        final local = [
          for (var i = 1; i <= 10; i++)
            Question(
              id: 'q-$i',
              category: 'divers',
              question: 'Question $i',
              answers: const ['a', 'b', 'c', 'd'],
              correctIndex: 0,
              explanation: '',
              difficulty: 1,
            ).shuffled(Random(i)),
        ];
        await play(c, local);
        await pumpEventQueue();
        expect(c.read(quizControllerProvider).isFinished, isTrue);
        expect(server.answersSent, isEmpty);
        expect(server.quizzesSent, isEmpty);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
        expect(server.offlineDaysSent, isEmpty,
            reason: 'journée déjà validée en local : rien à faire valider');
        expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
        expect(c.read(progressControllerProvider).totalXp, greaterThan(150),
            reason: 'calcul local affiché quand même');
      });

      test('mode local : aucun appel, rien en file', () async {
        final c = await container(withClient: false, userId: null);
        await play(c, [
          for (var i = 1; i <= 10; i++)
            Question(
              id: 'q-$i',
              category: 'divers',
              question: 'Question $i',
              answers: const ['a', 'b', 'c', 'd'],
              correctIndex: 0,
              explanation: '',
              difficulty: 1,
            ),
        ]);
        await pumpEventQueue();
        expect(server.requests, isEmpty);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
        expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
        expect(c.read(progressControllerProvider).totalXp, greaterThan(150),
            reason: 'calcul local');
      });
    });
  });

  group('mergeServerProgress : compteur du jour', () {
    final yesterday = addDays(_today, -1);
    ServerProfile server(DateTime? quizDay, int count) => ServerProfile(
          xp: 900,
          streak: 12,
          freezes: 2,
          lastPlayedDay: yesterday,
          dailyGoal: 2,
          quizDay: quizDay,
          quizCount: count,
          lastQuizAt: DateTime.utc(2026, 11, 25, 18),
        );

    test('jour local postérieur au serveur : compteur local gardé', () {
      final merged = mergeServerProgress(
          _local.copyWith(quizzesCount: 2), server(yesterday, 3));
      expect(merged.quizzesDay, _today);
      expect(merged.quizzesOn(_today), 2);
      expect(merged.streak.count, 12, reason: 'série : le serveur fait foi');
    });

    test('même jour : le plus grand des deux', () {
      expect(
          mergeServerProgress(_local, server(_today, 3)).quizzesOn(_today), 3);
      expect(
          mergeServerProgress(
                  _local.copyWith(quizzesCount: 4), server(_today, 3))
              .quizzesOn(_today),
          4);
    });

    test('jour serveur postérieur au local : compteur du serveur', () {
      final merged = mergeServerProgress(
          _local.copyWith(quizzesDay: yesterday, quizzesCount: 5),
          server(_today, 1));
      expect(merged.quizzesDay, _today);
      expect(merged.quizzesOn(_today), 1);
    });
  });

  group('série hors ligne (validate_offline_day)', () {
    final yesterday = addDays(_today, -1);

    /// Progression locale après un sync de la veille : identique au profil
    /// serveur (`_profile` avec `last_quiz_at`), journée pas encore validée.
    final synced = PlayerProgress(
      onboardingDone: true,
      dailyGoal: 2,
      totalXp: 900,
      streak: Streak(
          count: 12,
          lastPlayed: yesterday,
          freezes: 2,
          playedDays: {yesterday}),
      quizzesDay: yesterday,
      quizzesCount: 3,
    );

    Map<String, dynamic> serverProfile() =>
        _profile(lastQuizAt: '2026-11-25T18:00:00+00:00');

    final localQuestions = [
      for (var i = 1; i <= 10; i++)
        Question(
          id: 'q-$i',
          category: 'divers',
          question: 'Question $i',
          answers: const ['a', 'b', 'c', 'd'],
          correctIndex: 0,
          explanation: '',
          difficulty: 1,
        ),
    ];

    /// Quiz local (repli hors ligne) joué jusqu'au bout, tout juste.
    Future<void> playLocal(ProviderContainer c) async {
      final quiz = c.read(quizControllerProvider.notifier)
        ..start(localQuestions, mode: QuizMode.mix);
      for (var i = 0; i < localQuestions.length; i++) {
        await quiz.answer(c.read(quizControllerProvider).current.correctIndex);
        quiz.next();
      }
      expect(c.read(quizControllerProvider).isFinished, isTrue);
      await pumpEventQueue();
    }

    Future<ProgressSync> started(ProviderContainer c) async {
      final sync = c.read(progressSyncProvider)!;
      await pumpEventQueue();
      return sync;
    }

    test('quiz hors ligne → reconnexion → série intacte', () async {
      // RPC hors ligne (une lecture GET hors ligne est réessayée par le
      // client PostgREST, ce qui retarderait le sync).
      server
        ..profile = serverProfile()
        ..rpcOffline = true;
      final c = await container(local: synced);
      final sync = await started(c);

      await playLocal(c);
      await playLocal(c);
      final played = c.read(progressControllerProvider);
      expect(played.streak.count, 13, reason: 'journée validée en local');
      expect(played.quizzesOn(_today), 2);
      final pending = c.read(pendingOfflineDayRepositoryProvider).load();
      expect(pending, hasLength(1), reason: 'seul le 1er quiz valide le jour');
      expect(pending.single.userId, 'joueur-1');
      expect(pending.single.playedAt.isAtSameMomentAs(_now), isTrue);

      server.rpcOffline = false;
      await sync.sync(force: true);

      expect(
          server.offlineDaysSent,
          [
            for (var i = 0; i < 2; i++)
              {'played_at': _now.toUtc().toIso8601String()}
          ],
          reason: 'même journée renvoyée après un échec');
      expect(server.quizzesSent, isEmpty, reason: 'jamais soumis');
      expect(server.paths.indexOf('/rest/v1/rpc/validate_offline_day'),
          lessThan(server.paths.lastIndexOf('/rest/v1/profiles')),
          reason: 'journée validée avant de lire le profil serveur');
      final p = c.read(progressControllerProvider);
      expect(p.streak.count, 13, reason: 'série conservée');
      expect(p.streak.lastPlayed, _today);
      expect(p.streak.freezes, 2);
      expect(p.quizzesOn(_today), 2,
          reason: 'compteur du jour : quiz hors ligne suivants gardés');
      expect(p.totalXp, 900, reason: 'aucune XP accordée par le serveur');
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);

      // Sync suivant : rien à renvoyer, série toujours là.
      await sync.sync(force: true);
      expect(server.offlineDaysSent, hasLength(2));
      expect(c.read(progressControllerProvider).streak.count, 13);
    });

    test('témoin : sans journée en file, le profil serveur écrase la série',
        () async {
      server.profile = serverProfile();
      final c = await container(
          local: synced.copyWith(
              streak: synced.streak.copyWith(count: 13, lastPlayed: _today)));
      await (await started(c)).sync(force: true);
      expect(c.read(progressControllerProvider).streak.count, 12);
    });

    test('quiz local en ligne (P0002, PT429) : journée validée tout de suite',
        () async {
      server.profile = serverProfile();
      final c = await container(local: synced);
      await started(c);
      await playLocal(c);

      expect(server.offlineDaysSent, hasLength(1));
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 13);
    });

    test('jour déjà validé par un quiz servi : pas de double comptage',
        () async {
      server.profile = serverProfile()
        ..['streak'] = 13
        ..['last_played_day'] = dayKey(_today)
        ..['quiz_day'] = dayKey(_today)
        ..['quiz_count'] = 1;
      final c = await container(local: synced);
      await c
          .read(pendingOfflineDayRepositoryProvider)
          .add(OfflineDay(userId: 'joueur-1', playedAt: _now));
      await (await started(c)).sync(force: true);

      expect(server.offlineDaysSent, hasLength(1));
      final p = c.read(progressControllerProvider);
      expect(p.streak.count, 13);
      expect(p.quizzesOn(_today), 1);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
    });

    test('refus (plafond) : jauge du jour gardée, série du serveur', () async {
      server
        ..profile = serverProfile()
        ..validateRefusal = 'limit';
      final c = await container(local: synced);
      await started(c);
      await playLocal(c);

      expect(server.offlineDaysSent, hasLength(1));
      final p = c.read(progressControllerProvider);
      expect(p.streak.count, 12, reason: 'journée refusée par le serveur');
      expect(p.quizzesOn(_today), 1,
          reason: 'jour local postérieur au serveur : compteur gardé');
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
    });

    test('autre compte : abandonnée sans envoi', () async {
      server.profile = serverProfile();
      final c = await container(local: synced);
      await c
          .read(pendingOfflineDayRepositoryProvider)
          .add(OfflineDay(userId: 'autre', playedAt: _now));
      await (await started(c)).sync(force: true);

      expect(server.offlineDaysSent, isEmpty);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 12,
          reason: 'profil du compte connecté appliqué');
    });

    test('plus de 6 h : abandonnée sans envoi', () async {
      server.profile = serverProfile();
      final c = await container(local: synced);
      final days = c.read(pendingOfflineDayRepositoryProvider);
      await days.add(OfflineDay(
          userId: 'joueur-1',
          playedAt: _now.subtract(const Duration(hours: 6, minutes: 1))));
      await (await started(c)).sync(force: true);

      expect(server.offlineDaysSent, isEmpty);
      expect(days.isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 12);
    });

    test('moins de 6 h : envoyée', () async {
      server.profile = serverProfile();
      final c = await container(local: synced);
      await c.read(pendingOfflineDayRepositoryProvider).add(OfflineDay(
          userId: 'joueur-1',
          playedAt: _now.subtract(const Duration(hours: 5))));
      await (await started(c)).sync(force: true);

      expect(server.offlineDaysSent, hasLength(1));
      expect(c.read(progressControllerProvider).streak.count, 13);
    });

    test('erreur passagère : gardée, série locale pas écrasée', () async {
      server
        ..profile = serverProfile()
        ..validateError = 'PT429';
      final c = await container(local: synced);
      final sync = await started(c);
      await playLocal(c);
      await sync.sync(force: true);

      expect(server.offlineDaysSent, hasLength(2), reason: 'réessayée');
      expect(c.read(pendingOfflineDayRepositoryProvider).load(), hasLength(1));
      expect(c.read(progressControllerProvider).streak.count, 13);

      server.validateError = null;
      await sync.sync(force: true);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 13);
    });

    test('refus définitif (22023) : abandonnée, profil serveur appliqué',
        () async {
      server
        ..profile = serverProfile()
        ..validateError = '22023';
      final c = await container(local: synced);
      final sync = await started(c);
      await playLocal(c);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);

      await sync.sync(force: true);
      expect(server.offlineDaysSent, hasLength(1), reason: 'pas renvoyée');
      expect(c.read(progressControllerProvider).streak.count, 12);
    });

    test('ordre joué : journée hors ligne puis quiz servi', () async {
      server
        ..profile = serverProfile()
        ..rpcOffline = true;
      final c = await container(local: synced);
      await c.read(pendingOfflineDayRepositoryProvider).add(OfflineDay(
          userId: 'joueur-1',
          playedAt: _now.subtract(const Duration(hours: 2))));
      await c.read(pendingQuizRepositoryProvider).add(QuizSubmission(
          id: 'quiz-1',
          userId: 'joueur-1',
          playedAt: _now.subtract(const Duration(hours: 1))));
      final sync = await started(c);

      server.rpcOffline = false;
      await sync.sync(force: true);
      final rpcs = [
        for (final p in server.paths)
          if (p.contains('/rpc/') && !p.endsWith('set_daily_goal')) p
      ];
      expect(rpcs.toSet().toList(), [
        '/rest/v1/rpc/validate_offline_day',
        '/rest/v1/rpc/submit_quiz',
      ]);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
    });

    test('sans session : rien en file', () async {
      final c = await container(userId: null, local: synced);
      await playLocal(c);
      expect(server.requests, isEmpty);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 13,
          reason: 'progression locale');
    });

    test('mode 100 % local : inchangé', () async {
      final c = await container(withClient: false, userId: null, local: synced);
      await playLocal(c);
      expect(server.requests, isEmpty);
      expect(c.read(pendingOfflineDayRepositoryProvider).isEmpty, isTrue);
      expect(c.read(progressControllerProvider).streak.count, 13);
    });

    test('file : stockage et purge', () async {
      SharedPreferences.setMockInitialValues({});
      final days =
          PendingOfflineDayRepository(await SharedPreferences.getInstance());
      for (var i = 0; i < 7; i++) {
        await days.add(OfflineDay(
            userId: 'joueur-1', playedAt: _now.add(Duration(minutes: i))));
      }
      expect(days.load(), hasLength(PendingOfflineDayRepository.maxPending));
      expect(
          days
              .load()
              .first
              .playedAt
              .isAtSameMomentAs(_now.add(const Duration(minutes: 2))),
          isTrue,
          reason: 'les plus anciennes abandonnées');
      await days.clear();
      expect(days.isEmpty, isTrue);
    });
  });

  group('grantRewardedFreeze', () {
    test('serveur avec quiz : profil renvoyé appliqué', () async {
      server.profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00')
        ..['freezes'] = 0;
      final c = await container();
      final result = await c.read(progressSyncProvider)!.grantRewardedFreeze();

      expect(result.granted, isTrue);
      final p = c.read(progressControllerProvider);
      expect(p.streak.freezes, 1);
      expect(p.totalXp, 900, reason: 'profil serveur appliqué');
    });

    test('serveur sans quiz : gel ajouté localement', () async {
      server.profile = _profile()..['freezes'] = 0;
      final c = await container(
          local: _local.copyWith(streak: _local.streak.copyWith(freezes: 0)));
      await c.read(progressSyncProvider)!.grantRewardedFreeze();

      final p = c.read(progressControllerProvider);
      expect(p.streak.freezes, 1);
      expect(p.totalXp, 150, reason: 'progression locale conservée');
    });

    test('refus (plafond du jour) : rien d\'ajouté', () async {
      server.profile = _profile()..['freezes'] = 0;
      server.grantRefusal = 'daily_limit';
      final c = await container(
          local: _local.copyWith(streak: _local.streak.copyWith(freezes: 0)));
      final result = await c.read(progressSyncProvider)!.grantRewardedFreeze();

      expect(result.granted, isFalse);
      expect(result.reason, 'daily_limit');
      expect(c.read(progressControllerProvider).streak.freezes, 0);
    });

    test('sans session : erreur, aucun appel', () async {
      final c = await container(userId: null);
      await expectLater(c.read(progressSyncProvider)!.grantRewardedFreeze(),
          throwsStateError);
      expect(
          server.paths, isNot(contains('/rest/v1/rpc/grant_rewarded_freeze')));
    });

    test('journée hors ligne en attente : envoyée avant le gel', () async {
      server.profile = _profile(lastQuizAt: '2026-11-25T18:00:00+00:00')
        ..['freezes'] = 0;
      final c = await container();
      final sync = c.read(progressSyncProvider)!;
      server.rpcOffline = true;
      await sync.recordOfflineDay(_now.subtract(const Duration(minutes: 5)));
      server.rpcOffline = false;

      await sync.grantRewardedFreeze();
      final rpcs = server.paths.where((p) => p.contains('/rpc/')).toList();
      expect(rpcs.lastIndexOf('/rest/v1/rpc/validate_offline_day'),
          lessThan(rpcs.indexOf('/rest/v1/rpc/grant_rewarded_freeze')));
    });

    test('envoi en attente impossible : pas de gel demandé', () async {
      final c = await container();
      final sync = c.read(progressSyncProvider)!;
      server.validateError = 'PT429';
      await sync.recordOfflineDay(_now.subtract(const Duration(minutes: 5)));

      await expectLater(sync.grantRewardedFreeze(), throwsStateError);
      expect(await sync.readyForFreezeGrant(), isFalse);
      expect(
          server.paths, isNot(contains('/rest/v1/rpc/grant_rewarded_freeze')));
    });

    test('hors ligne : erreur, gels inchangés', () async {
      server.rpcOffline = true;
      final c = await container(
          local: _local.copyWith(streak: _local.streak.copyWith(freezes: 0)));
      await expectLater(c.read(progressSyncProvider)!.grantRewardedFreeze(),
          throwsA(anything));
      expect(c.read(progressControllerProvider).streak.freezes, 0);
    });
  });
}
