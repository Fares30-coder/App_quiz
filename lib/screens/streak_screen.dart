import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../models/player_progress.dart';
import '../share/share_content.dart';
import '../share/share_launcher.dart';
import '../sound/sound_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/engagement_widgets.dart';
import 'quiz_launcher.dart';

enum StreakScreenMode {
  /// Après le premier quiz du jour : animation de validation.
  celebrate,

  /// Série validée, consultée depuis l'accueil (sans animation).
  view,

  /// Pas encore joué aujourd'hui.
  danger,
}

/// Série (maquette serie.html, états « validée » et « danger »).
class StreakScreen extends ConsumerStatefulWidget {
  const StreakScreen({super.key, required this.mode});

  final StreakScreenMode mode;

  @override
  ConsumerState<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends ConsumerState<StreakScreen> {
  /// Nombre affiché : part de N − 1 puis passe à N (célébration).
  late int _shown;

  @override
  void initState() {
    super.initState();
    final count = ref.read(progressControllerProvider).streak.count;
    final celebrate = widget.mode == StreakScreenMode.celebrate;
    _shown = celebrate ? (count - 1).clamp(0, count) : count;
    if (celebrate) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final reduce = context.reduceMotion;
        if (!reduce) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
        if (!mounted) return;
        setState(() => _shown = count);
        HapticFeedback.mediumImpact();
        ref.read(soundEffectsProvider).play(Sfx.streak);
      });
    }
  }

  void _close() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressControllerProvider);
    final today = dayOf(ref.watch(clockProvider)());
    final danger = widget.mode == StreakScreenMode.danger;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          const SizedBox(width: AppSpacing.s),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: danger
                    ? _dangerContent(context, progress, today)
                    : _validatedContent(context, progress, today),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen,
                  AppSpacing.l, AppSpacing.screen, AppSpacing.s),
              child: Column(
                children: danger
                    ? [
                        FilledButton(
                          onPressed: () => launchQuiz(
                            context,
                            ref,
                            category: progress.challengePlayedOn(today)
                                ? mixCategory
                                : null,
                            replace: true,
                          ),
                          child: const Text('Jouer un quiz'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: context.colors.onSurface),
                          onPressed: _close,
                          child: const Text('Non merci'),
                        ),
                      ]
                    : [
                        FilledButton(
                          onPressed: _close,
                          child: const Text('Continuer'),
                        ),
                        const SizedBox(height: 10),
                        ShareLauncher(
                          content: () => streakShareContent(
                            streakDays: progress.streak.count,
                            day: today,
                          ),
                          builder: (context, onPressed) => TextButton.icon(
                            onPressed: onPressed,
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Partager ma série'),
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _validatedContent(
    BuildContext context,
    PlayerProgress progress,
    DateTime today,
  ) {
    final count = progress.streak.count;
    final animate =
        widget.mode == StreakScreenMode.celebrate && !context.reduceMotion;
    final number = TextStyle(
      fontFamily: AppFonts.titre,
      fontWeight: FontWeight.w800,
      fontSize: 72,
      height: 1,
      letterSpacing: -2,
      color: context.colors.onSurface,
    );
    return [
      Semantics(
        liveRegion: true,
        label: 'Série validée. $count jours de série.',
        child: ExcludeSemantics(
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: animate ? 0.6 : 1, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  alignment: const Alignment(0, 0.8),
                  child: child,
                ),
                child: const FlameIcon(size: 104),
              ),
              const SizedBox(height: 4),
              ClipRect(
                child: AnimatedSwitcher(
                  duration: animate
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.6),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Text('$_shown', key: ValueKey(_shown), style: number),
                ),
              ),
              Text(
                count > 1 ? 'jours de série' : 'jour de série',
                style: context.text.titleLarge
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.m),
            Text('Série validée !',
                textAlign: TextAlign.center,
                style: context.text.headlineMedium),
            const SizedBox(height: 6),
            Text(
              count > 1
                  ? '$count jours d\'affilée. Reviens demain pour passer à ${count + 1}.'
                  : 'C\'est parti ! Reviens demain pour passer à 2.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(fontSize: 16),
            ),
          ],
        ),
      ),
      _WeekCard(progress: progress, today: today, showDetails: true),
    ];
  }

  List<Widget> _dangerContent(
    BuildContext context,
    PlayerProgress progress,
    DateTime today,
  ) {
    final count = progress.streak.count;
    final freezes = progress.streak.freezes;
    final e = context.engagement;
    return [
      const Center(child: FlameIcon(size: 80, outline: true)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.m),
            Text(
              count > 0
                  ? 'Ta série de $count ${count > 1 ? 'jours' : 'jour'} t\'attend'
                  : 'Lance ta série aujourd\'hui',
              textAlign: TextAlign.center,
              style: context.text.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              count > 0
                  ? 'Joue un quiz aujourd\'hui pour la garder. 5 minutes suffisent.'
                  : 'Un quiz par jour suffit pour faire grandir ta série.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(fontSize: 16),
            ),
          ],
        ),
      ),
      _WeekCard(progress: progress, today: today, showDetails: false),
      Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(AppSpacing.l),
        decoration: BoxDecoration(
          color: e.gelContainer,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: e.gelBorder == null
              ? null
              : Border.all(color: e.gelBorder!, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.ac_unit, color: e.gel),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        freezes > 0
                            ? 'Ta série est protégée'
                            : 'Pas le temps aujourd\'hui ?',
                        style: context.text.titleMedium
                            ?.copyWith(color: e.onGelContainer),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        freezes > 0
                            ? 'Tu as $freezes ${freezes > 1 ? 'gels' : 'gel'} en réserve. Si tu ne joues pas, un gel s\'appliquera tout seul.'
                            : 'Un gel protège ta série pendant une journée sans jeu. Tu n\'en as pas en réserve.',
                        style: context.text.bodyLarge
                            ?.copyWith(fontSize: 15, color: e.onGelContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (freezes == 0) ...[
              const SizedBox(height: AppSpacing.m),
              // TODO(etape-3): RewardedAd AdMob (préchargée) ; créditer le gel
              // uniquement dans onUserEarnedReward via addStreakFreeze().
              // Joueurs « sans pub » : 1 gel offert par semaine.
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: context.colors.surfaceContainerLowest,
                  side: BorderSide(color: e.gel, width: 2),
                ),
                onPressed: null,
                icon: const Icon(Icons.smart_display_outlined),
                label: const Text('Pas de pub disponible pour le moment'),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Facultatif. Le gel est ajouté à la fin de la vidéo.',
                textAlign: TextAlign.center,
                style:
                    context.text.bodySmall?.copyWith(color: e.onGelContainer),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.progress,
    required this.today,
    required this.showDetails,
  });

  final PlayerProgress progress;
  final DateTime today;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final freezes = progress.streak.freezes;
    final e = context.engagement;
    final done = progress.quizzesOn(today);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showDetails) ...[
                Text('Cette semaine', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.m),
              ],
              WeekRow(
                streak: progress.streak,
                today: today,
                firstDay: mondayOf(today),
              ),
              if (showDetails) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.ac_unit, color: e.gel),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: context.text.bodyMedium
                              ?.copyWith(color: context.colors.onSurface),
                          children: [
                            TextSpan(
                              text: freezes == 0
                                  ? 'Aucun gel en réserve'
                                  : '$freezes ${freezes > 1 ? 'gels' : 'gel'} en réserve',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const TextSpan(text: ' pour un jour sans jeu.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: GoalGauge(done: done, goal: progress.dailyGoal),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Objectif du jour : ${done.clamp(0, progress.dailyGoal)}/${progress.dailyGoal} quiz',
                        style: context.text.bodyMedium
                            ?.copyWith(color: context.colors.onSurface),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
