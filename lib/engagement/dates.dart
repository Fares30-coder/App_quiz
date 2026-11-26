/// Outils de dates « jour calendaire » (heure locale), sans dépendance.
library;

/// Jour calendaire (minuit) de [date].
DateTime dayOf(DateTime date) => DateTime(date.year, date.month, date.day);

/// Nombre de jours calendaires entre [from] et [to] (insensible aux changements d'heure).
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
      to.year,
      to.month,
      to.day,
    ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

DateTime addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

bool isSameDay(DateTime? a, DateTime? b) =>
    a != null &&
    b != null &&
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day;

/// Clé stable `aaaa-mm-jj` (stockage).
String dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// Lundi de la semaine de [day].
DateTime mondayOf(DateTime day) => addDays(dayOf(day), 1 - day.weekday);

const _weekdaysShort = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _weekdayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// « mer. 25 nov. »
String formatShortDate(DateTime day) =>
    '${_weekdaysShort[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

/// « 25 nov. »
String formatDayMonth(DateTime day) => '${day.day} ${_months[day.month - 1]}';

/// « L », « M »… pour la rangée des jours.
String weekdayLetter(DateTime day) => _weekdayLetters[day.weekday - 1];

/// « 20 h 30 » à partir d'un nombre de minutes depuis minuit.
String formatHour(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h h ${m.toString().padLeft(2, '0')}';
}
