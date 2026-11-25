import '../engagement/dates.dart';
import 'streak.dart';

/// Objectif du jour proposé par défaut au premier lancement.
const defaultDailyGoal = 2;

/// Rappel proposé par défaut : 20 h 30 (minutes depuis minuit).
const defaultReminderMinutes = 20 * 60 + 30;

/// Progression du joueur, persistée localement.
class PlayerProgress {
  const PlayerProgress({
    this.onboardingDone = false,
    this.dailyGoal = defaultDailyGoal,
    this.reminderMinutes = defaultReminderMinutes,
    this.totalXp = 0,
    this.streak = const Streak(),
    this.quizzesDay,
    this.quizzesCount = 0,
    this.challengeDay,
    this.challengeScore = 0,
    this.challengeTotal = 0,
    this.dangerShownDay,
  });

  /// Consentement + objectif du jour passés.
  final bool onboardingDone;

  /// Objectif : 1, 2 ou 3 quiz par jour.
  final int dailyGoal;

  /// Heure du rappel en minutes depuis minuit ; null = pas de rappel.
  final int? reminderMinutes;
  final int totalXp;
  final Streak streak;

  /// Nombre de quiz terminés le jour [quizzesDay].
  final DateTime? quizzesDay;
  final int quizzesCount;

  /// Dernier défi du jour joué et son score.
  final DateTime? challengeDay;
  final int challengeScore;
  final int challengeTotal;

  /// Dernier jour où l'écran « Série en danger » a été montré.
  final DateTime? dangerShownDay;

  int quizzesOn(DateTime today) =>
      isSameDay(quizzesDay, today) ? quizzesCount : 0;

  bool goalReachedOn(DateTime today) => quizzesOn(today) >= dailyGoal;

  bool challengePlayedOn(DateTime today) => isSameDay(challengeDay, today);

  PlayerProgress copyWith({
    bool? onboardingDone,
    int? dailyGoal,
    int? Function()? reminderMinutes,
    int? totalXp,
    Streak? streak,
    DateTime? quizzesDay,
    int? quizzesCount,
    DateTime? challengeDay,
    int? challengeScore,
    int? challengeTotal,
    DateTime? dangerShownDay,
  }) =>
      PlayerProgress(
        onboardingDone: onboardingDone ?? this.onboardingDone,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        reminderMinutes:
            reminderMinutes == null ? this.reminderMinutes : reminderMinutes(),
        totalXp: totalXp ?? this.totalXp,
        streak: streak ?? this.streak,
        quizzesDay: quizzesDay ?? this.quizzesDay,
        quizzesCount: quizzesCount ?? this.quizzesCount,
        challengeDay: challengeDay ?? this.challengeDay,
        challengeScore: challengeScore ?? this.challengeScore,
        challengeTotal: challengeTotal ?? this.challengeTotal,
        dangerShownDay: dangerShownDay ?? this.dangerShownDay,
      );

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    DateTime? day(String key) =>
        json[key] == null ? null : parseDayKey(json[key] as String);
    return PlayerProgress(
      onboardingDone: json['onboardingDone'] as bool? ?? false,
      dailyGoal: json['dailyGoal'] as int? ?? defaultDailyGoal,
      reminderMinutes: json.containsKey('reminderMinutes')
          ? json['reminderMinutes'] as int?
          : defaultReminderMinutes,
      totalXp: json['totalXp'] as int? ?? 0,
      streak: json['streak'] == null
          ? const Streak()
          : Streak.fromJson(json['streak'] as Map<String, dynamic>),
      quizzesDay: day('quizzesDay'),
      quizzesCount: json['quizzesCount'] as int? ?? 0,
      challengeDay: day('challengeDay'),
      challengeScore: json['challengeScore'] as int? ?? 0,
      challengeTotal: json['challengeTotal'] as int? ?? 0,
      dangerShownDay: day('dangerShownDay'),
    );
  }

  Map<String, dynamic> toJson() {
    String? key(DateTime? d) => d == null ? null : dayKey(d);
    return {
      'onboardingDone': onboardingDone,
      'dailyGoal': dailyGoal,
      'reminderMinutes': reminderMinutes,
      'totalXp': totalXp,
      'streak': streak.toJson(),
      'quizzesDay': key(quizzesDay),
      'quizzesCount': quizzesCount,
      'challengeDay': key(challengeDay),
      'challengeScore': challengeScore,
      'challengeTotal': challengeTotal,
      'dangerShownDay': key(dangerShownDay),
    };
  }
}
