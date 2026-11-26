import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizzeo/backend/supabase_quiz_source.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/data/question_repository.dart';
import 'package:quizzeo/engagement/daily_challenge.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_session.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _today = DateTime(2026, 11, 26);

/// 21 questions locales : 3 par catégorie.
final _local = [
  for (final c in categories.keys)
    for (var i = 1; i <= 3; i++)
      Question(
        id: '$c-$i',
        category: c,
        question: '$c $i ?',
        answers: const ['bonne', 'b', 'c', 'd'],
        correctIndex: 0,
        explanation: 'Locale',
        difficulty: 1,
      ),
];

/// Question `srv-i` telle que servie (sans bonne réponse).
Map<String, dynamic> _questionJson(int i) => {
      'id': 'srv-$i',
      'category': 'divers',
      'difficulty': 2,
      'question': 'Serveur $i ?',
      'answers': ['d', 'bonne', 'b', 'c'],
      'answer': null,
    };

/// [answered] : nombre de questions déjà répondues (reprise du défi) ; la
/// 2e a dépassé le temps, les autres sont justes. Questions servies une à
/// une : les répondues puis la question en cours seulement.
Map<String, dynamic> _servedJson(String quizId,
        {int answered = 0, int? secondsLeft = 30}) =>
    {
      'quiz_id': quizId,
      'resumed': answered > 0,
      'mode': 'daily',
      'category': null,
      'day': '2026-11-26',
      'expires_at': '2026-11-26T10:30:00+00:00',
      'total': 10,
      'position': answered < 10 ? answered + 1 : null,
      'seconds_left': answered < 10 ? secondsLeft : null,
      'questions': [
        for (var i = 1; i <= answered && i <= 10; i++)
          {
            ..._questionJson(i),
            'answer': {
              'choice': i == 2 ? null : 1,
              'correct': i != 2,
              'correct_choice': 1,
              'explanation': 'Explication srv-$i',
              'time_ms': i == 2 ? 30000 : 4000,
            },
          },
        if (answered < 10) _questionJson(answered + 1),
      ],
    };

/// Faux serveur PostgREST : `start_quiz`, `next_question` et
/// `answer_question` (bonne réponse : position 1).
class _FakeServer {
  final requests = <http.Request>[];

  /// Erreur de `start_quiz` (code SQLSTATE), null = succès.
  String? startError;

  /// Détail de l'erreur de `start_quiz`.
  String? startErrorDetails;

  /// Réponses déjà enregistrées renvoyées par `start_quiz` (reprise).
  int resumedAnswers = 0;

  /// `seconds_left` renvoyé par `start_quiz` et `next_question`.
  int startSecondsLeft = 30;
  int nextSecondsLeft = 30;

  /// Décalage de la position renvoyée par `next_question` (quiz avancé
  /// ailleurs).
  int nextPositionShift = 0;
  bool offline = false;

  /// Réponse de `answer_question` retenue jusqu'à ce que le test la libère.
  Completer<void>? holdAnswer;

  /// Réponse de `next_question` retenue jusqu'à ce que le test la libère.
  Completer<void>? holdNext;

  /// `answer_question` : temps écoulé selon le serveur (réponse trop lente).
  bool serverTimeout = false;

  /// Questions répondues par quiz (reprise comprise).
  final _answered = <String, Set<String>>{};

