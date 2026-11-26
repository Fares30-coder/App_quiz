import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/backend/supabase_progress_source.dart';
import 'package:quizzeo/data/pending_quiz_repository.dart';
import 'package:quizzeo/models/quiz_submission.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tool/generate_seed.dart';

QuizSubmission _submission(String id) => QuizSubmission(
      id: id,
      userId: 'joueur-1',
      playedAt: DateTime.utc(2026, 11, 26, 19, 30),
    );

void main() {
  group('QuizSubmission', () {
    test('paramètres de la RPC submit_quiz : identifiant de session seul', () {
      expect(_submission('abc').toRpcParams(), {'quiz_id': 'abc'},
          reason: 'questions, réponses et heure : enregistrées par le serveur');
    });

    test('aller-retour JSON (file locale)', () {
      final s = _submission('abc');
      final back = QuizSubmission.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.toRpcParams(), s.toRpcParams());
      expect(back.userId, 'joueur-1');
      expect(back.playedAt, s.playedAt);
      expect(s.toRpcParams().containsKey('user_id'), isFalse,
          reason: 'le serveur prend auth.uid()');
    });

    test('ancien format sans compte : compte vide (jamais envoyé)', () {
      final json = _submission('abc').toJson()..remove('userId');
      expect(QuizSubmission.fromJson(json).userId, isEmpty);
    });

    test('expiré au-delà de 6 h', () {
      final s = _submission('abc');
      expect(s.isExpiredAt(s.playedAt.add(const Duration(hours: 6))), isFalse);
      expect(
          s.isExpiredAt(s.playedAt.add(const Duration(hours: 6, minutes: 1))),
          isTrue);
    });

    test('temps envoyé borné de 0,5 à 30 s', () {
      expect(submittedMs(const Duration(milliseconds: 1234)), 1234);
      expect(submittedMs(const Duration(milliseconds: 100)), 500);
      expect(submittedMs(const Duration(seconds: 30, milliseconds: 40)),
          QuizSubmission.maxMs);
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

    test('refus définitifs : 22023, 22P02, 22003, 23505, P0002', () {
      for (final code in ['22023', '22P02', '22003', '23505', 'P0002']) {
        expect(
            isRejectedQuiz(PostgrestException(message: '', code: code)), isTrue,
            reason: code);
      }
      expect(
          isRejectedQuiz(const PostgrestException(message: '', code: '42501')),
          isFalse);
      expect(
          isRejectedQuiz(const PostgrestException(message: '', code: 'PT429')),
          isFalse);
      expect(isRejectedQuiz(const SocketException('hors ligne')), isFalse);
    });
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

    test('removeWhere et clear', () async {
      await repo.add(_submission('a'));
      await repo.add(_submission('b'));
      await repo.removeWhere((s) => s.id == 'a');
      expect([for (final s in repo.load()) s.id], ['b']);
      await repo.clear();
      expect(repo.isEmpty, isTrue);
    });

    test('ancienne file (v1, réponses choisies par l\'app) : ignorée, effacée',
        () async {
      SharedPreferences.setMockInitialValues({
        'pending_quizzes_v1': '[{"id":"ancien","userId":"joueur-1"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final legacy = PendingQuizRepository(prefs);
      expect(legacy.isEmpty, isTrue, reason: 'jamais renvoyée au serveur');
      await legacy.clear();
      expect(prefs.getString('pending_quizzes_v1'), isNull);
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
