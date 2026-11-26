import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/xp.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/models/streak.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

QuizXp xpOf(int correct, {int total = 10}) => quizXp([
      for (var i = 0; i < total; i++)
        AnswerResult(
            correct: i < correct, elapsed: const Duration(seconds: 20)),
    ]);

void main() {
  final now = DateTime(2026, 11, 25, 9);
  final today = dayOf(now);

  group('applyQuizCompleted', () {
    test('premier quiz du jour : XP, série validée, objectif 1/2', () {
      final r = applyQuizCompleted(
        const PlayerProgress(totalXp: 50),
        xpOf(5),
        now: now,
        isDailyChallenge: true,
        score: 5,
        total: 10,
      );
      // 5 bonnes réponses d'affilée : combo x3, x4, x5 -> +15.
      expect(r.progress.totalXp, 50 + 50 + 15 + 20);
      expect(r.outcome.streakValidatedNow, isTrue);
      expect(r.outcome.streakCount, 1);
      expect(r.outcome.quizzesToday, 1);
      expect(r.outcome.goalReached, isFalse);
      expect(r.progress.challengePlayedOn(today), isTrue);
      expect(r.progress.challengeScore, 5);
    });

    test('2e quiz : objectif atteint, série inchangée', () {
      final first = applyQuizCompleted(const PlayerProgress(), xpOf(3),
          now: now, isDailyChallenge: false, score: 3, total: 10);
      final second = applyQuizCompleted(first.progress, xpOf(4),
          now: now.add(const Duration(hours: 2)),
          isDailyChallenge: false,
          score: 4,
          total: 10);
      expect(second.outcome.streakValidatedNow, isFalse);
      expect(second.outcome.goalReachedNow, isTrue);
      expect(second.outcome.quizzesToday, 2);
      expect(second.progress.streak.count, 1);
    });

    test('le défi du jour garde le premier score', () {
      final first = applyQuizCompleted(const PlayerProgress(), xpOf(7),
          now: now, isDailyChallenge: true, score: 7, total: 10);
      final again = applyQuizCompleted(first.progress, xpOf(2),
          now: now, isDailyChallenge: true, score: 2, total: 10);
      expect(again.progress.challengeScore, 7);
    });

    test('le compteur de quiz repart à 0 le lendemain', () {
      final p = PlayerProgress(quizzesDay: addDays(today, -1), quizzesCount: 3);
      expect(p.quizzesOn(today), 0);
    });

    test('montée de niveau détectée', () {
      final r = applyQuizCompleted(const PlayerProgress(totalXp: 90), xpOf(1),
          now: now, isDailyChallenge: false, score: 1, total: 10);
      expect(r.outcome.leveledUp, isTrue);
      expect(r.outcome.levelAfter.level, 2);
    });
  });

  group('shouldShowStreakDanger', () {
    final atRisk = PlayerProgress(
      streak: Streak(count: 5, lastPlayed: addDays(today, -1)),
    );

    test('après l\'heure du rappel, pas joué, aucun gel : oui', () {
      expect(
          shouldShowStreakDanger(atRisk, DateTime(2026, 11, 25, 21)), isTrue);
    });

    test('avant l\'heure du rappel : non', () {
      expect(
          shouldShowStreakDanger(atRisk, DateTime(2026, 11, 25, 19)), isFalse);
    });

    test('avec un gel en réserve : non', () {
      final p = atRisk.copyWith(
          streak: Streak(count: 5, lastPlayed: addDays(today, -1), freezes: 1));
      expect(shouldShowStreakDanger(p, DateTime(2026, 11, 25, 21)), isFalse);
    });

    test('déjà montré aujourd\'hui : non', () {
      final p = atRisk.copyWith(dangerShownDay: today);
      expect(shouldShowStreakDanger(p, DateTime(2026, 11, 25, 21)), isFalse);
    });
  });

  test('PlayerProgress JSON aller-retour (rappel désactivé conservé)', () {
    final p = PlayerProgress(
      onboardingDone: true,
      dailyGoal: 3,
      reminderMinutes: null,
      totalXp: 1234,
      quizzesDay: today,
      quizzesCount: 2,
      challengeDay: today,
      challengeScore: 8,
      challengeTotal: 10,
    );
    final r = PlayerProgress.fromJson(p.toJson());
    expect(r.onboardingDone, isTrue);
    expect(r.dailyGoal, 3);
    expect(r.reminderMinutes, isNull);
    expect(r.totalXp, 1234);
    expect(r.quizzesOn(today), 2);
    expect(r.challengeScore, 8);
  });

  test('défauts du premier lancement : 2 quiz, rappel 20 h 30', () {
    const p = PlayerProgress();
    expect(p.dailyGoal, 2);
    expect(p.reminderMinutes, 20 * 60 + 30);
  });

  group('contrôleurs (Riverpod + shared_preferences)', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
      ]);
    });

    tearDown(() => container.dispose());

    Question q(String id) => Question(
          id: id,
          category: 'geo',
          question: '?',
          answers: const ['a', 'b', 'c', 'd'],
          correctIndex: 0,
          explanation: '…',
          difficulty: 1,
        );

    test('quiz complet : XP, combo, série et persistance', () {
      final quiz = container.read(quizControllerProvider.notifier);
      quiz.start([q('1'), q('2'), q('3')], mode: QuizMode.dailyChallenge);

      expect(quiz.answer(0), isTrue);
      expect(container.read(quizControllerProvider).lastAnswerXp.total, 15);
      expect(quiz.next(), isTrue);
      expect(quiz.answer(0), isTrue);
      expect(quiz.next(), isTrue);
      expect(quiz.answer(0), isTrue);
      final s = container.read(quizControllerProvider);
      expect(s.combo, 3);
      expect(s.lastAnswerXp.total, 20); // 10 + 5 rapidité + 5 combo x3
      expect(quiz.next(), isFalse);

      final outcome = container.read(quizControllerProvider).outcome!;
      // 3 × 10 + 3 × 5 + 5 (combo x3) + 20 + 30 (sans faute) = 100
      expect(outcome.xp.total, 100);
      expect(outcome.streakValidatedNow, isTrue);

      final progress = container.read(progressControllerProvider);
      expect(progress.totalXp, 100);
      expect(progress.streak.count, 1);
      expect(progress.challengePlayedOn(today), isTrue);

      // Relecture depuis shared_preferences.
      final reloaded = container.read(progressRepositoryProvider).load();
      expect(reloaded.totalXp, 100);
      expect(reloaded.streak.count, 1);
    });

    test('une seule réponse par question', () {
      final quiz = container.read(quizControllerProvider.notifier);
      quiz.start([q('1'), q('2')], mode: QuizMode.mix);
      expect(quiz.answer(1), isFalse);
      expect(quiz.answer(0), isFalse);
      expect(container.read(quizControllerProvider).answers, hasLength(1));
    });

    test('abandon : rien n\'est compté', () {
      final quiz = container.read(quizControllerProvider.notifier);
      quiz.start([q('1'), q('2')], mode: QuizMode.mix);
      quiz.answer(0);
      quiz.quit();
      expect(container.read(progressControllerProvider).totalXp, 0);
      expect(container.read(progressControllerProvider).streak.count, 0);
    });

    test('premier lancement enregistré', () {
      container
          .read(progressControllerProvider.notifier)
          .finishOnboarding(dailyGoal: 3, reminder: null);
      final p = container.read(progressRepositoryProvider).load();
      expect(p.onboardingDone, isTrue);
      expect(p.dailyGoal, 3);
      expect(p.reminderMinutes, isNull);
    });
  });
}
