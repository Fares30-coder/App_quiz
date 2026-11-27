import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../quiz/quiz_controller.dart';
import '../quiz/report_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/engagement_widgets.dart';
import '../widgets/quiz_widgets.dart';
import 'result_screen.dart';

/// Question + feedback (maquettes question, feedback-bonne, feedback-mauvaise).
/// AUCUNE PUB sur cet écran.
class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key});

  static const _letters = ['A', 'B', 'C', 'D'];

  Future<void> _confirmQuit(BuildContext context, WidgetRef ref) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitter le quiz ?'),
        content: const Text('Cette partie ne sera pas comptée.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (quit == true && context.mounted) {
      ref.read(quizControllerProvider.notifier).quit();
      Navigator.of(context).pop();
    }
  }

  Future<void> _answer(BuildContext context, WidgetRef ref, int i) async {
    HapticFeedback.lightImpact();
    final before = ref.read(quizControllerProvider).combo;
    // Quiz servi : correction du serveur (quelques centaines de ms).
    final correct = await ref.read(quizControllerProvider.notifier).answer(i);
    if (!context.mounted) return;
    if (correct) {
      HapticFeedback.mediumImpact();
      // Le son (« ding » / son neutre) est joué par QuizController.answer.
      if (before + 1 >= 2) HapticFeedback.selectionClick();
    }
  }

  void _next(BuildContext context, WidgetRef ref) {
    if (!ref.read(quizControllerProvider.notifier).next()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const ResultScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(quizControllerProvider);
    if (state.questions.isEmpty || state.isFinished) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = state.current;
    final c = context.colors;

    final statuses = [
      for (var i = 0; i < state.total; i++)
        i < state.answers.length
            ? (state.answers[i].correct ? SegmentStatus.ok : SegmentStatus.ko)
            : i == state.index
                ? SegmentStatus.current
                : SegmentStatus.todo,
    ];

    AnswerStatus statusOf(int i) {
      // En attente de la correction du serveur : seul le choix reste en avant.
      if (state.waiting) {
        return i == state.selected ? AnswerStatus.neutral : AnswerStatus.dimmed;
      }
      if (!state.answered) return AnswerStatus.neutral;
      if (i == q.correctIndex) return AnswerStatus.correct;
      if (i == state.selected) return AnswerStatus.wrong;
      return AnswerStatus.dimmed;
    }

    final answers = Column(
      children: [
        for (var i = 0; i < q.answers.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.m),
          AnswerButton(
            letter: _letters[i],
            label: q.answers[i],
            status: statusOf(i),
            onPressed: state.locked ? null : () => _answer(context, ref, i),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit(context, ref);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: !state.answered &&
              !state.answerFailed &&
              !state.nextFailed &&
              !state.outOfSync,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Quitter le quiz',
                      iconSize: 24,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.close),
                      onPressed: () => _confirmQuit(context, ref),
                    ),
                    Expanded(
                      child: Text.rich(
                        textAlign: TextAlign.center,
                        TextSpan(
                          style: context.text.titleSmall?.copyWith(height: 1),
                          children: [
                            const TextSpan(text: 'Question '),
                            TextSpan(
                              text: '${state.index + 1}',
                              style: const TextStyle(
                                fontFamily: AppFonts.titre,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            TextSpan(text: '/${state.total}'),
                          ],
                        ),
                      ),
                    ),
                    TimerRing(
                      secondsLeft: state.secondsLeft,
                      frozen: state.locked,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: QuizSegments(statuses: statuses),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                      sliver: SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: CategoryChip(category: q.category),
                                ),
                                const SizedBox(width: AppSpacing.s),
                                const Spacer(),
                                Text('Difficulté ${q.difficulty}/3',
                                    style: context.text.bodyMedium),
                              ],
                            ),
                            if (!state.locked) _BonusRow(state: state),
                            const SizedBox(height: 14),
                            Text(
                              q.question,
                              style: context.text.headlineSmall?.copyWith(
                                height: 1.3,
                                fontSize: state.answered ? 22 : 24,
                              ),
                            ),
                            if (state.answered)
                              const SizedBox(height: AppSpacing.l)
                            else
                              const Spacer(),
                            const SizedBox(height: AppSpacing.l),
                            answers,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.outOfSync)
                _RetrySheet(
                  message: 'Ce quiz a avancé ailleurs (autre appareil ?). '
                      'Quitte-le puis relance-le pour reprendre.',
                  onQuit: () => _confirmQuit(context, ref),
                )
              else if (state.nextFailed)
                _RetrySheet(
                  message: 'Connexion perdue : impossible de charger '
                      'la question suivante.',
                  onRetry: () =>
                      ref.read(quizControllerProvider.notifier).retryNext(),
                  onQuit: () => _confirmQuit(context, ref),
                )
              else if (state.answered)
                _FeedbackSheet(
                  state: state,
                  onNext: () => _next(context, ref),
                )
              else if (state.answerFailed)
                _RetrySheet(
                  message: 'Connexion perdue : ta réponse est gardée.',
                  onRetry: () =>
                      ref.read(quizControllerProvider.notifier).retryAnswer(),
                  onQuit: () => _confirmQuit(context, ref),
                )
              else if (state.waiting)
                const LinearProgressIndicator(
                  semanticsLabel: 'Correction en cours',
                ),
            ],
          ),
        ),
        backgroundColor: c.surface,
      ),
    );
  }
}