  int _answeredCount(String quizId) =>
      resumedAnswers + (_answered[quizId]?.length ?? 0);

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('hors ligne');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    switch (request.url.path) {
      case '/rest/v1/rpc/start_quiz':
        final error = startError;
        if (error != null) {
          return _json({
            'code': error,
            'message': 'refusé',
            'details': startErrorDetails,
          }, 400, request);
        }
        return _json(
            _servedJson('quiz-${requests.length}',
                answered: resumedAnswers, secondsLeft: startSecondsLeft),
            200,
            request);
      case '/rest/v1/rpc/next_question':
        await holdNext?.future;
        if (offline) throw const SocketException('hors ligne');
        final done = _answeredCount(body['quiz_id'] as String);
        if (done == 0 || done >= 10) {
          return _json({'code': '22023', 'message': 'refusé'}, 400, request);
        }
        return _json({
          'quiz_id': body['quiz_id'],
          'total': 10,
          'position': done + 1 + nextPositionShift,
          'seconds_left': nextSecondsLeft,
          'question': _questionJson(done + 1 + nextPositionShift),
        }, 200, request);
      case '/rest/v1/rpc/answer_question':
        await holdAnswer?.future;
        if (offline) throw const SocketException('hors ligne');
        (_answered[body['quiz_id'] as String] ??= {})
            .add(body['question_id'] as String);
        final choice = serverTimeout ? null : body['choice'];
        return _json({
          'quiz_id': body['quiz_id'],
          'question_id': body['question_id'],
          'choice': choice,
          'correct': choice == 1,
          'timed_out': choice == null,
          'time_ms': serverTimeout ? 30000 : body['time_ms'],
          'correct_choice': 1,
          'explanation': 'Explication ${body['question_id']}',
        }, 200, request);
    }
    return http.Response('{"message":"interdit"}', 403, request: request);
  });

  List<Map<String, dynamic>> sent(String rpc) => [
        for (final r in requests)
          if (r.url.path.endsWith('/rpc/$rpc'))
            jsonDecode(r.body) as Map<String, dynamic>,
      ];
}

http.Response _json(Object body, int status, http.Request request) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'}, request: request);

