import '../engagement/dates.dart';

/// Ligne `public.profiles` du joueur (lecture seule côté client).
///
/// XP, série, gels et compteurs sont écrits uniquement par le serveur
/// (`submit_quiz()`, règle sécurité n° 3 de `supabase/README.md`).
class ServerProfile {
  const ServerProfile({
    required this.xp,
    required this.streak,
    required this.freezes,
    required this.lastPlayedDay,
    required this.dailyGoal,
    required this.quizDay,
    required this.quizCount,
    required this.lastQuizAt,
  });

  /// Colonnes lues (aucune autre donnée n'est demandée).
  static const columns = 'xp, streak, freezes, last_played_day, daily_goal, '
      'quiz_day, quiz_count, last_quiz_at';

  final int xp;
  final int streak;
  final int freezes;
  final DateTime? lastPlayedDay;
  final int dailyGoal;

  /// Nombre de quiz terminés le jour [quizDay].
  final DateTime? quizDay;
  final int quizCount;

  /// Dernier quiz validé par le serveur ; `null` tant qu'aucun quiz n'a été
  /// soumis (la progression locale fait alors foi).
  final DateTime? lastQuizAt;

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    DateTime? day(String key) =>
        json[key] == null ? null : parseDayKey(json[key] as String);
    return ServerProfile(
      xp: (json['xp'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      freezes: (json['freezes'] as num?)?.toInt() ?? 0,
      lastPlayedDay: day('last_played_day'),
      dailyGoal: (json['daily_goal'] as num?)?.toInt() ?? 2,
      quizDay: day('quiz_day'),
      quizCount: (json['quiz_count'] as num?)?.toInt() ?? 0,
      lastQuizAt: json['last_quiz_at'] == null
          ? null
          : DateTime.parse(json['last_quiz_at'] as String),
    );
  }
}
