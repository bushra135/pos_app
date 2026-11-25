import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import 'motion.dart';

/// Which screen the backdrop sits behind. Both share one visual language (a slow indigo
/// aurora and a few shop-counter shapes) but each has its own composition.
enum AuthScene { signIn, createAccount }

/// The animated backdrop of the sign-in and create-account screens.
///
/// A soft aurora of indigo and lavender light drifts slowly across the top, and a few
/// translucent shapes from the shop counter (a price tag, a receipt roll, a coin) float
/// gently around it. Everything is painted in one [CustomPainter] behind a
/// [RepaintBoundary], so a frame costs a handful of gradient fills. The motion runs on a
/// shared clock, so moving between the two screens keeps the drift continuous. With
/// reduced motion the scene fades in and then stays still.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key, this.scene = AuthScene.signIn});

  final AuthScene scene;

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

/// One clock for every backdrop, so the drift does not restart on a screen change.
final Stopwatch _clock = Stopwatch()..start();

class _AuthBackgroundState extends State<AuthBackground> with TickerProviderStateMixin {
  // Loops forever while the screen is visible; the painter reads the shared clock from it.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  // The one authored moment: the light blooms in when the screen opens.
  late final AnimationController _bloom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = Motion.reduced(context);
    if (reduced) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
    if (_bloom.status == AnimationStatus.dismissed) _bloom.forward();
  }

  @override
  void dispose() {
    _drift.dispose();
    _bloom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AuthPainter(
            scene: widget.scene,
            drift: _drift,
            bloom: CurvedAnimation(parent: _bloom, curve: _easeOut),
            moving: !reduced,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}

/// Strong ease-out for arrivals (Emil Kowalski's UI curve).
const Curve _easeOut = Cubic(0.23, 1, 0.32, 1);

/// A soft light: centre, radius (as fractions of the screen) and its drift.
class _Glow {
  const _Glow(this.x, this.y, this.r, this.color, this.alpha, this.period, this.phase, this.reach);
  final double x, y, r;
  final Color color;
  final double alpha;
  final double period; // seconds per loop
  final double phase;
  final double reach; // drift distance as a fraction of the shorter side
}

enum _ShapeKind { tag, roll, coin }

/// A floating counter shape: where it rests, how big it is and how it bobs.
class _Shape {
  const _Shape(this.kind, this.x, this.y, this.size, this.tilt, this.period, this.phase);
  final _ShapeKind kind;
  final double x, y, size, tilt, period, phase;
}

const _signInGlows = [
  _Glow(0.30, 0.10, 0.62, AppColors.primary, 0.24, 23, 0.0, 0.10),
  _Glow(0.82, 0.04, 0.55, AppColors.accent, 0.28, 29, 1.7, 0.10),
  _Glow(0.58, 0.30, 0.46, Color(0xFF9B8CF0), 0.18, 19, 3.1, 0.09),
];

const _createGlows = [
  _Glow(0.92, 0.00, 0.60, AppColors.accent, 0.22, 27, 0.6, 0.07),
  _Glow(0.10, 0.08, 0.40, AppColors.primary, 0.14, 21, 2.3, 0.05),
  _Glow(0.05, 1.02, 0.62, Color(0xFF9B8CF0), 0.18, 31, 4.0, 0.06),
];

// Resting places stay around the edges, clear of the fields and buttons.
const _signInShapes = [
  _Shape(_ShapeKind.tag, 0.12, 0.13, 46, -0.20, 9, 0.0),
  _Shape(_ShapeKind.coin, 0.88, 0.25, 30, 0.0, 7, 1.3),
  _Shape(_ShapeKind.roll, 0.10, 0.28, 32, 0.18, 11, 2.6),
];

const _createShapes = [
  _Shape(_ShapeKind.roll, 0.93, 0.035, 30, -0.16, 10, 0.4),
  _Shape(_ShapeKind.tag, 0.80, 0.985, 40, 0.14, 9, 2.0),
];

class _AuthPainter extends CustomPainter {
  _AuthPainter({
    required this.scene,
    required this.drift,
    required this.bloom,
    required this.moving,
    required this.rtl,
  }) : super(repaint: Listenable.merge([drift, bloom]));

  final AuthScene scene;
  final Animation<double> drift;
  final Animation<double> bloom;
  final bool moving;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.background);
    // Seconds on the shared clock; frozen at a pleasant pose with reduced motion.
    final t = moving ? _clock.elapsedMilliseconds / 1000.0 : 6.0;
    final b = bloom.value;
    final side = math.min(size.width, size.height);
    final glows = scene == AuthScene.signIn ? _signInGlows : _createGlows;
    final shapes = scene == AuthScene.signIn ? _signInShapes : _createShapes;
    // Mirror the composition for right-to-left, so it follows the reading direction.
    double fx(double x) => (rtl ? 1 - x : x) * size.width;

    for (final g in glows) {
      final a = 2 * math.pi * (t / g.period) + g.phase;
      final c = Offset(
        fx(g.x) + math.cos(a) * g.reach * side,
        g.y * size.height + math.sin(a * 0.8) * g.reach * side * 0.7,
      );
      final r = math.max(size.width, 360.0) * g.r * (0.9 + 0.1 * b);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              g.color.withValues(alpha: g.alpha * b),
              g.color.withValues(alpha: g.alpha * 0.45 * b),
              g.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Let the light settle into the plain ground before the form, keeping text crisp.
    final fadeTop = scene == AuthScene.signIn ? 0.42 : 0.30;
    final fadeBottom = scene == AuthScene.signIn ? 0.62 : 0.55;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background.withValues(alpha: 0.92),
            AppColors.background.withValues(alpha: 0.92),
            AppColors.background.withValues(alpha: 0),
          ],
          stops: [fadeTop, fadeBottom, 0.86, 1],
        ).createShader(Offset.zero & size),
    );

    for (final s in shapes) {
      final a = 2 * math.pi * (t / s.period) + s.phase;
      final c = Offset(fx(s.x), s.y * size.height + math.sin(a) * 9);
      final tilt = (rtl ? -s.tilt : s.tilt) + math.sin(a * 0.7) * 0.06;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      _drawShape(canvas, s, b);
      canvas.restore();
    }
  }

  void _drawShape(Canvas canvas, _Shape s, double b) {
    final fill = Paint()..color = AppColors.surface.withValues(alpha: 0.72 * b);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.primary.withValues(alpha: 0.28 * b);
    final shadow = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08 * b)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final w = s.size;
    switch (s.kind) {
      case _ShapeKind.tag:
        // A price tag: a rounded label with a clipped corner and a string hole.
        final h = w * 0.62;
        final path = Path()
          ..moveTo(-w / 2 + h * 0.42, -h / 2)
          ..lineTo(w / 2 - 6, -h / 2)
          ..quadraticBezierTo(w / 2, -h / 2, w / 2, -h / 2 + 6)
          ..lineTo(w / 2, h / 2 - 6)
          ..quadraticBezierTo(w / 2, h / 2, w / 2 - 6, h / 2)
          ..lineTo(-w / 2 + h * 0.42, h / 2)
          ..lineTo(-w / 2, 0)
          ..close();
        canvas.drawPath(path.shift(const Offset(0, 4)), shadow);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, line);
        canvas.drawCircle(Offset(-w / 2 + h * 0.5, 0), 2.6, line);
        canvas.drawLine(Offset(-w * 0.02, -h * 0.14), Offset(w * 0.32, -h * 0.14), line);
        canvas.drawLine(Offset(-w * 0.02, h * 0.14), Offset(w * 0.18, h * 0.14), line);
      case _ShapeKind.roll:
        // A receipt: a short slip with a torn bottom edge and printed lines.
        final h = w * 1.25;
        final path = Path()
          ..moveTo(-w / 2, -h / 2)
          ..lineTo(w / 2, -h / 2)
          ..lineTo(w / 2, h / 2);
        const teeth = 5;
        for (var i = 0; i < teeth; i++) {
          final x0 = w / 2 - (i + 0.5) * w / teeth;
          final x1 = w / 2 - (i + 1) * w / teeth;
          path
            ..lineTo(x0, h / 2 - 4)
            ..lineTo(x1, h / 2);
        }
        path.close();
        canvas.drawPath(path.shift(const Offset(0, 4)), shadow);
        canvas.drawPath(path, fill);
        canvas.drawPath(path, line);
        for (var i = 0; i < 3; i++) {
          final y = -h / 2 + h * (0.22 + i * 0.18);
          canvas.drawLine(Offset(-w * 0.3, y), Offset(w * (i == 2 ? 0.05 : 0.3), y), line);
        }
      case _ShapeKind.coin:
        // A coin: a disc with an inner ring.
        canvas.drawCircle(const Offset(0, 4), w / 2, shadow);
        canvas.drawCircle(Offset.zero, w / 2, fill);
        canvas.drawCircle(Offset.zero, w / 2, line);
        canvas.drawCircle(Offset.zero, w * 0.32, line);
    }
  }

  @override
  bool shouldRepaint(_AuthPainter old) =>
      old.scene != scene || old.moving != moving || old.rtl != rtl;
}
