import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_schedule.dart';

/// Notifications locales du rappel quotidien. Remplacé par un faux dans les tests.
abstract class NotificationService {
  /// Demande l'autorisation (iOS, Android 13+). `true` si accordée.
  /// Un refus ne bloque rien : l'app marche sans rappel.
  Future<bool> requestPermission();

  /// Remplace tous les rappels programmés par [slots] (liste vide = aucun).
  Future<void> replaceReminders(List<ReminderSlot> slots);

  /// Ouvre les réglages de notification de l'app (après un refus).
  Future<void> openSettings();
}

/// Implémentation réelle : flutter_local_notifications.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _init;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rappel_quotidien',
      'Rappel quotidien',
      channelDescription: 'Un seul rappel par jour, à l\'heure choisie.',
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _ensureInit() => _init ??= _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          // L'autorisation est demandée plus tard, au bon moment (écran objectif).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );

  @override
  Future<bool> requestPermission() async {
    try {
      await _ensureInit();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
    } catch (e) {
      debugPrint('Autorisation des notifications impossible : $e');
    }
    return false;
  }

  @override
  Future<void> replaceReminders(List<ReminderSlot> slots) async {
    try {
      await _ensureInit();
      await _plugin.cancelAll();
      for (final slot in slots) {
        await _plugin.zonedSchedule(
          id: slot.id,
          title: slot.title,
          body: slot.body,
          // Rappels ponctuels : seul l'instant compte, le fuseau n'a pas
          // d'importance (l'heure murale est calculée en DateTime local).
          scheduledDate: tz.TZDateTime.from(slot.when, tz.UTC),
          notificationDetails: _details,
          // Inexact : pas de permission « alarme exacte » à demander.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      // Ne jamais faire planter l'app pour un rappel.
      debugPrint('Programmation du rappel impossible : $e');
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _ensureInit();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.openAppNotificationSettings();
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.openAppNotificationSettings();
    } catch (e) {
      debugPrint('Réglages des notifications indisponibles : $e');
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);
