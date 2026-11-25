import 'package:material_ui/material_ui.dart';

import '../engagement/dates.dart';
import '../engagement/streak_rules.dart';
import '../models/streak.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// Pastille série (AppBar) : safran, flamme encre + nombre de jours.
class StreakChip extends StatelessWidget {
  const StreakChip({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Série de $count ${count > 1 ? 'jours' : 'jour'}',
      child: Material(
        color: c.tertiary,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlameIcon(size: 24, color: c.onTertiary),
                    const SizedBox(width: 6),
                    Text('$count',
                        style: _chipNumber(context, 20, c.onTertiary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille gel : fond glacier conteneur, flocon + nombre de gels.
class FreezeChip extends StatelessWidget {
  const FreezeChip({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    final shape = StadiumBorder(
      side: e.gelBorder == null
          ? BorderSide.none
          : BorderSide(color: e.gelBorder!, width: 1.5),
    );
    return Semantics(
      button: true,
      label: '$count ${count > 1 ? 'gels' : 'gel'} de série en réserve',
      child: Material(
        color: e.gelContainer,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ac_unit, size: 20, color: e.gel),
                    const SizedBox(width: 6),
                    Text('$count',
                        style: _chipNumber(context, 18, e.onGelContainer)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _chipNumber(BuildContext context, double size, Color color) =>
    TextStyle(
      fontFamily: AppFonts.titre,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1,
      color: color,
    );

/// Jauge de l'objectif du jour : N segments (1 à 3).
class GoalGauge extends StatelessWidget {
  const GoalGauge({
    super.key,
    required this.done,
    required this.goal,
    this.height = 10,
    this.gap = 6,
  });

  final int done;
  final int goal;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reached = done >= goal;
    final duration = context.reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 400);
    return Row(
      children: [
        for (var i = 0; i < goal; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                color: reached
                    ? context.quizColors.success
                    : i < done
                        ? c.primary
                        : c.outlineVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pastille ronde du niveau (canard, numéro blanc).
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level, this.size = 40});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: e.xp, shape: BoxShape.circle),
      child: Text('$level', style: _chipNumber(context, 18, e.onXp)),
    );
  }
}

/// Barre d'XP : part acquise en canard, [gain] (fraction) en safran.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.value, this.gain = 0});

  final double value;
  final double gain;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final v = value.clamp(0.0, 1.0);
            final g = gain.clamp(0.0, 1.0 - v);
            return Stack(
              children: [
                Container(color: context.colors.outlineVariant),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: w * v,
                  child: Container(color: e.xp),
                ),
                Positioned(
                  left: w * v,
                  top: 0,
                  bottom: 0,
                  width: w * g,
                  child: Container(color: e.xpGain),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Badge « +15 XP ».
class XpBadge extends StatelessWidget {
  const XpBadge({super.key, required this.xp, this.large = false});

  final int xp;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    return Semantics(
      label: 'Plus $xp XP',
      child: ExcludeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: large ? 40 : 32),
          padding: EdgeInsets.symmetric(horizontal: large ? 14 : 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: e.xpContainer,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text('+$xp XP',
              style: _chipNumber(context, large ? 20 : 16, e.onXpContainer)),
        ),
      ),
    );
  }
}

/// Pilule « Combo x3 » (affichée à partir de x2).
class ComboChip extends StatelessWidget {
  const ComboChip({super.key, required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    return Semantics(
      label: 'Combo de $combo bonnes réponses',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
          decoration: BoxDecoration(
            color: e.comboBg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: e.comboBorder == null
                ? null
                : Border.all(color: e.comboBorder!, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 18, color: e.comboIcon),
              const SizedBox(width: 6),
              Text('Combo x$combo',
                  style: _chipNumber(context, 15, e.comboText)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rangée de 7 jours (accueil : 7 derniers jours ; série : semaine en cours).
class WeekRow extends StatelessWidget {
  const WeekRow({
    super.key,
    required this.streak,
    required this.today,
    required this.firstDay,
  });

  final Streak streak;
  final DateTime today;
  final DateTime firstDay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = context.engagement;
    final q = context.quizColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final day = addDays(firstDay, i);
            final isToday = isSameDay(day, today);
            final status = dayStatus(streak, day, today);
            final label = isToday && daysBetween(firstDay, today) == 6
                ? 'Auj.'
                : weekdayLetter(day);
            Widget dot;
            switch (status) {
              case DayStatus.played:
                dot = _Dot(
                  color: c.tertiary,
                  border:
                      isToday ? Border.all(color: c.primary, width: 3) : null,
                  child: Icon(Icons.check, size: 18, color: c.onTertiary),
                );
              case DayStatus.frozen:
                dot = _Dot(
                  color: e.gelContainer,
                  border: Border.all(color: e.gel, width: 2),
                  child: Icon(Icons.ac_unit, size: 18, color: e.gel),
                );
              case DayStatus.missed:
              case DayStatus.future:
                dot = isToday
                    ? _DashedDot(color: c.primary)
                    : _Dot(border: Border.all(color: c.outline, width: 2));
            }
            final semantic = switch (status) {
              DayStatus.played => 'joué',
              DayStatus.frozen => 'protégé par un gel',
              DayStatus.missed => 'pas joué',
              DayStatus.future => isToday ? 'pas encore joué' : 'à venir',
            };
            return Semantics(
              label:
                  '${formatShortDate(day)}${isToday ? ', aujourd\'hui' : ''} : $semantic',
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 38,
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: context.text.labelSmall?.copyWith(
                          height: 1,
                          color: isToday ? q.primaryText : c.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      dot,
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({this.color, this.border, this.child});

  final Color? color;
  final BoxBorder? border;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: color, shape: BoxShape.circle, border: border),
        child: child,
      );
}

/// Aujourd'hui pas encore joué : anneau corail pointillé.
class _DashedDot extends StatelessWidget {
  const _DashedDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(32),
        painter: _DashedCirclePainter(color),
      );
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final rect = Offset.zero & size;
    const dashes = 12;
    const sweep = 2 * 3.14159265 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(1.5), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

/// Explication du gel (tap sur la pastille gel).
void showFreezeInfo(BuildContext context, int freezes) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.ac_unit, color: context.engagement.gel),
                const SizedBox(width: AppSpacing.s),
                Text('Gel de série', style: context.text.titleLarge),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              'Un gel protège ta série pendant une journée sans jeu. '
              'Il s\'applique tout seul. Tu peux en garder $maxFreezes en réserve.',
              style: context.text.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              freezes == 0
                  ? 'Tu n\'as pas de gel en réserve pour l\'instant.'
                  : 'Tu as $freezes ${freezes > 1 ? 'gels' : 'gel'} en réserve.',
              style: context.text.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
