import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../quiz/quiz_controller.dart';
import '../theme/app_theme.dart';

enum AnswerStatus { neutral, correct, wrong, dimmed }

/// Bouton de réponse (charte § 7) : 60 dp min, pastille lettre, 4 états.
class AnswerButton extends StatelessWidget {
  const AnswerButton({
    super.key,
    required this.letter,
    required this.label,
    required this.status,
    this.onPressed,
  });

  final String letter;
  final String label;
  final AnswerStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = context.quizColors;
    final (Color bg, Color border, Color pillBg, Color pillFg) =
        switch (status) {
      AnswerStatus.correct => (
          q.successContainer,
          q.success,
          q.success,
          q.onSuccess
        ),
      AnswerStatus.wrong => (c.errorContainer, c.error, c.error, c.onError),
      _ => (
          c.surfaceContainerLowest,
          c.outline,
          c.surfaceContainer,
          c.onSurface
        ),
    };
    final stateLabel = switch (status) {
      AnswerStatus.correct => 'Bonne réponse',
      AnswerStatus.wrong => 'Ta réponse',
      _ => null,
    };
    final stateColor = status == AnswerStatus.correct
        ? q.onSuccessContainer
        : c.onErrorContainer;

    final button = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        side: BorderSide(color: border, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: onPressed,
        overlayColor: WidgetStatePropertyAll(c.primaryContainer),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: switch (status) {
                    AnswerStatus.correct =>
                      Icon(Icons.check, size: 20, color: pillFg, weight: 700),
                    AnswerStatus.wrong =>
                      Icon(Icons.close, size: 20, color: pillFg, weight: 700),
                    _ => Text(
                        letter,
                        style: TextStyle(
                          fontFamily: AppFonts.titre,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: pillFg,
                        ),
                      ),
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(height: 1.3),
                  ),
                ),
                if (stateLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    stateLabel,
                    style: context.text.labelSmall?.copyWith(color: stateColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: stateLabel == null ? null : '$label, ${stateLabel.toLowerCase()}',
      child: Opacity(
        opacity: status == AnswerStatus.dimmed ? 0.55 : 1,
        child: button,
      ),
    );
  }
}

/// Anneau du minuteur (56 dp, trait 5) avec les secondes au centre.
class TimerRing extends StatelessWidget {
  const TimerRing({super.key, required this.secondsLeft, required this.frozen});

  final int secondsLeft;

  /// Réponse donnée : anneau figé en gris.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = context.quizColors;
    final Color ring;
    Color? center;
    if (frozen) {
      ring = c.outline;
    } else if (secondsLeft > 10) {
      ring = c.secondary;
    } else if (secondsLeft > 5) {
      ring = q.timerWarning;
      center = c.tertiary;
    } else {
      ring = c.primary;
      center = c.tertiary;
    }
    final announce = !frozen && (secondsLeft == 10 || secondsLeft == 5);
    return Semantics(
      liveRegion: announce,
      label: '$secondsLeft secondes restantes',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 56,
          child: CustomPaint(
            painter: RingPainter(
              value: secondsLeft / questionSeconds,
              color: ring,
              track: c.outlineVariant,
              stroke: 5,
            ),
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: center == null
                    ? null
                    : BoxDecoration(color: center, shape: BoxShape.circle),
                child: Text(
                  '$secondsLeft',
                  style: TextStyle(
                    fontFamily: AppFonts.titre,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1,
                    color: center == null ? c.onSurface : c.onTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anneau de progression (minuteur, score).
class RingPainter extends CustomPainter {
  RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base..color = track);
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      base
        ..color = color
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

enum SegmentStatus { ok, ko, current, todo }

/// 10 segments de progression du quiz.
class QuizSegments extends StatelessWidget {
  const QuizSegments({super.key, required this.statuses});

  final List<SegmentStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = context.quizColors;
    return Row(
      children: [
        for (var i = 0; i < statuses.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: switch (statuses[i]) {
                  SegmentStatus.ok => q.success,
                  SegmentStatus.ko => c.error,
                  SegmentStatus.current => c.onSurface,
                  SegmentStatus.todo => c.outlineVariant,
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Source de l'explication, discrète (charte : petit texte, encre douce) :
/// « Source : Larousse ». Affichée seulement si la question en a une.
class SourceLabel extends StatelessWidget {
  const SourceLabel(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) => Text('Source : $source',
      style: context.text.bodySmall
          ?.copyWith(color: context.colors.onSurfaceVariant));
}
