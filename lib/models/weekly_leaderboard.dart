import '../engagement/dates.dart';

/// Une ligne du classement : rang, pseudo et XP de la semaine.
/// Aucun identifiant de compte n'est transmis par le serveur.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.xp,
    this.isMe = false,
  });

  /// Rang partagé en cas d'ex-aequo (1, 2, 2, 4…).
  final int rank;
  final String displayName;
  final int xp;

  /// Ligne du joueur courant.
  final bool isMe;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num).toInt(),
        displayName: json['display_name'] as String? ?? '',
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        isMe: json['is_me'] as bool? ?? false,
      );
}

/// Classement hebdo global renvoyé par la RPC `weekly_leaderboard()`.
///
/// Semaine du lundi 00:00 au dimanche 23:59, heure de Paris ; XP officielle
/// du serveur (quiz validés par `submit_quiz()`).
class WeeklyLeaderboard {
  const WeeklyLeaderboard({
    required this.weekStart,
    required this.weekEnd,
    required this.endsAt,
    required this.entries,
    required this.myRank,
    required this.myXp,
    required this.myName,
  });

  /// Lundi et dimanche de la semaine (jours calendaires de Paris).
  final DateTime weekStart;
  final DateTime weekEnd;

  /// Fin de la semaine (lundi suivant 00:00 à Paris).
  final DateTime endsAt;

  /// Top N, dans l'ordre d'affichage (stable entre ex-aequo).
  final List<LeaderboardEntry> entries;

  /// Rang du joueur, `null` s'il n'a pas encore d'XP cette semaine.
  final int? myRank;
  final int myXp;
  final String? myName;

  factory WeeklyLeaderboard.fromJson(Map<String, dynamic> json) {
    final me = json['me'] as Map<String, dynamic>? ?? const {};
    return WeeklyLeaderboard(
      weekStart: parseDayKey(json['week_start'] as String),
      weekEnd: parseDayKey(json['week_end'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      entries: [
        for (final e in json['entries'] as List? ?? const [])
          LeaderboardEntry.fromJson(e as Map<String, dynamic>),
      ],
      myRank: (me['rank'] as num?)?.toInt(),
      myXp: (me['xp'] as num?)?.toInt() ?? 0,
      myName: me['display_name'] as String?,
    );
  }
}