/// Combo (à partir de x2) + bonus rapidité (10 premières secondes).
class _BonusRow extends StatelessWidget {
  const _BonusRow({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context) {
    final combo = state.combo;
    final speedLeft = state.speedBonusSecondsLeft;
    final fade = context.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: fade,
              child: combo >= 2
                  ? ComboChip(key: ValueKey(combo), combo: combo)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: AppSpacing.s),
            const Spacer(),
            Flexible(
              flex: 4,
              child: AnimatedOpacity(
                opacity: speedLeft > 0 ? 1 : 0,
                duration: fade,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 18, color: context.engagement.rapide),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Bonus rapidité · ${speedLeft > 0 ? speedLeft : 0} s',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feuille du bas : verdict, XP, explication, « Question suivante ».
class _FeedbackSheet extends StatelessWidget {
  const _FeedbackSheet({required this.state, required this.onNext});

  final QuizState state;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiz = context.quizColors;
    final q = state.current;
    final last = state.answers.last;
    final correct = last.correct;
    final xp = state.lastAnswerXp;
    final seconds = last.elapsed.inSeconds;

    final (
      String title,
      String subtitle,
      Color circle,
      Color onCircle,
      IconData icon
    ) = correct
        ? (
            'Bien vu !',
            'Réponse en $seconds s',
            quiz.success,
            quiz.onSuccess,
            Icons.check
          )
        : state.timedOut
            ? (
                'Temps écoulé',
                'C\'était ${q.answers[q.correctIndex]}.',
                c.error,
                c.onError,
                Icons.timer_off_outlined
              )
            : (
                'Raté !',
                'C\'était ${q.answers[q.correctIndex]}.',
                c.error,
                c.onError,
                Icons.close
              );

    final sheet = Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      decoration: BoxDecoration(
        color: c.surfaceContainerLowest,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1B3A).withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: correct
                          ? '$title Plus ${xp.total} XP'
                          : '$title $subtitle',
                      child: ExcludeSemantics(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: circle, shape: BoxShape.circle),
                              child: Icon(icon, color: onCircle, weight: 700),
                            ),
                            const SizedBox(width: AppSpacing.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      style: context.text.headlineSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  Text(subtitle,
                                      style: context.text.labelMedium?.copyWith(
                                          color: c.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (correct) XpBadge(xp: xp.total, large: true),
                          ],
                        ),
                      ),
                    ),
                    if (correct)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _XpDetail(
                                icon: Icons.check,
                                label: '+${xp.base} bonne réponse'),
                            if (xp.speed > 0)
                              _XpDetail(
                                  icon: Icons.timer_outlined,
                                  label: '+${xp.speed} rapidité'),
                            if (xp.combo > 0)
                              _XpDetail(
                                  icon: Icons.bolt,
                                  label: '+${xp.combo} combo x${state.combo}'),
                          ],
                        ),
                      ),
                    Container(
                      // Quiz servi : lien « Signaler » juste en dessous.
                      margin: EdgeInsets.fromLTRB(
                          0, 12, 0, state.isServed ? 0 : 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, color: c.secondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.explanation,
                                    style: context.text.bodyLarge),
                                if (q.source case final source?) ...[
                                  const SizedBox(height: 6),
                                  SourceLabel(source),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.isServed) _ReportLink(state: state),
                  ],
                ),
              ),
            ),
            FilledButton(
              // Quiz servi : question suivante en cours de chargement.
              onPressed: state.loadingNext ? null : onNext,
              child: state.loadingNext
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        semanticsLabel: 'Chargement de la question suivante',
                      ),
                    )
                  : Text(
                      state.isLast ? 'Voir le résultat' : 'Question suivante'),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ),
      ),
    );

    if (context.reduceMotion) return sheet;
    return TweenAnimationBuilder<Offset>(
      key: ValueKey(state.index),
      tween: Tween(begin: const Offset(0, 1), end: Offset.zero),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) =>
          FractionalTranslation(translation: offset, child: child),
      child: sheet,
    );
  }
}

