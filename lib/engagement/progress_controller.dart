import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_repository.dart';
import '../models/player_progress.dart';
import 'dates.dart';
import 'streak_rules.dart';
import 'xp.dart';

/// Horloge injectable (tests).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ce que le quiz qui vient de se terminer a changé (écran Résultats, Série).
class QuizOutcome {
  const QuizOutcome({
    required this.xp,
    required this.levelBefore,
    required this.levelAfter,
    required this.streakValidatedNow,
    required this.streakCount,
    required this.quizzesToday,
    required this.dailyGoal,
    required this.goalReachedNow,
  });

  final QuizXp xp;
  final LevelProgress levelBefore;
  final LevelProgress levelAfter;

  /// Premier quiz de la journée : afficher l'écran « Série validée ».
  final bool streakValidatedNow;
  final int streakCount;
  final int quizzesToday;
  final int dailyGoal;

  /// L'objectif du jour vient d'être atteint avec ce quiz.
  final bool goalReachedNow;

  bool get leveledUp => levelAfter.level > levelBefore.level;
  bool get goalReached => quizzesToday >= dailyGoal;
}

/// Applique un quiz terminé à la progression (fonction pure).
({PlayerProgress progress, QuizOutcome outcome}) applyQuizCompleted(
  PlayerProgress p,
  QuizXp xp, {
  required DateTime now,
  required bool isDailyChallenge,
  required int score,
  required int total,
}) {
  final today = dayOf(now);
  final played = recordQuizPlayed(p.streak, today);
  final quizzesBefore = p.quizzesOn(today);
  final quizzesToday = quizzesBefore + 1;
  final totalXp = p.totalXp + xp.total;
  var next = p.copyWith(
    totalXp: totalXp,
    streak: played.streak,
    quizzesDay: today,
    quizzesCount: quizzesToday,
  );
  if (isDailyChallenge && !p.challengePlayedOn(today)) {
    next = next.copyWith(
      challengeDay: today,
      challengeScore: score,
      challengeTotal: total,
    );
  }
  return (
    progress: next,
    outcome: QuizOutcome(
      xp: xp,
      levelBefore: levelFor(p.totalXp),
      levelAfter: levelFor(totalXp),
      streakValidatedNow: played.validatedNow,
      streakCount: played.streak.count,
      quizzesToday: quizzesToday,
      dailyGoal: p.dailyGoal,
      goalReachedNow:
          quizzesBefore < p.dailyGoal && quizzesToday >= p.dailyGoal,
    ),
  );
}

/// L'écran « Série en danger » doit-il s'afficher à l'ouverture ?
/// Une fois par jour au plus, après l'heure du rappel (20 h 30 si aucun),
/// si la série n'est pas validée aujourd'hui et qu'aucun gel n'est en réserve.
bool shouldShowStreakDanger(PlayerProgress p, DateTime now) {
  final today = dayOf(now);
  if (!streakAtRisk(p.streak, today)) return false;
  if (p.streak.freezes > 0) return false;
  if (isSameDay(p.dangerShownDay, today)) return false;
  final minutes = now.hour * 60 + now.minute;
  return minutes >= (p.reminderMinutes ?? defaultReminderMinutes);
}

class ProgressController extends Notifier<PlayerProgress> {
  ProgressRepository get _repo => ref.read(progressRepositoryProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  PlayerProgress build() {
    final loaded = _repo.load();
    // Applique les jours manqués (gels / perte de série) dès l'ouverture.
    final settled = loaded.copyWith(
      streak: settleStreak(loaded.streak, dayOf(_now())),
    );
    if (settled.streak != loaded.streak) _repo.save(settled);
    return settled;
  }

  void _set(PlayerProgress next) {
    state = next;
    _repo.save(next);
  }

  /// Fin du premier lancement (consentement + objectif).
  void finishOnboarding({required int dailyGoal, required int? reminder}) {
    _set(state.copyWith(
      onboardingDone: true,
      dailyGoal: dailyGoal.clamp(1, 3),
      reminderMinutes: () => reminder,
    ));
    // TODO(etape-1b): programmer le rappel (flutter_local_notifications + timezone).
  }

  void setGoalAndReminder({required int dailyGoal, required int? reminder}) {
    _set(state.copyWith(
      dailyGoal: dailyGoal.clamp(1, 3),
      reminderMinutes: () => reminder,
    ));
  }

  QuizOutcome completeQuiz(
    QuizXp xp, {
    required bool isDailyChallenge,
    required int score,
    required int total,
  }) {
    final result = applyQuizCompleted(
      state,
      xp,
      now: _now(),
      isDailyChallenge: isDailyChallenge,
      score: score,
      total: total,
    );
    _set(result.progress);
    return result.outcome;
  }

  void markDangerShown() => _set(state.copyWith(dangerShownDay: dayOf(_now())));

  /// Gel obtenu (pub récompensée à l'étape 3, ou offert aux joueurs « sans pub »).
  void addStreakFreeze() =>
      _set(state.copyWith(streak: addFreeze(state.streak)));
}

final progressControllerProvider =
    NotifierProvider<ProgressController, PlayerProgress>(
  ProgressController.new,
);
