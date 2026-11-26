import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/streak_rules.dart';
import 'package:quizzeo/models/streak.dart';

void main() {
  final wed = DateTime(2026, 11, 25);
  DateTime d(int offset) => addDays(wed, offset);

  group('recordQuizPlayed', () {
    test('premier quiz : série à 1, validée', () {
      final r = recordQuizPlayed(const Streak(), wed);
      expect(r.streak.count, 1);
      expect(r.validatedNow, isTrue);
      expect(r.streak.lastPlayed, wed);
      expect(r.streak.playedDays, contains(wed));
    });

    test('1 quiz suffit : un 2e quiz le même jour ne change rien', () {
      final first = recordQuizPlayed(const Streak(), wed).streak;
      final second = recordQuizPlayed(first, wed.add(const Duration(hours: 5)));
      expect(second.streak.count, 1);
      expect(second.validatedNow, isFalse);
    });

    test('jours consécutifs : la série monte', () {
      var s = const Streak();
      for (var i = 0; i < 7; i++) {
        s = recordQuizPlayed(s, d(i)).streak;
      }
      expect(s.count, 7);
    });

    test('un jour manqué sans gel : la série repart à 1', () {
      final s = Streak(count: 6, lastPlayed: d(-2));
      final r = recordQuizPlayed(s, wed);
      expect(r.streak.count, 1);
      expect(r.validatedNow, isTrue);
    });

    test(
        'un jour manqué avec un gel : la série continue sans monter pour le jour gelé',
        () {
      final s = Streak(count: 6, lastPlayed: d(-2), freezes: 1);
      final r = recordQuizPlayed(s, wed);
      expect(r.streak.count, 7);
      expect(r.streak.freezes, 0);
      expect(r.streak.frozenDays, contains(d(-1)));
    });
  });

  group('settleStreak (gels automatiques)', () {
    test('hier joué : rien à faire', () {
      final s = Streak(count: 4, lastPlayed: d(-1), freezes: 2);
      expect(identical(settleStreak(s, wed), s), isTrue);
    });

    test('2 jours manqués et 2 gels : les deux gels sont consommés', () {
      final s = Streak(count: 4, lastPlayed: d(-3), freezes: 2);
      final r = settleStreak(s, wed);
      expect(r.count, 4);
      expect(r.freezes, 0);
      expect(r.frozenDays, {d(-2), d(-1)});
    });

    test('3 jours manqués et 2 gels : série perdue, gels conservés', () {
      final s = Streak(count: 4, lastPlayed: d(-4), freezes: 2);
      final r = settleStreak(s, wed);
      expect(r.count, 0);
      expect(r.freezes, 2);
    });

    test('idempotent : appeler deux fois ne consomme pas plus de gels', () {
      final s = Streak(count: 4, lastPlayed: d(-2), freezes: 2);
      final once = settleStreak(s, wed);
      final twice = settleStreak(once, wed);
      expect(once.freezes, 1);
      expect(twice.freezes, 1);
      expect(twice.count, 4);
    });

    test('un gel par jour : le lendemain, un 2e gel est consommé', () {
      final s = Streak(count: 4, lastPlayed: d(-2), freezes: 2);
      final day1 = settleStreak(s, wed);
      final day2 = settleStreak(day1, d(1));
      expect(day2.freezes, 0);
      expect(day2.frozenDays, {d(-1), wed});
      expect(day2.count, 4);
    });

    test('série à 0 : les gels ne sont pas consommés', () {
      final s = Streak(count: 0, lastPlayed: d(-5), freezes: 2);
      expect(settleStreak(s, wed).freezes, 2);
    });
  });

  group('gels', () {
    test('réserve plafonnée à 2', () {
      var s = const Streak();
      s = addFreeze(s);
      s = addFreeze(s);
      s = addFreeze(s);
      expect(s.freezes, maxFreezes);
      expect(maxFreezes, 2);
    });
  });

  group('affichage', () {
    test('streakAtRisk', () {
      expect(streakAtRisk(Streak(count: 3, lastPlayed: d(-1)), wed), isTrue);
      expect(streakAtRisk(Streak(count: 3, lastPlayed: wed), wed), isFalse);
      expect(streakAtRisk(const Streak(), wed), isFalse);
    });

    test('dayStatus', () {
      final s = Streak(
        count: 2,
        lastPlayed: d(-1),
        playedDays: {d(-2), d(-1)},
        frozenDays: {d(-3)},
      );
      expect(dayStatus(s, d(-1), wed), DayStatus.played);
      expect(dayStatus(s, d(-3), wed), DayStatus.frozen);
      expect(dayStatus(s, d(-4), wed), DayStatus.missed);
      expect(dayStatus(s, wed, wed), DayStatus.future);
      expect(dayStatus(s, d(2), wed), DayStatus.future);
    });

    test('JSON aller-retour', () {
      final s = Streak(
        count: 5,
        lastPlayed: wed,
        freezes: 1,
        playedDays: {wed, d(-1)},
        frozenDays: {d(-2)},
      );
      final r = Streak.fromJson(s.toJson());
      expect(r.count, 5);
      expect(r.lastPlayed, wed);
      expect(r.freezes, 1);
      expect(r.playedDays, {wed, d(-1)});
      expect(r.frozenDays, {d(-2)});
    });
  });

  group('dates', () {
    test('daysBetween traverse le changement d\'heure', () {
      expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    });

    test('formatShortDate', () {
      expect(formatShortDate(wed), 'mer. 25 nov.');
      expect(mondayOf(wed), DateTime(2026, 11, 23));
      expect(formatHour(20 * 60 + 30), '20 h 30');
    });
  });
}
