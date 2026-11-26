import '../engagement/dates.dart';

/// État de la série (streak). Immuable ; la logique est dans `engagement/streak_rules.dart`.
class Streak {
  const Streak({
    this.count = 0,
    this.lastPlayed,
    this.freezes = 0,
    this.playedDays = const {},
    this.frozenDays = const {},
  });

  /// Nombre de jours de série.
  final int count;

  /// Dernier jour où un quiz a été terminé.
  final DateTime? lastPlayed;

  /// Gels en réserve.
  final int freezes;

  /// Jours récents joués / couverts par un gel (affichage de la semaine).
  final Set<DateTime> playedDays;
  final Set<DateTime> frozenDays;

  Streak copyWith({
    int? count,
    DateTime? lastPlayed,
    int? freezes,
    Set<DateTime>? playedDays,
    Set<DateTime>? frozenDays,
  }) =>
      Streak(
        count: count ?? this.count,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        freezes: freezes ?? this.freezes,
        playedDays: playedDays ?? this.playedDays,
        frozenDays: frozenDays ?? this.frozenDays,
      );

  factory Streak.fromJson(Map<String, dynamic> json) => Streak(
        count: json['count'] as int? ?? 0,
        lastPlayed: json['lastPlayed'] == null
            ? null
            : parseDayKey(json['lastPlayed'] as String),
        freezes: json['freezes'] as int? ?? 0,
        playedDays: {
          for (final k in json['playedDays'] as List? ?? const [])
            parseDayKey(k as String),
        },
        frozenDays: {
          for (final k in json['frozenDays'] as List? ?? const [])
            parseDayKey(k as String),
        },
      );

  Map<String, dynamic> toJson() => {
        'count': count,
        'lastPlayed': lastPlayed == null ? null : dayKey(lastPlayed!),
        'freezes': freezes,
        'playedDays': [for (final d in playedDays) dayKey(d)],
        'frozenDays': [for (final d in frozenDays) dayKey(d)],
      };
}
