import '../models/streak.dart';
import 'dates.dart';

/// Règles de la série (validées) :
/// - 1 quiz terminé suffit pour valider la journée ;
/// - 1 gel protège 1 jour sans jeu (la série ne monte pas mais ne retombe pas à 0) ;
/// - 2 gels en réserve au maximum ; les gels s'appliquent automatiquement.
const maxFreezes = 2;

/// Nombre de jours d'historique conservés (affichage de la semaine).
const _historyDays = 14;

/// Applique les jours manqués depuis le dernier quiz : consomme les gels
/// si possible, sinon remet la série à 0. Idempotent pour un même [today].
Streak settleStreak(Streak s, DateTime today) {
  final last = s.lastPlayed;
  if (s.count == 0 || last == null) return s;
  final day = dayOf(today);
  final missed = <DateTime>[
    for (var d = addDays(last, 1); daysBetween(d, day) > 0; d = addDays(d, 1))
      if (!s.frozenDays.contains(d)) d,
  ];
  if (missed.isEmpty) return s;
  if (missed.length > s.freezes) {
    // Pas assez de gels : la série est perdue, les gels restent en réserve.
    return s.copyWith(count: 0);
  }
  return s.copyWith(
    freezes: s.freezes - missed.length,
    frozenDays: _prune({...s.frozenDays, ...missed}, day),
  );
}

/// Enregistre un quiz terminé [today]. `validatedNow` est vrai pour le
/// premier quiz de la journée (affichage de l'écran « Série validée »).
({Streak streak, bool validatedNow}) recordQuizPlayed(
  Streak s,
  DateTime today,
) {
  final day = dayOf(today);
  final settled = settleStreak(s, day);
  if (isSameDay(settled.lastPlayed, day)) {
    return (streak: settled, validatedNow: false);
  }
  return (
    streak: settled.copyWith(
      count: settled.count + 1,
      lastPlayed: day,
      playedDays: _prune({...settled.playedDays, day}, day),
    ),
    validatedNow: true,
  );
}

/// Ajoute un gel (pub récompensée, offre « sans pub »), plafonné à [maxFreezes].
Streak addFreeze(Streak s) =>
    s.copyWith(freezes: (s.freezes + 1).clamp(0, maxFreezes));

bool playedToday(Streak s, DateTime today) => isSameDay(s.lastPlayed, today);

/// Série en cours mais pas encore validée aujourd'hui.
bool streakAtRisk(Streak s, DateTime today) =>
    s.count > 0 && !playedToday(s, today);

enum DayStatus { played, frozen, missed, future }

DayStatus dayStatus(Streak s, DateTime day, DateTime today) {
  final d = dayOf(day);
  if (s.playedDays.contains(d)) return DayStatus.played;
  if (s.frozenDays.contains(d)) return DayStatus.frozen;
  if (daysBetween(today, d) >= 0) return DayStatus.future;
  return DayStatus.missed;
}

Set<DateTime> _prune(Set<DateTime> days, DateTime today) => {
      for (final d in days)
        if (daysBetween(d, today) < _historyDays) d
    };
