import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/backend/supabase_quiz_source.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/data/question_repository.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_session.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:quizzeo/quiz/report_controller.dart';
import 'package:quizzeo/screens/quiz_screen.dart';
import 'package:quizzeo/sound/sound_service.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Question telle que servie (sans bonne réponse ni explication).
Question _served(int position) => Question.fromServerJson({
      'position': position,
      'category': 'divers',
      'difficulty': 2,
      'question': 'Serveur $position ?',
      'answers': ['d', 'bonne', 'b', 'c'],
      'answer': null,
    });

const _local = Question(
  id: 'div-1',
  category: 'divers',
  question: 'Locale ?',
  answers: ['bonne', 'b', 'c', 'd'],
  correctIndex: 0,
  explanation: 'Locale',
  difficulty: 1,
);

/// Faux serveur PostgREST : `answer_question` et `report_question`.
class _FakeServer {
  final requests = <http.Request>[];

  /// Erreur de `report_question` (code SQLSTATE), null = succès.
  String? reportError;
  bool offline = false;

  /// Réponse de `report_question` retenue jusqu'à ce que le test la libère.
  Completer<void>? holdReport;

  late final client = MockClient((request) async {
    requests.add(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    switch (request.url.path) {
      case '/rest/v1/rpc/answer_question':
        return _json({
          'quiz_id': body['quiz_id'],
          'position': body['position'],
          'choice': body['choice'],
          'correct': body['choice'] == 1,
          'timed_out': body['choice'] == null,
          'time_ms': body['time_ms'],
          'correct_choice': 1,
          'explanation': 'Explication ${body['position']}',
        }, 200, request);
      case '/rest/v1/rpc/report_question':
        await holdReport?.future;
        if (offline) throw const SocketException('hors ligne');
        final error = reportError;
        if (error != null) {
          return _json({'code': error, 'message': 'refusé'}, 400, request);
        }
        return _json({'reported': true}, 200, request);
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

  Future<ProviderContainer> container({bool withServer = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    QuestionRepository repository;
    if (withServer) {
      final client = SupabaseClient(
        'https://exemple.supabase.co',
        'sb_publishable_test',
        httpClient: server.client,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      repository = QuestionRepository(
        questions: const [_local],
        remote: SupabaseQuizSource(client),
        userId: () => 'joueur-1',
      );
    } else {
      repository = QuestionRepository(questions: const [_local]);
    }
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      questionRepositoryProvider.overrideWithValue(repository),
      soundServiceProvider.overrideWithValue(const SilentSoundService()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Quiz servi, question 1 reçue (pas encore répondue).
  QuizController startServed(ProviderContainer c) {
    final quiz = c.read(quizControllerProvider.notifier);
    quiz.start([_served(1)],
        mode: QuizMode.mix, quizId: 'quiz-1', userId: 'joueur-1', total: 10);
    return quiz;
  }

  group('ReportController', () {
    test('RPC report_question : session, position et motif seulement',
        () async {
      final c = await container();
      final reports = c.read(reportControllerProvider.notifier);

      final result = await reports.report(
          quizId: 'quiz-1', position: 3, reason: ReportReason.ambiguous);

      expect(result, ReportResult.sent);
      expect(server.sent('report_question').single, {
        'p_quiz_id': 'quiz-1',
        'p_position': 3,
        'p_reason': 'ambigue',
      });
      expect(c.read(reportControllerProvider).statusOf('quiz-1', 3),
          ReportStatus.sent);
    });

    test('motifs : valeurs attendues par le serveur', () {
      expect([for (final r in ReportReason.values) r.param],
          ['fausse', 'ambigue', 'faute', 'autre']);
      expect([
        for (final r in ReportReason.values) r.label
      ], [
        'Réponse fausse',
        'Question ambiguë',
        'Faute ou coquille',
        'Autre',
      ]);
    });

    test('même question : un seul signalement par quiz', () async {
      final c = await container();
      final reports = c.read(reportControllerProvider.notifier);
      server.holdReport = Completer();

      final first = reports.report(
          quizId: 'quiz-1', position: 1, reason: ReportReason.wrongAnswer);
      expect(c.read(reportControllerProvider).statusOf('quiz-1', 1),
          ReportStatus.sending);
      expect(
          await reports.report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.other),
          ReportResult.ignored,
          reason: 'envoi en cours');
      server.holdReport!.complete();
      expect(await first, ReportResult.sent);
      expect(
          await reports.report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.typo),
          ReportResult.ignored,
          reason: 'déjà signalée');
      expect(server.sent('report_question'), hasLength(1));

      // Autre question, puis autre quiz : signalables.
      expect(
          await reports.report(
              quizId: 'quiz-1', position: 2, reason: ReportReason.typo),
          ReportResult.sent);
      expect(
          await reports.report(
              quizId: 'quiz-2', position: 1, reason: ReportReason.typo),
          ReportResult.sent);
      expect(server.sent('report_question'), hasLength(3));
    });

    test('erreur réseau : échec, question de nouveau signalable', () async {
      server.offline = true;
      final c = await container();
      final reports = c.read(reportControllerProvider.notifier);

      expect(
          await reports.report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.other),
          ReportResult.failed);
      expect(c.read(reportControllerProvider).statusOf('quiz-1', 1), isNull);

      server.offline = false;
      expect(
          await reports.report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.other),
          ReportResult.sent);
    });

    test('plafond du serveur (PT429) : trop de signalements', () async {
      server.reportError = 'PT429';
      final c = await container();
      expect(
          await c.read(reportControllerProvider.notifier).report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.other),
          ReportResult.tooMany);
    });

    test('sans serveur configuré : échec, sans plantage', () async {
      final c = await container(withServer: false);
      expect(
          await c.read(reportControllerProvider.notifier).report(
              quizId: 'quiz-1', position: 1, reason: ReportReason.other),
          ReportResult.failed);
    });

    test('canReport : quiz servi, question corrigée, pas encore signalée',
        () async {
      final c = await container();
      final quiz = startServed(c);
      bool can() => canReport(
          c.read(quizControllerProvider), c.read(reportControllerProvider));

      expect(can(), isFalse, reason: 'avant la réponse');
      await quiz.answer(1);
      expect(can(), isTrue);
      await c
          .read(reportControllerProvider.notifier)
          .report(quizId: 'quiz-1', position: 1, reason: ReportReason.other);
      expect(can(), isFalse, reason: 'déjà signalée');
      quiz.quit();
    });

    test('canReport : jamais en quiz local', () async {
      final c = await container(withServer: false);
      final quiz = c.read(quizControllerProvider.notifier)
        ..start(const [_local], mode: QuizMode.mix);
      await quiz.answer(0);
      expect(
          canReport(
              c.read(quizControllerProvider), c.read(reportControllerProvider)),
          isFalse);
    });
  });

  // Écran : faux dépôt (pas de client HTTP dans le temps simulé des tests
  // de widgets).
  group('QuizScreen, lien « Signaler »', () {
    late _FakeRepository repo;

    Future<ProviderContainer> pumpQuiz(WidgetTester tester,
        {bool served = true}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = _FakeRepository();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        questionRepositoryProvider.overrideWithValue(repo),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
      ]);
      addTearDown(c.dispose);
      final quiz = c.read(quizControllerProvider.notifier);
      if (served) {
        startServed(c);
      } else {
        quiz.start(const [_local, _local], mode: QuizMode.mix);
      }
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: const QuizScreen()),
      ));
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(RegExp(r'^(Bien vu|Raté)')), findsOneWidget);
      return c;
    }

    Future<void> report(WidgetTester tester, String label) async {
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      for (final l in [
        'Réponse fausse',
        'Question ambiguë',
        'Faute ou coquille',
        'Autre',
      ]) {
        expect(find.text(l), findsOneWidget);
      }
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('quiz servi : motif, confirmation, plus de second signalement',
        (tester) async {
      final c = await pumpQuiz(tester);
      final secondsLeft = c.read(quizControllerProvider).secondsLeft;

      await report(tester, 'Question ambiguë');

      expect(find.text('Merci, on vérifie.'), findsOneWidget);
      expect(repo.reports, ['quiz-1/1/ambigue']);
      expect(find.text('Signaler'), findsNothing);
      expect(find.text('Question signalée'), findsOneWidget);
      // Chrono arrêté depuis la réponse, quiz toujours jouable.
      await tester.pump(const Duration(seconds: 3));
      expect(c.read(quizControllerProvider).secondsLeft, secondsLeft);
      expect(c.read(quizControllerProvider).index, 0);
      expect(find.text('Question suivante'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      c.read(quizControllerProvider.notifier).quit();
    });

    testWidgets('quiz local : pas de lien', (tester) async {
      final c = await pumpQuiz(tester, served: false);
      expect(find.text('Signaler'), findsNothing);
      c.read(quizControllerProvider.notifier).quit();
    });

    testWidgets('erreur réseau : message court, lien de nouveau disponible',
        (tester) async {
      final c = await pumpQuiz(tester);
      repo.offline = true;

      await report(tester, 'Autre');

      expect(find.text('Signalement non envoyé. Réessaie plus tard.'),
          findsOneWidget);
      expect(find.text('Signaler'), findsOneWidget);
      expect(find.text('Question suivante'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      c.read(quizControllerProvider.notifier).quit();
    });

    testWidgets('feuille fermée sans motif : rien envoyé', (tester) async {
      final c = await pumpQuiz(tester);
      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(repo.reports, isEmpty);
      expect(find.text('Signaler'), findsOneWidget);
      c.read(quizControllerProvider.notifier).quit();
    });
  });
}

/// Dépôt sans réseau : corrige `answer` (bonne réponse : position 1) et
/// enregistre les signalements.
class _FakeRepository extends QuestionRepository {
  _FakeRepository() : super(questions: const [_local]);

  final reports = <String>[];

  /// Signalement en échec (réseau).
  bool offline = false;

  @override
  Future<AnswerCorrection> answer({
    required String quizId,
    required int position,
    required int? choice,
    required int timeMs,
  }) async =>
      AnswerCorrection.fromJson({
        'correct': choice == 1,
        'timed_out': choice == null,
        'time_ms': timeMs,
        'correct_choice': 1,
        'explanation': 'Explication $position',
      });

  @override
  Future<void> reportQuestion({
    required String quizId,
    required int position,
    required ReportReason reason,
  }) async {
    if (offline) throw const SocketException('hors ligne');
    reports.add('$quizId/$position/${reason.param}');
  }
}
