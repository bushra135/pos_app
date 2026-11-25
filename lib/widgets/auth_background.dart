import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import 'motion.dart';

/// The living background of the sign-in screen: a slowly shifting gradient, glowing
/// orbs drifting at different speeds, small floating particles and two flowing waves.
///
/// Everything is drawn by one painter on one ticker, behind a RepaintBoundary, so the
/// form above it never repaints. With reduced motion it is a still picture.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key});

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> with SingleTickerProviderStateMixin {
  // One slow loop; every element moves at a whole-number multiple of it, so the loop
  // is seamless.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _loop.stop();
      _loop.value = 0.18;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(painter: _AuthPainter(_loop), size: Size.infinite),
      ),
    );
  }
}

class _Particle {
  const _Particle(this.x, this.y, this.radius, this.speed, this.phase, this.alpha);
  final double x, y, radius, speed, phase, alpha;
}

class _AuthPainter extends CustomPainter {
  _AuthPainter(this.loop) : super(repaint: loop);

  final Animation<double> loop;

  static final List<_Particle> _particles = () {
    final random = math.Random(7); // fixed seed: the same sky every time
    return List.generate(
      22,
      (_) => _Particle(
        random.nextDouble(),
        random.nextDouble(),
        1.2 + random.nextDouble() * 2.4,
        (1 + random.nextInt(2)).toDouble(), // whole loops, so the cycle is seamless
        random.nextDouble() * math.pi * 2,
        0.18 + random.nextDouble() * 0.3,
      ),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value; // 0..1
    final a = t * math.pi * 2;
    final rect = Offset.zero & size;

    // 1. Background: light neutral to soft lavender, its direction turning slowly.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(math.cos(a) * 0.6, -1),
          end: Alignment(-math.cos(a) * 0.6, 1),
          colors: const [AppColors.background, Color(0xFFEFEEF9), AppColors.background],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // 2. Glowing orbs: radial gradients fading to transparent, on slow paths.
    void orb(double cx, double cy, double r, Color color, double opacity) {
      final center = Offset(cx * size.width, cy * size.height);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    final unit = math.min(size.width, size.height);
    orb(0.15 + 0.10 * math.sin(a), 0.12 + 0.06 * math.cos(a), unit * 0.62, AppColors.accent, 0.36);
    orb(
      0.90 + 0.08 * math.cos(a * 2),
      0.32 + 0.08 * math.sin(a),
      unit * 0.48,
      AppColors.primary,
      0.16,
    );
    orb(
      0.25 + 0.12 * math.cos(a),
      0.86 + 0.05 * math.sin(a * 2),
      unit * 0.55,
      AppColors.accent,
      0.20,
    );
    orb(
      0.78 + 0.06 * math.sin(a * 2),
      0.95 - 0.04 * math.cos(a),
      unit * 0.40,
      AppColors.primary,
      0.12,
    );

    // 3. Particles rise slowly and sway; they wrap around top to bottom.
    final dot = Paint();
    for (final p in _particles) {
      final y = (p.y - t * p.speed) % 1.0;
      final x = p.x + 0.015 * math.sin(a * p.speed + p.phase);
      // Fade in at the bottom and out at the top.
      final edge = math.min(1.0, math.min(y, 1 - y) * 6);
      dot.color = AppColors.primary.withValues(alpha: p.alpha * edge);
      canvas.drawCircle(Offset(x * size.width, y * size.height), p.radius, dot);
    }

    // 4. Two flowing waves at the bottom, out of phase.
    void wave(double base, double amplitude, double phase, Color color) {
      double yAt(double x) =>
          size.height * base +
          math.sin(x / size.width * math.pi * 2 + a + phase) * amplitude +
          math.sin(x / size.width * math.pi * 4 - a) * amplitude * 0.35;
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x < size.width; x += 8) {
        path.lineTo(x, yAt(x));
      }
      // Always end exactly on the right edge.
      path.lineTo(size.width, yAt(size.width));
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    wave(0.90, 14, 0, AppColors.accent.withValues(alpha: 0.10));
    wave(0.93, 10, math.pi * 0.7, AppColors.primary.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(_AuthPainter oldDelegate) => false;
}