void main() {
  late _FakeServer server;

  setUp(() => server = _FakeServer());

  QuestionRepository repository({
    bool withServer = true,
    String? userId = 'joueur-1',
    Duration timeout = const Duration(seconds: 6),
    DateTime Function()? now,
  }) {
    if (!withServer) return QuestionRepository(questions: _local);
    final client = SupabaseClient(
      'https://exemple.supabase.co',
      'sb_publishable_test',
      httpClient: server.client,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    return QuestionRepository(
      questions: _local,
      remote: SupabaseQuizSource(client),
      userId: () => userId,
      timeout: timeout,
      now: now,
    );
  }

  group('QuestionRepository.startQuiz', () {
    test('connecté : questions servies, sans bonne réponse ni explication',
        () async {
      final start = await repository()
          .startQuiz(mode: QuizMode.dailyChallenge, today: _today);

      expect(server.sent('start_quiz').single, {'mode': 'daily'});
      expect(start.isServed, isTrue);
      expect(start.quizId, 'quiz-1');
      expect(start.userId, 'joueur-1');
      expect(start.unranked, isNull);
      expect(start.questions, hasLength(1), reason: 'servies une à une');
      expect(start.total, 10);
      expect(start.questions.any((q) => q.isRevealed), isFalse);
      expect(start.questions.every((q) => q.explanation.isEmpty), isTrue);
      expect(start.questions.first.answers, ['d', 'bonne', 'b', 'c'],
          reason: 'ordre du serveur, jamais remélangé');
    });

    test('mode catégorie et mix : paramètres envoyés', () async {
      final repo = repository();
      await repo.startQuiz(
          mode: QuizMode.category, category: 'geo', today: _today);
      await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(server.sent('start_quiz'), [
        {'mode': 'category', 'category': 'geo'},
        {'mode': 'mix'},
      ]);
    });

    test('hors ligne : défi du jour local, hors classement', () async {
      server.offline = true;
      final start = await repository()
          .startQuiz(mode: QuizMode.dailyChallenge, today: _today);

      expect(start.isServed, isFalse);
      expect(start.unranked, UnrankedReason.offline);
      expect([for (final q in start.questions) q.id],
          [for (final q in pickDailyChallenge(_local, _today)) q.id]);
      expect(start.questions.every((q) => q.isRevealed), isTrue);
    });

    test('pas assez de questions sur le serveur (P0002) : quiz local',
        () async {
      server.startError = 'P0002';
      final start = await repository().startQuiz(
          mode: QuizMode.category, category: 'histoire', today: _today);

      expect(start.unranked, UnrankedReason.notEnoughQuestions);
      expect(start.questions, hasLength(3));
      expect(start.questions.every((q) => q.category == 'histoire'), isTrue);
    });

    test('limite de débit (PT429) : quiz local hors classement', () async {
      server.startError = 'PT429';
      final start =
          await repository().startQuiz(mode: QuizMode.mix, today: _today);
      expect(start.unranked, UnrankedReason.offline);
      expect(start.questions, hasLength(quizLength));
    });

    test('serveur trop lent : repli local après le délai', () async {
      final never = Completer<void>();
      final client = SupabaseClient(
        'https://exemple.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient((request) async {
          await never.future;
          return http.Response('{}', 200);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final repo = QuestionRepository(
        questions: _local,
        remote: SupabaseQuizSource(client),
        userId: () => 'joueur-1',
        timeout: const Duration(milliseconds: 20),
      );
      final start = await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(start.unranked, UnrankedReason.offline);
      expect(start.questions, hasLength(quizLength));
    });

    test('pas encore de session : aucun appel, hors classement', () async {
      final start = await repository(userId: null)
          .startQuiz(mode: QuizMode.mix, today: _today);
      expect(server.requests, isEmpty);
      expect(start.unranked, UnrankedReason.offline);
      expect(start.isServed, isFalse);
    });

    test('défi repris : réponses enregistrées, questions déjà corrigées',
        () async {
      server.resumedAnswers = 3;
      final start = await repository()
          .startQuiz(mode: QuizMode.dailyChallenge, today: _today);

      expect(start.isServed, isTrue);
      expect(start.answered, hasLength(3));
      expect([for (final a in start.answered) a.choice], [1, null, 1]);
      expect([for (final a in start.answered) a.correct], [true, false, true]);
      expect(start.answered[1].timeMs, 30000);
      expect([
        for (final q in start.questions) q.isRevealed
      ], [
        true,
        true,
        true,
        false
      ], reason: 'répondues + question en cours seulement');
      expect(start.total, 10);
      expect(start.questions[0].explanation, 'Explication srv-1');
      expect(start.questions[3].explanation, isEmpty);
    });

    test('défi déjà joué (23505) : erreur dédiée, aucun repli local', () async {
      server.startError = '23505';
      server.startErrorDetails = '{"score": 7, "total": 10}';
      await expectLater(
        repository().startQuiz(mode: QuizMode.dailyChallenge, today: _today),
        throwsA(isA<DailyChallengeAlreadyPlayed>()
            .having((e) => e.score, 'score', 7)
            .having((e) => e.total, 'total', 10)),
      );
    });

    test('défi déjà joué, détail illisible : score inconnu', () async {
      server.startError = '23505';
      server.startErrorDetails = 'illisible';
      await expectLater(
        repository().startQuiz(mode: QuizMode.dailyChallenge, today: _today),
        throwsA(isA<DailyChallengeAlreadyPlayed>()
            .having((e) => e.score, 'score', isNull)),
      );
    });

    test('échec du serveur : pas de nouvel appel pendant 1 min', () async {
      var now = DateTime(2026, 11, 26, 10);
      final repo = repository(now: () => now);
      server.offline = true;

      await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(server.requests, hasLength(1));

      server.offline = false;
      now = now.add(const Duration(seconds: 59));
      final local = await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(server.requests, hasLength(1), reason: 'attente en cours');
      expect(local.unranked, UnrankedReason.offline);

      now = now.add(const Duration(seconds: 2));
      final served = await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(server.requests, hasLength(2));
      expect(served.isServed, isTrue);
    });

    test('P0002 (catégorie trop petite) : pas d\'attente pour les autres modes',
        () async {
      final repo = repository();
      server.startError = 'P0002';
      await repo.startQuiz(
          mode: QuizMode.category, category: 'histoire', today: _today);
      server.startError = null;
      final served = await repo.startQuiz(mode: QuizMode.mix, today: _today);
      expect(served.isServed, isTrue);
    });

    test('mode 100 % local : aucun appel, pas de message', () async {
      final start = await repository(withServer: false)
          .startQuiz(mode: QuizMode.dailyChallenge, today: _today);
      expect(server.requests, isEmpty);
      expect(start.unranked, isNull);
      expect(start.questions, hasLength(dailyChallengeLength));
    });
  });

  group('QuizController, quiz servi', () {
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        questionRepositoryProvider.overrideWithValue(repository()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<QuizController> started(ProviderContainer c) async {
      final start = await c
          .read(questionRepositoryProvider)
          .startQuiz(mode: QuizMode.dailyChallenge, today: dayOf(_today));
      final quiz = c.read(quizControllerProvider.notifier);
      quiz.start(start.questions,
          mode: QuizMode.dailyChallenge,
          quizId: start.quizId,
          userId: start.userId,
          answered: start.answered,
          total: start.total,
          secondsLeft: start.secondsLeft);
      return quiz;
    }

    test('défi repris : continue à la 1re question sans réponse', () async {
      server.resumedAnswers = 3;
      final c = await container();
      final quiz = await started(c);

      var state = c.read(quizControllerProvider);
      expect(state.index, 3);
      expect(state.answers, hasLength(3));
      expect(state.score, 2, reason: 'corrections du serveur');
      expect(state.answers[1].elapsed, const Duration(seconds: 30));
      expect(state.locked, isFalse);
      expect(state.secondsLeft, questionSeconds);

      expect(await quiz.answer(1), isTrue);
      expect(server.sent('answer_question').single['question_id'], 'srv-4');
      state = c.read(quizControllerProvider);
      expect(state.score, 3);
      expect(state.combo, 2, reason: 'combo repris après la 3e réponse');
      quiz.quit();
    });

    test('défi repris, tout répondu : dernière question corrigée, puis fin',
        () async {
      server.resumedAnswers = 10;
      final c = await container();
      final quiz = await started(c);

      final state = c.read(quizControllerProvider);
      expect(state.index, 9);
      expect(state.answered, isTrue);
      expect(state.locked, isTrue);
      expect(state.selected, 1);
      expect(state.score, 9);
      expect(quiz.next(), isFalse);
      final done = c.read(quizControllerProvider);
      expect(done.isFinished, isTrue);
      expect(done.outcome!.xp.correctCount, 9);
      expect(server.sent('answer_question'), isEmpty);
      expect(
          c
              .read(progressControllerProvider)
              .challengePlayedOn(dayOf(c.read(clockProvider)())),
          isTrue);
    });

    test('correction du serveur : bonne réponse et explication révélées',
        () async {
      final c = await container();
      final quiz = await started(c);

      expect(await quiz.answer(1), isTrue);
      final state = c.read(quizControllerProvider);
      expect(state.answered, isTrue);
      expect(state.current.correctIndex, 1);
      expect(state.current.explanation, 'Explication srv-1');
      final sent = server.sent('answer_question').single;
      expect(sent['quiz_id'], 'quiz-1');
      expect(sent['question_id'], 'srv-1');
      expect(sent['choice'], 1);
      expect(sent['time_ms'], 500, reason: 'toucher immédiat : borné à 0,5 s');

      expect(quiz.next(), isTrue);
      await pumpEventQueue();
      expect(await quiz.answer(0), isFalse);
      expect(c.read(quizControllerProvider).score, 1);
    });

    test('question suivante demandée au serveur, chrono au chargement',
        () async {
      final c = await container();
      final quiz = await started(c);
      var state = c.read(quizControllerProvider);
      expect(state.total, 10);
      expect(state.questions, hasLength(1));
      expect(quiz.next(), isFalse, reason: 'pas encore répondu');
      expect(server.sent('next_question'), isEmpty);

      await quiz.answer(1);
      server.holdNext = Completer<void>();
      expect(quiz.next(), isTrue);
      expect(quiz.next(), isTrue, reason: 'chargement en cours : ignoré');
      state = c.read(quizControllerProvider);
      expect(state.loadingNext, isTrue);
      expect(state.index, 0, reason: 'reste sur la question corrigée');

      server.holdNext!.complete();
      await pumpEventQueue();
      state = c.read(quizControllerProvider);
      expect(server.sent('next_question'), [
        {'quiz_id': 'quiz-1'},
      ]);
      expect(state.loadingNext, isFalse);
      expect(state.index, 1);
      expect(state.current.id, 'srv-2');
      expect(state.current.isRevealed, isFalse);
      expect(state.locked, isFalse);
      expect(state.secondsLeft, questionSeconds);
      quiz.quit();
    });

    test('connexion perdue au chargement : « Réessayer » puis question 2',
        () async {
      final c = await container();
      final quiz = await started(c);
      await quiz.answer(1);
      server.offline = true;

      expect(quiz.next(), isTrue);
      await pumpEventQueue();
      var state = c.read(quizControllerProvider);
      expect(state.nextFailed, isTrue);
      expect(state.loadingNext, isFalse);
      expect(state.index, 0);
      expect(state.isFinished, isFalse);

      server.offline = false;
      await quiz.retryNext();
      state = c.read(quizControllerProvider);
      expect(state.nextFailed, isFalse);
      expect(state.index, 1);
      expect(state.current.id, 'srv-2');
      quiz.quit();
    });

    test('abandon pendant le chargement : question tardive ignorée', () async {
      final c = await container();
      final quiz = await started(c);
      await quiz.answer(1);
      server.holdNext = Completer<void>();

      quiz.next();
      await pumpEventQueue();
      quiz.quit();
      server.holdNext!.complete();
      await pumpEventQueue();

      final state = c.read(quizControllerProvider);
      expect(state.questions, isEmpty);
      expect(state.loadingNext, isFalse);
    });

    test('temps écoulé selon le serveur : réponse comptée fausse', () async {
      final c = await container();
      final quiz = await started(c);
      server.serverTimeout = true;

      expect(await quiz.answer(1), isFalse);
      final state = c.read(quizControllerProvider);
      expect(state.answered, isTrue);
      expect(state.timedOut, isTrue);
      expect(state.selected, isNull);
      expect(state.answers.single.correct, isFalse);
      expect(state.answers.single.elapsed, const Duration(seconds: 30));
      quiz.quit();
    });

    test('quiz servi joué en entier : 10 questions reçues une à une', () async {
      final c = await container();
      final quiz = await started(c);
      for (var i = 0; i < 10; i++) {
        expect(c.read(quizControllerProvider).current.id, 'srv-${i + 1}');
        await quiz.answer(1);
        final more = quiz.next();
        expect(more, i < 9);
        await pumpEventQueue();
      }
      final state = c.read(quizControllerProvider);
      expect(state.isFinished, isTrue);
      expect(state.score, 10);
      expect(state.outcome!.xp.correctCount, 10);
      expect(server.sent('next_question'), hasLength(9));
    });

    test('pendant la correction : réponse verrouillée, pas de 2e envoi',
        () async {
      final c = await container();
      final quiz = await started(c);
      server.holdAnswer = Completer<void>();

      final pending = quiz.answer(1);
      await pumpEventQueue();
      final waiting = c.read(quizControllerProvider);
      expect(waiting.waiting, isTrue);
      expect(waiting.locked, isTrue);
      expect(await quiz.answer(2), isFalse, reason: 'déjà répondu');
      expect(quiz.next(), isFalse, reason: 'correction attendue');

      server.holdAnswer!.complete();
      expect(await pending, isTrue);
      expect(server.sent('answer_question'), hasLength(1));
    });

    test('connexion perdue : réponse gardée, renvoyée par « Réessayer »',
        () async {
      final c = await container();
      final quiz = await started(c);
      server.offline = true;

      expect(await quiz.answer(2), isFalse);
      var state = c.read(quizControllerProvider);
      expect(state.answerFailed, isTrue);
      expect(state.waiting, isTrue);
      expect(state.answers, isEmpty);

      server.offline = false;
      expect(await quiz.retryAnswer(), isFalse, reason: 'réponse 2 fausse');
      state = c.read(quizControllerProvider);
      expect(state.answerFailed, isFalse);
      expect(state.answered, isTrue);
      expect(state.current.correctIndex, 1);
      final sent = server.sent('answer_question');
      expect(sent, hasLength(2));
      expect(sent.last, sent.first, reason: 'même choix, même temps');
    });

    test('défi repris : chrono du serveur, temps envoyé depuis l\'envoi',
        () async {
      server.resumedAnswers = 1;
      server.startSecondsLeft = 12;
      final c = await container();
      final quiz = await started(c);

      expect(c.read(quizControllerProvider).secondsLeft, 12,
          reason: 'temps restant selon le serveur, pas 30 s');
      await quiz.answer(1);
      expect(server.sent('answer_question').single['time_ms'],
          greaterThanOrEqualTo(18000),
          reason: '18 s déjà écoulées avant la reprise');
      quiz.quit();
    });

    test('défi repris après la fin du chrono : temps écoulé aussitôt',
        () async {
      server.resumedAnswers = 1;
      server.startSecondsLeft = 0;
      final c = await container();
      await started(c);
      await pumpEventQueue();

      final state = c.read(quizControllerProvider);
      expect(state.timedOut, isTrue);
      expect(state.answered, isTrue);
      final sent = server.sent('answer_question').single;
      expect(sent['choice'], isNull);
      expect(sent['time_ms'], 30000);
    });

    test('question suivante déjà servie : chrono restant du serveur', () async {
      server.nextSecondsLeft = 21;
      final c = await container();
      final quiz = await started(c);
      await quiz.answer(1);
      quiz.next();
      await pumpEventQueue();

      final state = c.read(quizControllerProvider);
      expect(state.index, 1);
      expect(state.secondsLeft, 21);
      quiz.quit();
    });

    test('question inattendue (quiz avancé ailleurs) : pas de « Réessayer »',
        () async {
      server.nextPositionShift = 1;
      final c = await container();
      final quiz = await started(c);
      await quiz.answer(1);
      quiz.next();
      await pumpEventQueue();

      var state = c.read(quizControllerProvider);
      expect(state.outOfSync, isTrue);
      expect(state.nextFailed, isFalse);
      expect(state.loadingNext, isFalse);
      expect(state.index, 0);
      await quiz.retryNext();
      state = c.read(quizControllerProvider);
      expect(server.sent('next_question'), hasLength(1),
          reason: 'aucun nouvel essai');
      quiz.quit();
      expect(c.read(quizControllerProvider).outOfSync, isFalse);
    });

    test('abandon pendant la correction : réponse tardive ignorée', () async {
      final c = await container();
      final quiz = await started(c);
      server.holdAnswer = Completer<void>();

      final pending = quiz.answer(1);
      await pumpEventQueue();
      quiz.quit();
      server.holdAnswer!.complete();

      expect(await pending, isFalse);
      final state = c.read(quizControllerProvider);
      expect(state.questions, isEmpty);
      expect(state.answers, isEmpty);
    });
  });

  group('ProgressController.markChallengePlayed', () {
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 26, 9)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('défi joué ailleurs : accueil cohérent, sans XP ni série', () async {
      final c = await container();
      final before = c.read(progressControllerProvider);
      c
          .read(progressControllerProvider.notifier)
          .markChallengePlayed(score: 7, total: 10);
      final p = c.read(progressControllerProvider);
      expect(p.challengePlayedOn(_today), isTrue);
      expect(p.challengeScore, 7);
      expect(p.challengeTotal, 10);
      expect(p.totalXp, before.totalXp);
      expect(p.quizzesOn(_today), before.quizzesOn(_today));
    });

    test('score déjà connu en local : conservé', () async {
      final c = await container();
      final progress = c.read(progressControllerProvider.notifier);
      progress.markChallengePlayed(score: 8, total: 10);
      progress.markChallengePlayed();
      expect(c.read(progressControllerProvider).challengeScore, 8);
    });
  });
}
