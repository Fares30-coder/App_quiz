import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../share/share_content.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

/// Image de partage 9:16, gabarit de `design/visuels/partage-score.html`.
/// Zone logique 360×640, capturée à l'échelle 3 (1080×1920).
/// Toujours en thème clair (fond crème), quel que soit le thème de l'appareil.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.content});

  static const size = Size(360, 640);
  static const pixelRatio = 3.0;

  final ShareContent content;

  static const _creme = Color(0xFFFFF7EE);
  static const _encre = Color(0xFF1A1B3A);
  static const _encre2 = Color(0xFF4A4C6B);
  static const _lin = Color(0xFFE6DED2);
  static const _corail = Color(0xFFD63A1F);
  static const _safran = Color(0xFFFFC23D);

  static TextStyle _titre(double size, {double height = 1, double ls = 0}) =>
      TextStyle(
        fontFamily: AppFonts.titre,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: height,
        letterSpacing: ls * size,
        color: _encre,
      );

  static TextStyle _texte(double size, {Color color = _encre}) => TextStyle(
        fontFamily: AppFonts.texte,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final score = content.kind == ShareKind.score;
    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: _creme,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
          child: Column(
            children: [
              const QuizzeoLogo(size: 40),
              const SizedBox(height: 14),
              _OneLine(
                Text(content.overline,
                    style: _texte(13).copyWith(letterSpacing: 0.08 * 13)),
              ),
              const SizedBox(height: 14),
              if (score) ...[
                _ScoreRing(score: content.score, total: content.total),
                const SizedBox(height: 16),
                _headline(),
                const SizedBox(height: 18),
                _Dots(answers: content.answers),
                if (content.streakLabel != null) ...[
                  const SizedBox(height: 18),
                  _StreakPill(label: content.streakLabel!),
                ],
              ] else ...[
                const FlameIcon(size: 150),
                _OneLine(Text('${content.streakDays}',
                    style: _titre(92, ls: -0.04))),
                const SizedBox(height: 6),
                Text(
                    content.streakDays > 1 ? 'jours de série' : 'jour de série',
                    style: _texte(18, color: _encre2)),
                const SizedBox(height: 24),
                _headline(),
              ],
              const Spacer(),
              const SizedBox(height: 16),
              _OneLine(
                  Text(content.challenge, style: _titre(34, height: 1.05))),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: _corail,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: _OneLine(
                  Text(content.cta, style: _texte(17, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headline() => _OneLine(
        Text(
          content.headline,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: _titre(30, height: 1.1, ls: -0.02),
        ),
      );
}

/// Réduit le texte s'il dépasse la largeur (jamais de coupure ni débordement).
class _OneLine extends StatelessWidget {
  const _OneLine(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: child);
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.total});

  final int score;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 200,
      child: CustomPaint(
        painter: _RingPainter(total == 0 ? 0 : score / total),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$score', style: ShareCard._titre(92, ls: -0.04)),
            const SizedBox(height: 2),
            Text('sur $total',
                style: ShareCard._texte(18, color: ShareCard._encre2)),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: 84,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(rect.center, 84, paint..color = ShareCard._lin);
    if (value <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * value.clamp(0, 1),
      false,
      paint
        ..color = ShareCard._corail
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

class _Dots extends StatelessWidget {
  const _Dots({required this.answers});

  final List<bool> answers;

  @override
  Widget build(BuildContext context) {
    return _OneLine(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < answers.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: answers[i]
                    ? const Color(0xFFDDF3E6)
                    : const Color(0xFFFCE3E5),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: CustomPaint(
                size: const Size.square(15),
                painter: _MarkPainter(answers[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Coche ou croix (tracés de partage-score.html, viewBox 24×24).
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.correct);

  final bool correct;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = correct ? const Color(0xFF17784A) : const Color(0xFFC42B3A);
    final path = correct
        ? (Path()
          ..moveTo(5, 12.5)
          ..lineTo(9.5, 17)
          ..lineTo(19, 7))
        : (Path()
          ..moveTo(6, 6)
          ..lineTo(18, 18)
          ..moveTo(18, 6)
          ..lineTo(6, 18));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.correct != correct;
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: ShareCard._safran,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlameIcon(size: 18, color: ShareCard._corail),
          const SizedBox(width: 6),
          Text(label, style: ShareCard._titre(16)),
        ],
      ),
    );
  }
}
