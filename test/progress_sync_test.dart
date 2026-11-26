import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizzeo/backend/auth_service.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:quizzeo/data/pending_quiz_repository.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/progress_sync.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_submission.dart';
import 'package:quizzeo/models/streak.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime(2026, 11, 26, 10);
final _today = dayOf(_now);

/// Faux serveur PostgREST : `profiles` en lecture, RPC `set_daily_goal` et
/// `submit_quiz`.
class _FakeServer {
  final requests = <http.Request>[];
  bool offline = false;
  bool rpcOffline = false;
  Map<String, dynamic>? profile = _profile();

  /// Réponse d'erreur de `submit_quiz` (code SQLSTATE), null = succès.
  String? submitError;

  /// Quiz validés (réponse 200), dans l'ordre.
  final accepted = <String>[];

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
    return http.Response('{"message":"interdit"}', 403, request: request);
  });

  List<Map<String, dynamic>> get quizzesSent => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/submit_quiz'))
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

  group('submit_quiz', () {
    QuizSubmission submission([String id = 'quiz-1']) => QuizSubmission(
          id: id,
          questionIds: [for (var i = 1; i <= 10; i++) 'q-$i'],
          choices: [0, 1, null, 0, 0, 0, 0, 0, 0, 0],
          timesMs: List.filled(10, 2000),
          playedAt: _now,
        );

    /// Sync créé et sync initial (lancement) terminé.
    Future<ProgressSync> started(ProviderContainer c) async {
      final sync = c.read(progressSyncProvider)!;
      await pumpEventQueue();
      return sync;
    }

    test('quiz terminé : envoyé, profil serveur appliqué', () async {
      final c = await container();
      await (await started(c)).submitQuiz(submission());

      expect(server.quizzesSent, hasLength(1));
      final body = server.quizzesSent.single;
      expect(body['quiz_id'], 'quiz-1');
      expect(body['question_ids'], hasLength(10));
      expect(body['choices'], [0, 1, null, 0, 0, 0, 0, 0, 0, 0]);
      expect(body['times_ms'], List.filled(10, 2000));
      expect(DateTime.parse(body['played_at'] as String).isAtSameMomentAs(_now),
          isTrue);

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
      await sync.submitQuiz(submission());

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

    test('sans session : mis en file, aucun appel', () async {
      final c = await container(userId: null);
      await (await started(c)).submitQuiz(submission());
      expect(server.requests, isEmpty);
      expect(c.read(pendingQuizRepositoryProvider).load(), hasLength(1));
    });

    group('fin de quiz (QuizController)', () {
      // 10 questions dont la bonne réponse d'origine est l'index 0, mélangées.
      final questions = [
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

      void play(ProviderContainer c, {required int count}) {
        final quiz = c.read(quizControllerProvider.notifier)
          ..start(questions.take(count).toList(), mode: QuizMode.mix);
        for (var i = 0; i < count; i++) {
          final q = c.read(quizControllerProvider).current;
          // Bonne réponse, sauf à la 2e question (première mauvaise affichée).
          quiz.answer(i == 1 ? (q.correctIndex + 1) % 4 : q.correctIndex);
          quiz.next();
        }
      }

      test('quiz de 10 questions : soumis en arrière-plan', () async {
        final c = await container();
        await started(c);
        play(c, count: 10);
        expect(c.read(quizControllerProvider).isFinished, isTrue);
        await pumpEventQueue();

        final body = server.quizzesSent.single;
        expect(body['question_ids'], [for (final q in questions) q.id]);
        final wrong =
            questions[1].originalIndex((questions[1].correctIndex + 1) % 4);
        expect(body['choices'], [0, wrong, 0, 0, 0, 0, 0, 0, 0, 0],
            reason: 'index d\'origine, pas l\'ordre affiché');
        expect(
            (body['times_ms'] as List)
                .every((t) => t is int && t >= 0 && t <= 30000),
            isTrue);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
      });

      test('quiz incomplet (moins de 10 questions) : non soumis', () async {
        final c = await container();
        play(c, count: 3);
        await pumpEventQueue();
        expect(server.quizzesSent, isEmpty);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
      });

      test('mode local : aucun appel, rien en file', () async {
        final c = await container(withClient: false, userId: null);
        play(c, count: 10);
        await pumpEventQueue();
        expect(server.requests, isEmpty);
        expect(c.read(pendingQuizRepositoryProvider).isEmpty, isTrue);
        expect(c.read(progressControllerProvider).totalXp, greaterThan(150),
            reason: 'calcul local');
      });
    });
  });
}
