import 'package:material_ui/material_ui.dart';

import '../models/question.dart';
import '../theme/app_theme.dart';

/// Logotype « quizzéo » : lettres encre, « é » corail (charte § 5).
class QuizzeoLogo extends StatelessWidget {
  const QuizzeoLogo({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppFonts.titre,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1,
      letterSpacing: -0.03 * size,
      color: context.colors.onSurface,
    );
    return Semantics(
      label: 'Quizzéo',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: style,
            children: [
              const TextSpan(text: 'quizz'),
              TextSpan(
                text: 'é',
                style: TextStyle(color: context.colors.primary),
              ),
              const TextSpan(text: 'o'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flamme de série en 2 couleurs (corail + cœur safran), sans personnage.
/// [outline] : série en danger (contour corail seulement).
/// [color] : flamme pleine d'une seule couleur (pastille de l'AppBar).
class FlameIcon extends StatelessWidget {
  const FlameIcon(
      {super.key, this.size = 52, this.outline = false, this.color});

  final double size;
  final bool outline;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final e = context.engagement;
    return CustomPaint(
      size: Size.square(size),
      painter: _FlamePainter(
        outer: color ?? e.flammeExt,
        inner: color == null ? e.flammeInt : null,
        outline: outline,
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.outer, this.inner, required this.outline});

  final Color outer;
  final Color? inner;
  final bool outline;

  // Tracés repris de design/maquettes (symbole i-flamme2, viewBox 48×48).
  static Path _outerPath() => Path()
    ..moveTo(24, 3)
    ..relativeCubicTo(1.7, 7.4, 11.5, 11.6, 11.5, 22.6)
    ..relativeArcToPoint(const Offset(-23, 0),
        radius: const Radius.circular(11.5))
    ..relativeCubicTo(0, -4.8, 2.1, -8, 4.6, -10.3)
    ..relativeCubicTo(.2, 4.2, 1.9, 6.5, 4.2, 7.1)
    ..relativeCubicTo(-.8, -7.1, .2, -13.8, 2.7, -19.4)
    ..close();

  static Path _innerPath() => Path()
    ..moveTo(24.3, 24.5)
    ..relativeCubicTo(.7, 3, 5.2, 4.7, 5.2, 9.6)
    ..relativeArcToPoint(const Offset(-11, 0),
        radius: const Radius.circular(5.5))
    ..relativeCubicTo(0, -2.6, 1.3, -4, 2.4, -4.8)
    ..relativeCubicTo(.2, 1.7, .9, 2.6, 1.7, 2.9)
    ..relativeCubicTo(-.2, -2.8, .5, -5.4, 1.7, -7.7)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    if (outline) {
      canvas.drawPath(
        _outerPath(),
        Paint()
          ..color = outer
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    canvas.drawPath(_outerPath(), Paint()..color = outer);
    if (inner != null) canvas.drawPath(_innerPath(), Paint()..color = inner!);
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.outer != outer || old.inner != inner || old.outline != outline;
}

/// Identifiant pour « Mélange » (toutes catégories).
const mixCategory = 'mix';

IconData categoryIcon(String category) => switch (category) {
      'histoire' => Icons.account_balance_outlined,
      'geo' => Icons.public,
      'sciences' => Icons.science_outlined,
      'arts' => Icons.palette_outlined,
      'sport' => Icons.sports_soccer,
      'actu' => Icons.newspaper,
      'divers' => Icons.casino_outlined,
      _ => Icons.shuffle,
    };

String categoryLabel(String category) =>
    categories[category] ?? (category == mixCategory ? 'Mélange' : category);

/// Pastille de catégorie (écran question).
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final q = context.quizColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: q.categoryTint[category] ?? q.categoryTint[mixCategory],
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(categoryIcon(category),
              size: 18, color: q.categoryIcon[category]),
          const SizedBox(width: 6),
          Flexible(
            child: Text(categoryLabel(category),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
