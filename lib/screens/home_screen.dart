import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../engagement/streak_rules.dart';
import '../engagement/xp.dart';
import '../models/player_progress.dart';
import '../models/question.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_slot.dart';
import '../widgets/brand.dart';
import '../widgets/engagement_widgets.dart';
import 'quiz_launcher.dart';
import 'streak_screen.dart';

/// Accueil (maquette accueil.html).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressControllerProvider);
    final today = dayOf(ref.watch(clockProvider)());
    final streak = progress.streak;

    void openStreak() {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StreakScreen(
          mode: playedToday(streak, today)
              ? StreakScreenMode.view
              : StreakScreenMode.danger,
        ),
      ));
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              child: Row(
                children: [
                  const QuizzeoLogo(),
                  const Spacer(),
                  StreakChip(count: streak.count, onTap: openStreak),
                  const SizedBox(width: AppSpacing.s),
                  FreezeChip(
                    count: streak.freezes,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      showFreezeInfo(context, streak.freezes);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
              children: [
                _ProgressCard(progress: progress, today: today),
                const SizedBox(height: AppSpacing.m),
                _ChallengeCard(progress: progress, today: today),
                const SizedBox(height: AppSpacing.m),
                _StreakCard(
                    progress: progress, today: today, onTap: openStreak),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text('Catégories', style: context.text.titleLarge),
                    ),
                    Text('10 questions', style: context.text.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                const _CategoryGrid(),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
          // Écart avec la barre de navigation (clics accidentels).
          const AdSlot(padding: EdgeInsets.only(bottom: AppSpacing.m)),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress, required this.today});

  final PlayerProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = progress.quizzesOn(today);
    final goal = progress.dailyGoal;
    final remaining = goal - done;
    final level = levelFor(progress.totalXp);
    final goalLegend = remaining <= 0
        ? 'Objectif atteint. Bien joué !'
        : progress.challengePlayedOn(today)
            ? 'Encore $remaining quiz.'
            : 'Encore $remaining quiz. Le défi du jour compte.';
    final reached = remaining <= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ValueRow(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      reached ? context.quizColors.success : c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  reached ? Icons.check : Icons.track_changes,
                  color: reached
                      ? context.quizColors.onSuccess
                      : context.quizColors.primaryText,
                ),
              ),
              title: 'Objectif du jour',
              value: '${done.clamp(0, goal)}/$goal',
              unit: 'quiz',
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Objectif du jour : $done quiz sur $goal',
              child: GoalGauge(done: done, goal: goal),
            ),
            const SizedBox(height: 6),
            Text(goalLegend, style: context.text.bodyMedium),
            Divider(height: 28, color: c.outlineVariant),
            _ValueRow(
              leading: LevelBadge(level: level.level),
              title: 'Niveau ${level.level}',
              value: '${level.xpInLevel}',
              unit: '/ ${level.xpForNext} XP',
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Progression vers le niveau ${level.level + 1}',
              value: '${level.xpInLevel} sur ${level.xpForNext} XP',
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: level.fraction),
                duration: context.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, v, child) => LevelBar(value: v),
              ),
            ),
            const SizedBox(height: 6),
            Text('${level.xpRemaining} XP avant le niveau ${level.level + 1}.',
                style: context.text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.leading,
    required this.title,
    required this.value,
    required this.unit,
  });

  final Widget leading;
  final String title;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading,
        const SizedBox(width: AppSpacing.m),
        Expanded(child: Text(title, style: context.text.titleMedium)),
        Text.rich(
          TextSpan(
            text: value,
            style: const TextStyle(
              fontFamily: AppFonts.titre,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1,
            ),
            children: [
              TextSpan(
                text: ' $unit',
                style: context.text.labelSmall?.copyWith(
                  fontSize: 14,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard({required this.progress, required this.today});

  final PlayerProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final played = progress.challengePlayedOn(today);
    final now = ref.watch(clockProvider)();
    final hoursLeft =
        (addDays(today, 1).difference(now).inMinutes / 60).ceil().clamp(1, 24);
    final onColor = c.onPrimary;
    final body = context.text.bodyLarge?.copyWith(color: onColor, fontSize: 15);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: -34,
            child: ExcludeSemantics(
              child: Text(
                'é',
                style: TextStyle(
                  fontFamily: AppFonts.titre,
                  fontWeight: FontWeight.w800,
                  fontSize: 170,
                  height: 1,
                  color: onColor.withValues(alpha: 0.13),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'DÉFI DU JOUR · ${formatShortDate(today).toUpperCase()}',
                  style: context.text.labelSmall?.copyWith(
                    color: onColor,
                    letterSpacing: 1.04,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  !played
                      ? '10 questions, les mêmes pour tous'
                      : progress.challengeTotal > 0
                          ? 'Ton score : ${progress.challengeScore}/${progress.challengeTotal}'
                          : 'Défi du jour joué',
                  style: context.text.headlineSmall?.copyWith(
                    color: onColor,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: onColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        played
                            ? 'Nouveau défi dans $hoursLeft h'
                            : '30 s par question · nouveau défi dans $hoursLeft h',
                        style: body,
                      ),
                    ),
                  ],
                ),
                if (!played) ...[
                  const SizedBox(height: AppSpacing.l),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: c.brightness == Brightness.light
                          ? Colors.white
                          : c.surface,
                      foregroundColor: c.onSurface,
                    ),
                    onPressed: () => launchQuiz(context, ref),
                    child: const Text('Jouer le défi'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatefulWidget {
  const _StreakCard({
    required this.progress,
    required this.today,
    required this.onTap,
  });

  final PlayerProgress progress;
  final DateTime today;
  final VoidCallback onTap;

  @override
  State<_StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<_StreakCard>
    with SingleTickerProviderStateMixin {
  // Respiration de la flamme : 1 -> 1.05 en 2,4 s, aller-retour.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.progress.streak;
    final today = widget.today;
    final count = streak.count;
    final done = playedToday(streak, today);
    final legend = done
        ? 'Validée aujourd\'hui. À demain !'
        : count > 0
            ? 'Joue aujourd\'hui pour garder ta série.'
            : 'Joue un quiz pour lancer ta série.';
    final freezes = streak.freezes;
    final e = context.engagement;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ScaleTransition(
                    alignment: const Alignment(0, 0.8),
                    scale: Tween(begin: 1.0, end: 1.05).animate(
                      CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
                    ),
                    child: FlameIcon(size: 52, outline: !done && count > 0),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 0
                              ? 'Pas encore de série'
                              : '$count ${count > 1 ? 'jours' : 'jour'} de série',
                          style: context.text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800, fontSize: 22),
                        ),
                        Text(legend, style: context.text.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              WeekRow(
                streak: streak,
                today: today,
                firstDay: addDays(today, -6),
              ),
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: e.gelContainer,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: e.gelBorder == null
                      ? null
                      : Border.all(color: e.gelBorder!, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.ac_unit, color: e.gel),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: context.text.bodyMedium
                              ?.copyWith(color: e.onGelContainer),
                          children: freezes > 0
                              ? [
                                  TextSpan(
                                    text:
                                        '$freezes ${freezes > 1 ? 'gels' : 'gel'} en réserve. ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const TextSpan(
                                      text:
                                          'Il protège ta série si tu rates un jour.'),
                                ]
                              : const [
                                  TextSpan(
                                    text: 'Aucun gel en réserve. ',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  TextSpan(
                                      text:
                                          'Un gel protège ta série un jour sans jeu.'),
                                ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = [...categories.keys, mixCategory];
    final q = context.quizColors;
    return Column(
      children: [
        for (var row = 0; row < keys.length; row += 2) ...[
          if (row > 0) const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              for (var i = row; i < row + 2 && i < keys.length; i++) ...[
                if (i > row) const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: _CategoryCard(
                    tint: q.categoryTint[keys[i]]!,
                    iconColor: q.categoryIcon[keys[i]]!,
                    category: keys[i],
                    onTap: () => launchQuiz(context, ref, category: keys[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.tint,
    required this.iconColor,
    required this.category,
    required this.onTap,
  });

  final Color tint;
  final Color iconColor;
  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
    );
    return Material(
      color: tint,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(categoryIcon(category), color: iconColor),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(categoryLabel(category),
                      style: context.text.titleMedium?.copyWith(height: 1.2)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
