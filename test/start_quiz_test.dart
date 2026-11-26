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

Map<String, dynamic> _servedJson(String quizId) => {
      'quiz_id': quizId,
      'mode': 'daily',
      'category': null,
      'day': '2026-11-26',
      'expires_at': '2026-11-26T10:30:00+00:00',
      'questions': [
        for (var i = 1; i <= 10; i++)
          {
            'id': 'srv-$i',
            'category': 'divers',
            'difficulty': 2,
            'question': 'Serveur $i ?',
            'answers': ['d', 'bonne', 'b', 'c'],
          },
      ],
    };

/// Faux serveur PostgREST : `start_quiz` et `answer_question` (bonne
/// réponse : position 1).
class _FakeServer {
  final requests = <http.Request>[];

  /// Erreur de `start_quiz` (code SQLSTATE), null = succès.
  String? startError;
  bool offline = false;

  /// Réponse de `answer_question` retenue jusqu'à ce que le test la libère.
  Completer<void>? holdAnswer;

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('hors ligne');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    switch (request.url.path) {
      case '/rest/v1/rpc/start_quiz':
        final error = startError;
        if (error != null) {
          return _json({'code': error, 'message': 'refusé'}, 400, request);
        }
        return _json(_servedJson('quiz-${requests.length}'), 200, request);
      case '/rest/v1/rpc/answer_question':
        await holdAnswer?.future;
        if (offline) throw const SocketException('hors ligne');
        return _json({
          'quiz_id': body['quiz_id'],
          'question_id': body['question_id'],
          'choice': body['choice'],
          'correct': body['choice'] == 1,
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
      expect(start.questions, hasLength(10));
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
          userId: start.userId);
      return quiz;
    }

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
      expect(await quiz.answer(0), isFalse);
      expect(c.read(quizControllerProvider).score, 1);
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
}