/// Lien discret « Signaler » sous l'explication (quiz servi seulement :
/// jamais en quiz local). Le chrono est déjà arrêté (question corrigée) ;
/// l'envoi part en arrière-plan sans bloquer « Question suivante ».
class _ReportLink extends ConsumerWidget {
  const _ReportLink({required this.state});

  final QuizState state;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final quizId = state.quizId;
    if (quizId == null) return;
    final position = state.index + 1;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(reportControllerProvider.notifier);
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _ReportSheet(),
    );
    if (reason == null) return;
    final result = await controller.report(
        quizId: quizId, position: position, reason: reason);
    final message = switch (result) {
      ReportResult.sent => 'Merci, on vérifie.',
      ReportResult.ignored => null,
      ReportResult.tooMany =>
        'Trop de signalements aujourd\'hui. Réessaie demain.',
      ReportResult.failed => 'Signalement non envoyé. Réessaie plus tard.',
    };
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportControllerProvider);
    final quizId = state.quizId;
    if (quizId == null) return const SizedBox(height: 14);
    final status = reports.statusOf(quizId, state.index + 1);
    final color = context.colors.onSurfaceVariant;
    if (status != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.s),
            Icon(Icons.flag, size: 18, color: color),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                status == ReportStatus.sending
                    ? 'Envoi du signalement…'
                    : 'Question signalée',
                style: context.text.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }
    if (!canReport(state, reports)) return const SizedBox(height: 14);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          foregroundColor: color,
          textStyle: context.text.labelMedium,
        ),
        onPressed: () => _report(context, ref),
        icon: const Icon(Icons.flag_outlined, size: 18),
        label:
            const Text('Signaler', semanticsLabel: 'Signaler cette question'),
      ),
    );
  }
}

/// Feuille des 4 motifs de signalement (pas de texte libre).
class _ReportSheet extends StatelessWidget {
  const _ReportSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.s),
              child: Text('Signaler cette question',
                  style: context.text.titleMedium),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                minTileHeight: 56,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
                title: Text(reason.label, style: context.text.bodyLarge),
                onTap: () => Navigator.of(context).pop(reason),
              ),
            const SizedBox(height: AppSpacing.s),
          ],
        ),
      ),
    );
  }
}

/// Connexion perdue pendant un quiz servi (correction ou question suivante
/// impossible à obtenir) : le joueur réessaie ou quitte.
class _RetrySheet extends StatelessWidget {
  const _RetrySheet({
    required this.message,
    this.onRetry,
    required this.onQuit,
  });

  final String message;

  /// `null` : réessayer ne servirait à rien, seul « Quitter » est proposé.
  final VoidCallback? onRetry;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceContainerLowest,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.large)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(onRetry == null ? Icons.sync_problem : Icons.wifi_off,
                      color: c.error),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Text(
                      message,
                      style: context.text.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            if (onRetry != null) ...[
              FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
              TextButton(
                  onPressed: onQuit, child: const Text('Quitter le quiz')),
            ] else
              FilledButton(
                  onPressed: onQuit, child: const Text('Quitter le quiz')),
            const SizedBox(height: AppSpacing.s),
          ],
        ),
      ),
    );
  }
}

class _XpDetail extends StatelessWidget {
  const _XpDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: context.colors.outlineVariant, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.engagement.xp),
          const SizedBox(width: 4),
          Text(label, style: context.text.labelSmall?.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
