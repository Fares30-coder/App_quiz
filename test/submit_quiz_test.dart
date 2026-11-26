import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/backend/supabase_progress_source.dart';
import 'package:quizzeo/data/pending_quiz_repository.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/quiz_submission.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tool/generate_seed.dart';

QuizSubmission _submission(String id) => QuizSubmission(
      id: id,
      questionIds: [for (var i = 1; i <= 10; i++) 'q-$i'],
      choices: [0, null, 2, 3, 0, 0, 0, 0, 0, 1],
      timesMs: [for (var i = 1; i <= 10; i++) i * 1000],
      playedAt: DateTime.utc(2026, 11, 26, 19, 30),
    );

void main() {
  group('QuizSubmission', () {
    test('paramètres de la RPC submit_quiz', () {
      expect(_submission('abc').toRpcParams(), {
        'quiz_id': 'abc',
        'question_ids': [for (var i = 1; i <= 10; i++) 'q-$i'],
        'choices': [0, null, 2, 3, 0, 0, 0, 0, 0, 1],
        'times_ms': [for (var i = 1; i <= 10; i++) i * 1000],
        'played_at': '2026-11-26T19:30:00.000Z',
      });
    });

    test('aller-retour JSON (file locale)', () {
      final s = _submission('abc');
      final back = QuizSubmission.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.toRpcParams(), s.toRpcParams());
    });

    test('temps envoyé borné à 30 s', () {
      expect(submittedMs(const Duration(milliseconds: 1234)), 1234);
      expect(submittedMs(const Duration(seconds: 30, milliseconds: 40)),
          QuizSubmission.maxMs);
    });

    test('identifiant au format UUID v4, différent à chaque quiz', () {
      final v4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final ids = {for (var i = 0; i < 100; i++) randomUuid()};
      expect(ids, hasLength(100));
      expect(ids.every(v4.hasMatch), isTrue);
    });

    test('réponse du serveur', () {
      final result = SubmitQuizResult.fromJson({
        'quiz_id': 'abc',
        'duplicate': false,
        'score': 8,
        'total': 10,
        'xp_gained': 135,
        'xp_capped': false,
        'profile': {
          'xp': 1035,
          'streak': 4,
          'freezes': 1,
          'last_played_day': '2026-11-26',
          'daily_goal': 2,
          'quiz_day': '2026-11-26',
          'quiz_count': 2,
          'last_quiz_at': '2026-11-26T19:30:00+00:00',
        },
      });
      expect(result.xpGained, 135);
      expect(result.profile.xp, 1035);
      expect(result.profile.lastQuizAt, isNotNull);
    });

    test('seul le code 22023 est un refus définitif', () {
      expect(
          isRejectedQuiz(const PostgrestException(message: '', code: '22023')),
          isTrue);
      expect(
          isRejectedQuiz(const PostgrestException(message: '', code: 'PT429')),
          isFalse);
      expect(isRejectedQuiz(const SocketException('hors ligne')), isFalse);
    });
  });

  test('Question.originalIndex suit les mélanges successifs', () {
    const q = Question(
      id: 'q',
      category: 'divers',
      question: '?',
      answers: ['a', 'b', 'c', 'd'],
      correctIndex: 2,
      explanation: '',
      difficulty: 1,
    );
    expect(q.originalIndex(3), 3);
    final once = q.shuffled(Random(1));
    final twice = once.shuffled(Random(2));
    for (final s in [once, twice]) {
      for (var i = 0; i < 4; i++) {
        expect(q.answers[s.originalIndex(i)], s.answers[i]);
      }
      expect(s.originalIndex(s.correctIndex), q.correctIndex);
    }
  });

  group('PendingQuizRepository', () {
    late PendingQuizRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = PendingQuizRepository(await SharedPreferences.getInstance());
    });

    test('ajout et retrait dans l\'ordre', () async {
      await repo.add(_submission('a'));
      await repo.add(_submission('b'));
      expect([for (final s in repo.load()) s.id], ['a', 'b']);
      await repo.remove('a');
      expect([for (final s in repo.load()) s.id], ['b']);
      await repo.remove('b');
      expect(repo.isEmpty, isTrue);
    });

    test('taille plafonnée : les plus anciens sont abandonnés', () async {
      for (var i = 0; i < PendingQuizRepository.maxPending + 5; i++) {
        await repo.add(_submission('q$i'));
      }
      final ids = [for (final s in repo.load()) s.id];
      expect(ids, hasLength(PendingQuizRepository.maxPending));
      expect(ids.first, 'q5');
    });
  });

  test('supabase/seed.sql est à jour avec assets/questions.json', () {
    final questions = [
      for (final q
          in jsonDecode(File(questionsPath).readAsStringSync()) as List)
        q as Map<String, dynamic>,
    ];
    expect(File(seedPath).readAsStringSync(), seedSql(questions),
        reason: 'relancer : dart run tool/generate_seed.dart');
  });
}
