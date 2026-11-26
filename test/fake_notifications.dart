import 'package:quizzeo/reminder/notification_service.dart';
import 'package:quizzeo/reminder/reminder_schedule.dart';

/// Faux service : enregistre les appels au lieu de toucher au téléphone.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({this.grant = true});

  bool grant;
  int permissionRequests = 0;
  int settingsOpened = 0;

  /// Rappels programmés actuellement (dernier `replaceReminders`).
  List<ReminderSlot> scheduled = const [];
  int replaceCalls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceReminders(List<ReminderSlot> slots) async {
    replaceCalls++;
    scheduled = List.of(slots);
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}
