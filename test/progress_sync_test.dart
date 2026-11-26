import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizzeo/backend/auth_service.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/progress_sync.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/streak.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime(2026, 11, 26, 10);
final _today = dayOf(_now);

/// Faux serveur PostgREST : `profiles` en lecture, RPC `set_daily_goal`.
class _FakeServer {
  final requests = <http.Request>[];
  bool offline = false;
  bool rpcOffline = false;
  Map<String, dynamic>? profile = _profile();

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
    return http.Response('{"message":"interdit"}', 403, request: request);
  });

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
    expect(p.quizzesOn(_today), 0, reason: 'quiz comptés hier');
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
}
