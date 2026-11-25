import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Confettis du 10/10 (charte § 7 bis) : rectangles et ronds, ~40 particules,
/// deux émetteurs en haut à gauche et à droite, 1,2 s.
/// Ne s'affiche pas si « Réduire les animations » est actif.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  static const colors = [
    Color(0xFFD63A1F), // corail
    Color(0xFFFFC23D), // safran
    Color(0xFF0E6E72), // canard
    Color(0xFF17784A), // vert
    Color(0xFF1F5E8C), // glacier
  ];

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _particles = [
      for (var i = 0; i < 40; i++)
        _Particle(
          fromLeft: i.isEven,
          angle: (i.isEven ? 1 : -1) * (0.15 + r.nextDouble() * 0.9),
          speed: 0.5 + r.nextDouble() * 0.6,
          spin: (r.nextDouble() - 0.5) * 12,
          color: ConfettiBurst.colors[i % ConfettiBurst.colors.length],
          round: i % 3 == 0,
        ),
    ];
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_particles, _controller.value),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.fromLeft,
    required this.angle,
    required this.speed,
    required this.spin,
    required this.color,
    required this.round,
  });

  final bool fromLeft;

  /// Écart par rapport à la verticale descendante, en radians.
  final double angle;
  final double speed;
  final double spin;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = t < 0.75 ? 1.0 : (1 - t) / 0.25;
    for (final p in particles) {
      final origin = Offset(p.fromLeft ? 0 : size.width, 0);
      final dist = p.speed * size.height * 0.55 * t;
      final dx = math.sin(p.angle.abs()) * dist * (p.fromLeft ? 1 : -1);
      final dy = math.cos(p.angle.abs()) * dist * 0.6 + 260 * t * t;
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * t);
      if (p.round) {
        canvas.drawCircle(Offset.zero, 5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4.5, -7, 9, 14),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
