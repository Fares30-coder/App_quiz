import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../ads/consent_service.dart';
import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../engagement/xp.dart';
import '../models/player_progress.dart';
import '../reminder/reminder_scheduler.dart';
import '../reminder/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/engagement_widgets.dart';
import 'goal_screen.dart';
import 'no_ads_screen.dart';

/// Profil (pas de maquette dédiée) : niveau, réglages de l'objectif, sans pub.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressControllerProvider);
    final level = levelFor(p.totalXp);
    final reminder = p.reminderMinutes;
    // Exigence Google : entrée affichée seulement si UMP la demande (EEE…).
    final privacyOptions = ref.watch(privacyOptionsRequiredProvider);

    void open(Widget screen, {bool fullscreen = false}) =>
        Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: fullscreen,
          builder: (_) => screen,
        ));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          const SizedBox(height: AppSpacing.s),
          Text('Profil', style: context.text.headlineMedium),
          const SizedBox(height: AppSpacing.l),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      LevelBadge(level: level.level),
                      const SizedBox(width: AppSpacing.m),
                      Expanded(
                        child: Text('Niveau ${level.level}',
                            style: context.text.titleMedium),
                      ),
                      Text('${p.totalXp} XP au total',
                          style: context.text.bodyMedium),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LevelBar(value: level.fraction),
                  const SizedBox(height: 6),
                  Text('${level.xpInLevel} / ${level.xpForNext} XP',
                      style: context.text.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(Icons.track_changes),
                  title: const Text('Objectif du jour'),
                  subtitle: Text('${p.dailyGoal} quiz par jour'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(const GoalScreen()),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_none),
                  title: const Text('Rappel quotidien'),
                  subtitle: const Text(
                      'Un seul par jour, seulement si tu n\'as pas encore joué'),
                  value: reminder != null,
                  onChanged: (on) => _setReminder(
                      context, ref, on ? defaultReminderMinutes : null),
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 56,
                  enabled: reminder != null,
                  leading: const Icon(Icons.schedule),
                  title: const Text('Heure du rappel'),
                  subtitle: Text(
                      reminder == null ? 'Désactivé' : formatHour(reminder)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked =
                        await pickReminderMinutes(context, reminder!);
                    if (picked != null && context.mounted) {
                      _setReminder(context, ref, picked);
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(Icons.block),
                  title: const Text('Supprimer les pubs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(const NoAdsScreen(), fullscreen: true),
                ),
                const Divider(height: 1),
                if (privacyOptions) ...[
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Gérer mes choix de confidentialité'),
                    subtitle: const Text('Pubs personnalisées ou non'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: ref
                        .read(consentControllerProvider.notifier)
                        .showPrivacyOptions,
                  ),
                  const Divider(height: 1),
                ],
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('Sons'),
                  subtitle:
                      const Text('Muets quand le téléphone est en silencieux'),
                  value: p.soundEnabled,
                  onChanged: ref
                      .read(progressControllerProvider.notifier)
                      .setSoundEnabled,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Enregistre le rappel (replanifié automatiquement) et, s'il est actif,
  /// demande l'autorisation. Refus : message discret, l'app marche sans.
  Future<void> _setReminder(
      BuildContext context, WidgetRef ref, int? minutes) async {
    ref.read(progressControllerProvider.notifier).setReminder(minutes);
    if (minutes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(notificationServiceProvider);
    final granted =
        await ref.read(reminderSchedulerProvider).requestPermission();
    if (granted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text(
            'Les notifications sont désactivées pour Quizzéo. Autorise-les dans les réglages pour recevoir le rappel.'),
        action:
            SnackBarAction(label: 'Réglages', onPressed: service.openSettings),
      ));
  }
}
