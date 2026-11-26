import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../quiz/quiz_controller.dart';
import '../share/share_content.dart';
import '../share/share_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_slot.dart';
import '../widgets/brand.dart';
import '../widgets/confetti.dart';
import '../widgets/engagement_widgets.dart';
import '../widgets/quiz_widgets.dart';
import 'streak_screen.dart';

/// Résultats (maquette resultats.html) : score, XP, niveau, objectif, confettis à 10/10.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  @override
  void initState() {
    super.initState();
    final outcome = ref.read(quizControllerProvider).outcome;
    if (outcome == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (outcome.leveledUp || outcome.xp.perfect) {
        HapticFeedback.heavyImpact();
        // La « fanfare » est jouée par QuizController à la fin du quiz.
      } else if (outcome.goalReachedNow) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  /// Après le premier quiz du jour : écran « Série validée », sinon accueil.
  void _leave() {
    final outcome = ref.read(quizControllerProvider).outcome;
    if (outcome != null && outcome.streakValidatedNow) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const StreakScreen(mode: StreakScreenMode.celebrate),
      ));
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _title(QuizState s) => switch (s.mode) {
        QuizMode.dailyChallenge => 'Défi du jour',
        QuizMode.mix => 'Mélange',
        QuizMode.category => categoryLabel(s.category ?? mixCategory),
      };

  String _message(int score, int total) {
    if (total > 0 && score == total) return '$score/$total, sans faute !';
    final ratio = total == 0 ? 0 : score / total;
    if (ratio >= 0.7) return 'Joli score !';
    if (ratio >= 0.4) return 'Pas mal du tout !';
    return 'Tu feras mieux au prochain !';
  }

  void _showAnswers(QuizState s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView.separated(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.screen),
          itemCount: s.questions.length,
          separatorBuilder: (context, index) => const Divider(height: 24),
          itemBuilder: (context, i) {
            final q = s.questions[i];
            final ok = s.answers[i].correct;
            final qc = context.quizColors;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ok ? Icons.check_circle : Icons.cancel,
                    color: ok ? qc.success : context.colors.error),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.question, style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text('Réponse : ${q.answers[q.correctIndex]}',
                          style: context.text.bodyLarge),
                      Text(q.explanation, style: context.text.bodyMedium),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(quizControllerProvider);
    final outcome = s.outcome;
    if (outcome == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final total = s.questions.length;
    final score = s.score;
    final perfect = outcome.xp.perfect;
    // Jour figé au début du quiz (jour serveur pour le défi), pas
    // aujourd'hui : un quiz fini après minuit garde son jour.
    final day = s.day ?? dayOf(ref.watch(clockProvider)());
    final animate = !context.reduceMotion;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child:
                                Text(_title(s), style: context.text.titleLarge),
                          ),
                          IconButton(
                            tooltip: 'Fermer',
                            icon: const Icon(Icons.close),
                            onPressed: _leave,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screen),
                      children: [
                        Semantics(
                          liveRegion: true,
                          label:
                              '$score sur $total, plus ${s.serverXp ?? outcome.xp.total} XP'
                              '${outcome.goalReached ? ', objectif du jour atteint' : ''}',
                          child: ExcludeSemantics(
                            child: _ScoreRing(
                                score: score, total: total, animate: animate),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(_message(score, total),
                            textAlign: TextAlign.center,
                            style: context.text.headlineMedium
                                ?.copyWith(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(
                          '${_capitalize(formatShortDate(day))} · '
                          '${perfect ? 'Qui fait aussi bien ?' : 'Qui dit mieux ?'}',
                          textAlign: TextAlign.center,
                          style: context.text.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        _AnswerDots(state: s),
                        const SizedBox(height: AppSpacing.l),
                        ShareLauncher(
                          content: () => scoreShareContent(
                            mode: s.mode,
                            category: s.category,
                            score: score,
                            total: total,
                            answers: [for (final a in s.answers) a.correct],
                            streakDays: outcome.streakCount,
                            day: day,
                          ),
                          builder: (context, onPressed) => FilledButton.icon(
                            onPressed: onPressed,
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Partager mon score'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.l),
                        _XpCard(
                            outcome: outcome,
                            animate: animate,
                            serverXp: s.serverXp),
                        const SizedBox(height: AppSpacing.m),
                        _GoalCard(outcome: outcome),
                        const SizedBox(height: AppSpacing.m),
                        OutlinedButton(
                          onPressed: () => _showAnswers(s),
                          child: const Text('Voir les réponses'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _leave,
                          child: Text(outcome.streakValidatedNow
                              ? 'Continuer'
                              : 'Retour à l\'accueil'),
                        ),
                        const SizedBox(height: AppSpacing.s),
                      ],
                    ),
                  ),
                  const AdSlot(),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom),
                ],
              ),
            ),
            if (perfect)
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 420,
                child: ConfettiBurst(),
              ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.score,
    required this.total,
    required this.animate,
  });

  final int score;
  final int total;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween:
            Tween(begin: animate ? 0 : score.toDouble(), end: score.toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => SizedBox.square(
          dimension: 150,
          child: CustomPaint(
            painter: RingPainter(
              value: total == 0 ? 0 : v / total,
              color: c.primary,
              track: c.outlineVariant,
              stroke: 12,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${v.round()}', style: context.text.displayLarge),
                  const SizedBox(height: 2),
                  Text('sur $total',
                      style: context.text.titleSmall
                          ?.copyWith(color: c.onSurfaceVariant, height: 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerDots extends StatelessWidget {
  const _AnswerDots({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context) {
    final q = context.quizColors;
    final c = context.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < state.answers.length; i++)
          Semantics(
            label:
                'Question ${i + 1} : ${state.answers[i].correct ? 'juste' : 'fausse'}',
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: state.answers[i].correct
                    ? q.successContainer
                    : c.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                state.answers[i].correct ? Icons.check : Icons.close,
                size: 16,
                color: state.answers[i].correct
                    ? q.onSuccessContainer
                    : c.onErrorContainer,
              ),
            ),
          ),
      ],
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({
    required this.outcome,
    required this.animate,
    this.serverXp,
  });

  final QuizOutcome outcome;
  final bool animate;

  /// XP accordés par le serveur (quiz servi), une fois connus.
  final int? serverXp;

  @override
  Widget build(BuildContext context) {
    final xp = outcome.xp;
    final e = context.engagement;
    final before = outcome.levelBefore;
    final after = outcome.levelAfter;
    // Sans montée de niveau : part acquise fixe + gain en safran qui se remplit.
    // Avec montée : la barre du nouveau niveau se remplit depuis 0.
    final base = outcome.leveledUp ? 0.0 : before.fraction;
    final gainEnd = after.fraction - base;

    final lines = <(String, int)>[
      ('Bonnes réponses (${xp.correctCount} × 10)', xp.correctXp),
      if (xp.speedCount > 0)
        (
          'Rapidité (${xp.speedCount} ${xp.speedCount > 1 ? 'réponses' : 'réponse'} en moins de 10 s)',
          xp.speedXp
        ),
      if (xp.comboCount > 0)
        (
          xp.maxCombo > 3 ? 'Combo jusqu\'à x${xp.maxCombo}' : 'Combo x3',
          xp.comboXp
        ),
      ('Quiz terminé', xp.completedXp),
      if (xp.perfect) ('Sans faute', xp.perfectXp),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('XP gagnés', style: context.text.titleMedium)),
                Text('+${serverXp ?? xp.total} XP',
                    style: TextStyle(
                      fontFamily: AppFonts.titre,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      height: 1,
                      color: e.xp,
                    )),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            for (final (label, value) in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(label,
                          style:
                              context.text.bodyMedium?.copyWith(fontSize: 15)),
                    ),
                    Text('+$value',
                        style: context.text.titleSmall?.copyWith(fontSize: 15)),
                  ],
                ),
              ),
            if (serverXp != null && serverXp != xp.total)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Validé par le serveur : +$serverXp XP (rapidité jugée '
                  'sur le temps de réception, plafond du jour).',
                  style: context.text.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                LevelBadge(level: after.level),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Niveau ${after.level}',
                                style: context.text.titleSmall),
                          ),
                          Text('${after.xpInLevel} / ${after.xpForNext} XP',
                              style: context.text.labelSmall?.copyWith(
                                  fontSize: 14,
                                  color: context.colors.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween:
                            Tween(begin: animate ? 0 : gainEnd, end: gainEnd),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (context, g, _) =>
                            LevelBar(value: base, gain: g),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (outcome.leveledUp)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.s),
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: context.colors.tertiary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up,
                          size: 18, color: context.colors.onTertiary),
                      const SizedBox(width: 6),
                      Text('Niveau ${after.level} atteint !',
                          style: TextStyle(
                            fontFamily: AppFonts.titre,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: context.colors.onTertiary,
                          )),
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.outcome});

  final QuizOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final q = context.quizColors;
    final c = context.colors;
    final reached = outcome.goalReached;
    final done = outcome.quizzesToday.clamp(0, outcome.dailyGoal);
    final streak = outcome.streakCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: reached ? q.success : c.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(reached ? Icons.check : Icons.track_changes,
                  color: reached ? q.onSuccess : q.primaryText),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      reached ? 'Objectif du jour atteint' : 'Objectif du jour',
                      style: context.text.titleMedium),
                  Text(
                    '$done/${outcome.dailyGoal} quiz · série de $streak '
                    '${streak > 1 ? 'jours' : 'jour'}',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  GoalGauge(
                      done: outcome.quizzesToday, goal: outcome.dailyGoal),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
