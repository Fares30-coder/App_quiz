import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/engagement/xp.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/reminder/notification_service.dart';
import 'package:quizzeo/reminder/reminder_schedule.dart';
import 'package:quizzeo/reminder/reminder_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notifications.dart';

/// Laisse passer les appels asynchrones (file de replanification).
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const h2030 = 20 * 60 + 30;
  final today = DateTime(2026, 11, 25);
  final tomorrow = addDays(today, 1);

  group('firstReminderDay', () {
    test('avant l\'heure, pas encore joué : aujourd\'hui', () {
      expect(
        firstReminderDay(
            now: DateTime(2026, 11, 25, 9), minutes: h2030, playedToday: false),
        today,
      );
    });

    test('avant l\'heure, journée déjà validée : demain', () {
      expect(
        firstReminderDay(
            now: DateTime(2026, 11, 25, 9), minutes: h2030, playedToday: true),
        tomorrow,
      );
    });

    test('heure passée : demain', () {
      expect(
        firstReminderDay(
            now: DateTime(2026, 11, 25, 21),
            minutes: h2030,
            playedToday: false),
        tomorrow,
      );
    });

    test('pile à l\'heure : demain (jamais dans le passé)', () {
      expect(
        firstReminderDay(
            now: DateTime(2026, 11, 25, 20, 30),
            minutes: h2030,
            playedToday: false),
        tomorrow,
      );
    });

    test('fin de mois : passe au 1er', () {
      expect(
        firstReminderDay(
            now: DateTime(2026, 11, 30, 22),
            minutes: h2030,
            playedToday: false),
        DateTime(2026, 12, 1),
      );
    });
  });

  group('reminderSlots', () {
    const ready = PlayerProgress(onboardingDone: true);
    final morning = DateTime(2026, 11, 25, 9);

    test('premier lancement non terminé : aucun rappel', () {
      expect(reminderSlots(const PlayerProgress(), morning), isEmpty);
    });

    test('« Pas de rappel » : aucun rappel', () {
      expect(
        reminderSlots(ready.copyWith(reminderMinutes: () => null), morning),
        isEmpty,
      );
    });

    test('un rappel par jour, à l\'heure choisie, 7 jours d\'avance', () {
      final slots = reminderSlots(ready, morning);
      expect(slots, hasLength(reminderDaysAhead));
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].when, DateTime(2026, 11, 25 + i, 20, 30));
        expect(slots[i].id, i);
      }
    });

    test('journée validée : le premier rappel passe au lendemain', () {
      final played = ready.copyWith(quizzesDay: today, quizzesCount: 1);
      final slots = reminderSlots(played, morning);
      expect(slots.first.when, DateTime(2026, 11, 26, 20, 30));
      expect(slots, hasLength(reminderDaysAhead));
    });

    test('quiz joué hier seulement : rappel aujourd\'hui', () {
      final p = ready.copyWith(quizzesDay: addDays(today, -1), quizzesCount: 2);
      expect(
          reminderSlots(p, morning).first.when, DateTime(2026, 11, 25, 20, 30));
    });

    test('heure murale gardée au passage à l\'heure d\'été', () {
      final p = ready.copyWith(reminderMinutes: () => 8 * 60);
      final slots = reminderSlots(p, DateTime(2026, 3, 27, 9));
      expect(slots.map((s) => s.when.hour).toSet(), {8});
      expect(slots.map((s) => s.when.minute).toSet(), {0});
    });
  });

  group('texte du rappel', () {
    test('varie d\'un jour à l\'autre, stable pour un même jour', () {
      for (var i = 0; i < 30; i++) {
        final day = addDays(today, i);
        expect(reminderMessageFor(day), reminderMessageFor(day));
        expect(reminderMessageFor(day),
            isNot(reminderMessageFor(addDays(day, 1))));
      }
    });

    test('tous les textes sont utilisés', () {
      final used = {
        for (var i = 0; i < reminderMessages.length; i++)
          reminderMessageFor(addDays(today, i)),
      };
      expect(used, reminderMessages.toSet());
    });

    test('ton bienveillant : jamais de culpabilisation', () {
      for (final m in reminderMessages) {
        expect(m.toLowerCase(),
            isNot(matches(RegExp('perdre|perdu|série|dernière chance|!'))));
      }
    });

    test('titre et texte des rappels programmés', () {
      final slots = reminderSlots(
          const PlayerProgress(onboardingDone: true), DateTime(2026, 11, 25));
      for (final s in slots) {
        expect(s.title, 'Quizzéo');
        expect(s.body, reminderMessageFor(dayOf(s.when)));
      }
    });
  });

  group('ReminderScheduler (Riverpod)', () {
    late ProviderContainer container;
    late FakeNotificationService fake;
    final now = DateTime(2026, 11, 25, 9);

    Future<void> start(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final instance = await SharedPreferences.getInstance();
      fake = FakeNotificationService();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        clockProvider.overrideWithValue(() => now),
        notificationServiceProvider.overrideWithValue(fake),
      ]);
      container.read(reminderSchedulerProvider);
      await settle();
    }

    tearDown(() => container.dispose());

    ProgressController progress() =>
        container.read(progressControllerProvider.notifier);

    QuizOutcome finishQuiz() => progress().completeQuiz(quizXp(const []),
        isDailyChallenge: false, score: 0, total: 10);

    test('premier lancement : rien programmé, puis rappel à la fin', () async {
      await start({});
      expect(fake.scheduled, isEmpty);

      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      await settle();
      expect(fake.scheduled.first.when, DateTime(2026, 11, 25, 20, 30));
    });

    test('démarrage : replanifie la progression enregistrée', () async {
      await start({
        'progress_v1':
            '{"onboardingDone":true,"reminderMinutes":${8 * 60 + 15}}',
      });
      expect(fake.replaceCalls, 1);
      // 9 h, 8 h 15 est passé : premier rappel demain.
      expect(fake.scheduled.first.when, DateTime(2026, 11, 26, 8, 15));
    });

    test('changement d\'heure puis désactivation', () async {
      await start({});
      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      await settle();

      progress().setReminder(12 * 60 + 30);
      await settle();
      expect(fake.scheduled.first.when, DateTime(2026, 11, 25, 12, 30));
      expect(fake.scheduled, hasLength(reminderDaysAhead));

      progress().setReminder(null);
      await settle();
      expect(fake.scheduled, isEmpty);
    });

    test('changer l\'objectif seul ne replanifie pas', () async {
      await start({});
      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      await settle();
      final calls = fake.replaceCalls;
      progress().setGoalAndReminder(dailyGoal: 3, reminder: h2030);
      await settle();
      expect(fake.replaceCalls, calls);
    });

    test('quiz terminé : le rappel du jour passe au lendemain', () async {
      await start({});
      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      await settle();
      expect(fake.scheduled.first.when.day, 25);

      finishQuiz();
      await settle();
      expect(fake.scheduled.first.when, DateTime(2026, 11, 26, 20, 30));

      // 2e quiz du jour : rien ne change, pas de replanification inutile.
      final calls = fake.replaceCalls;
      finishQuiz();
      await settle();
      expect(fake.replaceCalls, calls);
    });

    test('autorisation : demandée puis rappels reprogrammés', () async {
      await start({});
      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      await settle();
      final calls = fake.replaceCalls;

      final granted =
          await container.read(reminderSchedulerProvider).requestPermission();
      expect(granted, isTrue);
      expect(fake.permissionRequests, 1);
      expect(fake.replaceCalls, calls + 1);
    });

    test('autorisation refusée : réglage gardé, l\'app continue', () async {
      await start({});
      fake.grant = false;
      progress().finishOnboarding(dailyGoal: 2, reminder: h2030);
      final granted =
          await container.read(reminderSchedulerProvider).requestPermission();
      expect(granted, isFalse);
      expect(container.read(progressControllerProvider).reminderMinutes, h2030);
      expect(fake.scheduled, isNotEmpty);
    });
  });
}
