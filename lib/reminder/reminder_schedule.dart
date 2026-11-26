/// Calcul du rappel quotidien (fonctions pures, testées).
///
/// Principe (maquette objectif.html) : pas de notification répétée, mais des
/// rappels ponctuels pour les prochains jours, reprogrammés à chaque
/// changement. Un jour déjà validé (au moins 1 quiz terminé) n'a pas de rappel.
library;

import '../engagement/dates.dart';
import '../models/player_progress.dart';

/// Nombre de jours programmés d'avance. Au-delà, plus de rappel tant que
/// l'app n'est pas rouverte : on ne relance pas indéfiniment.
const reminderDaysAhead = 7;

/// Un rappel à afficher à une date précise (heure locale).
class ReminderSlot {
  const ReminderSlot({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ReminderSlot &&
      other.id == id &&
      other.when == when &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, when, title, body);

  @override
  String toString() => 'ReminderSlot($id, $when, $body)';
}

/// Textes du rappel : neutres et bienveillants, jamais culpabilisants
/// (pas de « tu vas perdre ta série »).
const reminderMessages = [
  'Le défi du jour est prêt. 10 questions, ça te dit ?',
  'Une petite pause culture G ? Ton quiz du jour t\'attend.',
  '10 questions, environ 5 minutes : le défi du jour est là quand tu veux.',
  'Histoire, sciences, sport… Qu\'est-ce qui tombe aujourd\'hui ?',
  'Envie d\'apprendre un truc nouveau ? Le défi du jour est prêt.',
];

/// Texte du rappel pour [day] : change chaque jour, stable pour un jour donné.
String reminderMessageFor(DateTime day) {
  final index = daysBetween(DateTime(2026), day) % reminderMessages.length;
  return reminderMessages[index];
}

/// Premier jour à rappeler : aujourd'hui si l'heure n'est pas passée et que la
/// journée n'est pas encore validée, sinon demain.
DateTime firstReminderDay({
  required DateTime now,
  required int minutes,
  required bool playedToday,
}) {
  final today = dayOf(now);
  final todayAt = today.add(Duration(minutes: minutes));
  if (!playedToday && now.isBefore(todayAt)) return today;
  return addDays(today, 1);
}

/// Rappels à programmer pour la progression [p] à l'instant [now].
/// Liste vide si pas de rappel choisi ou premier lancement non terminé.
List<ReminderSlot> reminderSlots(PlayerProgress p, DateTime now) {
  final minutes = p.reminderMinutes;
  if (!p.onboardingDone || minutes == null) return const [];
  final first = firstReminderDay(
    now: now,
    minutes: minutes,
    playedToday: p.quizzesOn(dayOf(now)) > 0,
  );
  return [
    for (var i = 0; i < reminderDaysAhead; i++)
      _slot(i, addDays(first, i), minutes),
  ];
}

ReminderSlot _slot(int index, DateTime day, int minutes) => ReminderSlot(
      id: index,
      // DateTime local : l'heure murale reste juste aux changements d'heure.
      when: DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60),
      title: 'Quizzéo',
      body: reminderMessageFor(day),
    );

/// Ce qui, dans la progression, change les rappels programmés.
/// (Enregistrement : valeur comparable pour `select`.)
({bool onboardingDone, int? minutes, DateTime? playedDay}) reminderInputs(
  PlayerProgress p,
) =>
    (
      onboardingDone: p.onboardingDone,
      minutes: p.reminderMinutes,
      playedDay: p.quizzesCount > 0 ? p.quizzesDay : null,
    );
