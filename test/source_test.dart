import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/data/question_repository.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_session.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:quizzeo/screens/quiz_screen.dart';
import 'package:quizzeo/sound/sound_service.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/generate_seed.dart';

Map<String, dynamic> _localJson({String? source}) => {
      'id': 'div-1',
      'category': 'divers',
      'question': 'Locale ?',
      'answers': ['bonne', 'b', 'c', 'd'],
      'correctIndex': 0,
      'explanation': 'Explication locale',
      'difficulty': 1,
      if (source != null) 'source': source,
    };

/// Question telle que servie (sans bonne réponse, explication ni source).
Map<String, dynamic> _servedJson(int position, {Object? answer}) => {
      'position': position,
      'category': 'divers',
      'difficulty': 2,
      'question': 'Serveur $position ?',
      'answers': ['d', 'bonne', 'b', 'c'],
      'answer': answer,
    };

void main() {
  group('Question.source', () {
    test('lot hors ligne : source lue si présente, null sinon', () {
      expect(
          Question.fromJson(_localJson(source: 'Larousse')).source, 'Larousse');
      expect(Question.fromJson(_localJson()).source, isNull);
    });

    test('question servie : jamais de source avant la correction', () {
      final q = Question.fromServerJson(_servedJson(1));
      expect(q.source, isNull);
      expect(q.isRevealed, isFalse);
    });

    test('withCorrection : source reçue, ou null', () {
      final q = Question.fromServerJson(_servedJson(1));
      final withSource = q.withCorrection(1, 'Explication', source: 'Insee');
      expect(withSource.source, 'Insee');
      expect(withSource.correctIndex, 1);
      expect(withSource.explanation, 'Explication');
      expect(q.withCorrection(1, 'Explication').source, isNull);
    });

    test('shuffled garde la source', () {
      final q = Question.fromJson(_localJson(source: 'NASA'));
      expect(q.shuffled(Random(1)).source, 'NASA');
    });

    test('AnswerCorrection : source si présente, null si absente ou vide', () {
      Map<String, dynamic> json(Object? source) => {
            'correct': true,
            'correct_choice': 1,
            'explanation': 'Explication',
            'timed_out': false,
            'source': source,
          };
      expect(
          AnswerCorrection.fromJson(json('Britannica')).source, 'Britannica');
      expect(AnswerCorrection.fromJson(json(null)).source, isNull);
      expect(AnswerCorrection.fromJson(json('  ')).source, isNull);
      expect(
          AnswerCorrection.fromJson({
            'correct': false,
            'correct_choice': 2,
            'explanation': 'E',
            'timed_out': true,
          }).source,
          isNull);
    });

    test('reprise du défi : source des questions déjà répondues seulement', () {
      final quiz = ServedQuiz.fromJson({
        'quiz_id': 'quiz-1',
        'resumed': true,
        'total': 10,
        'position': 3,
        'seconds_left': 30,
        'questions': [
          _servedJson(1, answer: {
            'choice': 1,
            'correct': true,
            'correct_choice': 1,
            'explanation': 'Explication 1',
            'source': 'Larousse',
            'time_ms': 4000,
          }),
          _servedJson(2, answer: {
            'choice': null,
            'correct': false,
            'correct_choice': 1,
            'explanation': 'Explication 2',
            'source': null,
            'time_ms': 30000,
          }),
          _servedJson(3),
        ],
      });
      expect(quiz.answered.map((a) => a.source), ['Larousse', null]);
      expect(quiz.questions.map((q) => q.source), ['Larousse', null, null]);
    });

    test('seed : source écrite si présente, null sinon', () {
      final sql = seedSql([
        _localJson(source: 'L\'Équipe'),
        {..._localJson(), 'id': 'div-2'},
      ]);
      expect(sql, contains("'Explication locale', 'L''Équipe')"));
      expect(sql, contains("'Explication locale', null)"));
      expect(sql, contains('source = excluded.source'));
      expect(sql, contains('excluded.source, true)'));
    });
  });

  group('QuizScreen : source sous l\'explication', () {
    Future<ProviderContainer> pumpQuiz(
      WidgetTester tester, {
      required List<Question> questions,
      QuestionRepository? repository,
      String? quizId,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        questionRepositoryProvider.overrideWithValue(
            repository ?? QuestionRepository(questions: questions)),
        soundServiceProvider.overrideWithValue(const SilentSoundService()),
      ]);
      addTearDown(c.dispose);
      c.read(quizControllerProvider.notifier).start(questions,
          mode: QuizMode.mix,
          quizId: quizId,
          userId: quizId == null ? null : 'joueur-1',
          total: quizId == null ? null : 10);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: const QuizScreen()),
      ));
      return c;
    }

    Future<void> answerB(WidgetTester tester) async {
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(RegExp(r'^(Bien vu|Raté)')), findsOneWidget);
    }

    testWidgets('quiz servi : source affichée seulement après la réponse',
        (tester) async {
      final c = await pumpQuiz(tester,
          questions: [Question.fromServerJson(_servedJson(1))],
          repository: _FakeRepository(source: 'Insee'),
          quizId: 'quiz-1');
      expect(find.textContaining('Source'), findsNothing);

      await answerB(tester);

      expect(find.text('Source : Insee'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      c.read(quizControllerProvider.notifier).quit();
    });

    testWidgets('quiz servi sans source : rien affiché', (tester) async {
      final c = await pumpQuiz(tester,
          questions: [Question.fromServerJson(_servedJson(1))],
          repository: _FakeRepository(),
          quizId: 'quiz-1');

      await answerB(tester);

      expect(find.text('Explication 1'), findsOneWidget);
      expect(find.textContaining('Source'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      c.read(quizControllerProvider.notifier).quit();
    });

    testWidgets('quiz local : source du lot hors ligne affichée',
        (tester) async {
      final q = Question.fromJson(_localJson(source: 'Larousse'));
      final c = await pumpQuiz(tester, questions: [q, q]);

      await answerB(tester);

      expect(find.text('Source : Larousse'), findsOneWidget);
      c.read(quizControllerProvider.notifier).quit();
    });
  });
}

/// Dépôt sans réseau : corrige `answer` (bonne réponse : position 1) avec
/// [source] (null = pas de source).
class _FakeRepository extends QuestionRepository {
  _FakeRepository({this.source}) : super(questions: const []);

  final String? source;

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
        'source': source,
      });
}
