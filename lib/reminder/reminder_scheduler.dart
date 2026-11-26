import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engagement/progress_controller.dart';
import 'notification_service.dart';
import 'reminder_schedule.dart';

/// Garde les rappels programmés en phase avec la progression : au démarrage,
/// au changement d'heure (ou désactivation), et quand le premier quiz du jour
/// est terminé (le rappel du jour passe alors au lendemain).
class ReminderScheduler {
  ReminderScheduler(this._ref);

  final Ref _ref;
  Future<void> _last = Future.value();

  /// Replanifie. Les appels sont mis en file pour ne jamais se chevaucher.
  Future<void> reschedule() {
    final slots = reminderSlots(
      _ref.read(progressControllerProvider),
      _ref.read(clockProvider)(),
    );
    final service = _ref.read(notificationServiceProvider);
    return _last = _last.then((_) => service.replaceReminders(slots));
  }

  /// Demande l'autorisation puis replanifie (iOS n'enregistre rien sans elle).
  Future<bool> requestPermission() async {
    final granted =
        await _ref.read(notificationServiceProvider).requestPermission();
    await reschedule();
    return granted;
  }
}

/// À lire une fois au démarrage (voir `RootGate`) pour activer la replanification.
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final scheduler = ReminderScheduler(ref);
  ref.listen(
    progressControllerProvider.select(reminderInputs),
    (_, __) => scheduler.reschedule(),
    fireImmediately: true,
  );
  return scheduler;
});
