import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import 'motion.dart';

/// The sign-in background: a clean neutral surface and one soft indigo glow at the
/// top that breathes very slowly.
/// Quiet by design; a still picture with reduced motion.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key});

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _breath.stop();
      _breath.value = 0.5;
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
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(painter: _AuthPainter(_breath), size: Size.infinite),
      ),
    );
  }
}

class _AuthPainter extends CustomPainter {
  _AuthPainter(this.breath) : super(repaint: breath);

  final Animation<double> breath;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.background);

    // One soft glow behind the logo area; it breathes very slightly.
    final t = Curves.easeInOut.transform(breath.value);
    final center = Offset(size.width / 2, size.height * 0.16);
    final radius = math.max(size.width, 420) * (0.62 + 0.05 * t);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.20 + 0.04 * t),
            AppColors.accentSoft.withValues(alpha: 0.35),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AuthPainter oldDelegate) => false;
}
