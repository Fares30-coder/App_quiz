import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../models/player_progress.dart';
import '../theme/app_theme.dart';

/// Objectif du jour + heure du rappel (maquette objectif.html).
/// [onboarding] : premier lancement ; sinon modification depuis le Profil.
class GoalScreen extends ConsumerStatefulWidget {
  const GoalScreen({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  ConsumerState<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends ConsumerState<GoalScreen> {
  static const _presets = [8 * 60, 12 * 60 + 30, 18 * 60, 20 * 60 + 30];
  static const _goals = [
    (1, 'Tranquille · environ 5 min'),
    (2, 'Régulier · environ 10 min'),
    (3, 'À fond · environ 15 min'),
  ];

  // État local du formulaire, enregistré seulement à la validation.
  late int _goal;
  late int? _reminder;

  @override
  void initState() {
    super.initState();
    final p = ref.read(progressControllerProvider);
    _goal = widget.onboarding ? defaultDailyGoal : p.dailyGoal;
    _reminder = widget.onboarding ? defaultReminderMinutes : p.reminderMinutes;
  }

  Future<void> _pickOtherHour() async {
    final initial = _reminder ?? defaultReminderMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _reminder = picked.hour * 60 + picked.minute);
    }
  }

  void _save() {
    final controller = ref.read(progressControllerProvider.notifier);
    if (widget.onboarding) {
      controller.finishOnboarding(dailyGoal: _goal, reminder: _reminder);
      // L'accueil remplace la racine (voir main.dart) : on ferme l'onboarding.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      controller.setGoalAndReminder(dailyGoal: _goal, reminder: _reminder);
      Navigator.of(context).pop();
    }
    // TODO(etape-1b): demander l'autorisation des notifications (iOS / Android 13+)
    // et programmer le rappel ; un refus ne bloque rien.
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isOther = _reminder != null && !_presets.contains(_reminder);
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          if (widget.onboarding)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.screen),
              child: Text('Dernière étape',
                  style: context.text.titleSmall
                      ?.copyWith(fontSize: 14, color: c.onSurfaceVariant)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              children: [
                Text('Ton objectif du jour',
                    style: context.text.headlineMedium),
                const SizedBox(height: 6),
                Text(
                    'Combien de quiz par jour ? Tu pourras le changer quand tu veux.',
                    style: context.text.bodyMedium?.copyWith(fontSize: 16)),
                const SizedBox(height: AppSpacing.xl),
                for (final (goal, subtitle) in _goals) ...[
                  _GoalOption(
                    goal: goal,
                    subtitle: subtitle,
                    selected: _goal == goal,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _goal = goal);
                    },
                  ),
                  const SizedBox(height: AppSpacing.m),
                ],
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Icon(Icons.notifications_none, color: c.secondary),
                    const SizedBox(width: AppSpacing.s),
                    Text('Ton rappel', style: context.text.titleLarge),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                    'Un seul rappel par jour, et seulement si tu n\'as pas encore joué.',
                    style: context.text.bodyMedium),
                const SizedBox(height: AppSpacing.m),
                Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [
                    for (final m in _presets)
                      _HourChip(
                        label: formatHour(m),
                        selected: _reminder == m,
                        onTap: () => setState(() => _reminder = m),
                      ),
                    _HourChip(
                      label: isOther ? formatHour(_reminder!) : 'Autre heure',
                      icon: Icons.schedule,
                      selected: isOther,
                      onTap: _pickOtherHour,
                    ),
                    _HourChip(
                      label: 'Pas de rappel',
                      selected: _reminder == null,
                      onTap: () => setState(() => _reminder = null),
                    ),
                  ],
                ),
                if (_reminder != null) _ReminderPreview(minutes: _reminder!),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.outlineVariant)),
            ),
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.m,
                AppSpacing.screen, AppSpacing.m),
            child: SafeArea(
              top: false,
              child: FilledButton(
                onPressed: _save,
                child: Text(widget.onboarding ? 'C\'est parti' : 'Enregistrer'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalOption extends StatelessWidget {
  const _GoalOption({
    required this.goal,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final int goal;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = context.quizColors.primaryText;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      side: BorderSide(color: selected ? accent : c.outline, width: 2),
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? c.primaryContainer : c.surfaceContainerLowest,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 4),
                            Expanded(
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  color:
                                      i < goal ? c.primary : c.outlineVariant,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.pill),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$goal quiz par jour',
                            style: context.text.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          subtitle,
                          style: context.text.bodyMedium?.copyWith(
                            color: selected ? c.onPrimaryContainer : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected ? accent : c.outline, width: 2),
                    ),
                    child: selected
                        ? Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: accent, shape: BoxShape.circle),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onSecondary : c.onSurface;
    final shape = StadiumBorder(
      side: BorderSide(color: selected ? c.secondary : c.outline, width: 2),
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: Material(
        color: selected ? c.secondary : c.surfaceContainerLowest,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected || icon != null) ...[
                  Icon(selected ? Icons.check : icon, size: 18, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: context.text.titleSmall
                        ?.copyWith(color: fg, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderPreview extends StatelessWidget {
  const _ReminderPreview({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final time =
        '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
    return Semantics(
      label: 'Aperçu du rappel',
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.l),
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Icône d'app : toujours corail clair, même en mode sombre.
                color: AppTheme.lightScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text('é',
                  style: TextStyle(
                      fontFamily: AppFonts.titre,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1,
                      color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: context.text.bodyMedium?.copyWith(color: c.onSurface),
                  children: [
                    const TextSpan(
                        text: 'Quizzéo',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                      text: ' · $time\n',
                      style: context.text.bodySmall,
                    ),
                    const TextSpan(
                        text:
                            'Le défi du jour est prêt. 10 questions, ça te dit ?'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
