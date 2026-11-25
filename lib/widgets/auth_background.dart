import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import 'motion.dart';

/// Strong ease-out for entrances (Emil Kowalski's UI curve).
const _easeOut = Cubic(0.23, 1, 0.32, 1);

/// The sign-in backdrop: an ice-blue light falls from the top of the screen and
/// drifts slowly from side to side, like daylight on a shop counter.
/// It is the quiet layer; the scanner frame around the logo is the moment.
/// A still picture with reduced motion.
class AuthBackground extends StatefulWidget {
  const AuthBackground({super.key});

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _drift.stop();
      _drift.value = 0.5;
    } else if (!_drift.isAnimating) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(painter: _FrostPainter(_drift), size: Size.infinite),
      ),
    );
  }
}

class _FrostPainter extends CustomPainter {
  _FrostPainter(this.drift) : super(repaint: drift);

  final Animation<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.background);

    // Layer 1: an ice wash over the top of the screen that fades into the page.
    final wash = Rect.fromLTWH(0, 0, size.width, size.height * 0.52);
    canvas.drawRect(
      wash,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.ice, AppColors.ice.withValues(alpha: 0.45), AppColors.background],
          stops: const [0, 0.55, 1],
        ).createShader(wash),
    );

    // Layer 2: a soft white light that drifts slowly across the top.
    final t = Curves.easeInOut.transform(drift.value);
    final center = Offset(size.width * (0.38 + 0.24 * t), size.height * 0.08);
    final radius = math.max(size.width, 420) * 0.58;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_FrostPainter oldDelegate) => false;
}

/// Viewfinder corners around [child] (the same shape as the barcode scanner) with
/// a light beam that passes over it.
///
/// On entry the corners draw in, then the beam sweeps down once every few
/// seconds. While [scanning] is true (signing in) the beam scans up and down
/// continuously, so the motion also says "working". With reduced motion the
/// corners are shown still and there is no beam.
class ScanFrame extends StatefulWidget {
  const ScanFrame({super.key, required this.child, this.scanning = false, this.extent = 176});

  final Widget child;
  final bool scanning;
  final double extent;

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame> with TickerProviderStateMixin {
  static const _idlePeriod = Duration(milliseconds: 5200);
  static const _sweep = Duration(milliseconds: 1400);
  static const _scanPass = Duration(milliseconds: 900);

  // Corners start once the logo has mostly landed (the logo takes 700 ms).
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..addStatusListener(_onIntro);
  late final Animation<double> _corners = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.3, 1, curve: _easeOut),
  );
  late final AnimationController _beam = AnimationController(vsync: this);
  bool _reduced = false;
  bool _started = false;

  void _onIntro(AnimationStatus status) {
    if (status == AnimationStatus.completed) _runBeam();
  }

  void _runBeam() {
    if (_reduced || !mounted) return;
    if (widget.scanning) {
      _beam
        ..duration = _scanPass
        ..repeat(reverse: true);
    } else {
      _beam
        ..duration = _idlePeriod
        ..repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.reduced(context);
    if (_reduced) {
      _intro.value = 1;
      _beam
        ..stop()
        ..value = 0;
    } else if (!_started) {
      _intro.forward();
    } else if (!_beam.isAnimating && _intro.isCompleted) {
      _runBeam();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(ScanFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanning != widget.scanning && _intro.isCompleted) {
      _beam.value = 0;
      _runBeam();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _beam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ScanPainter(
                      corners: _corners,
                      beam: _beam,
                      scanning: widget.scanning,
                      showBeam: !_reduced,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  _ScanPainter({
    required this.corners,
    required this.beam,
    required this.scanning,
    required this.showBeam,
  }) : super(repaint: Listenable.merge([corners, beam]));

  final Animation<double> corners;
  final AnimationController beam;
  final bool scanning;
  final bool showBeam;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    _paintCorners(canvas, frame.deflate(6), corners.value);
    if (showBeam && corners.value > 0.99) _paintBeam(canvas, frame.deflate(18));
  }

  void _paintCorners(Canvas canvas, Rect r, double t) {
    if (t <= 0) return;
    final len = 28 * t;
    const bend = 10.0;
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.25 + 0.75 * t)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    // Each corner grows from its elbow outward.
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * math.max(len, bend))
        ..lineTo(corner.dx, corner.dy + dy * bend)
        ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * bend, corner.dy)
        ..lineTo(corner.dx + dx * math.max(len, bend), corner.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _paintBeam(Canvas canvas, Rect r) {
    double p;
    bool goingDown;
    if (scanning) {
      p = Curves.easeInOut.transform(beam.value);
      goingDown = beam.status != AnimationStatus.reverse;
    } else {
      // One sweep at the start of each period, then rest.
      final sweepEnd =
          _ScanFrameState._sweep.inMilliseconds / _ScanFrameState._idlePeriod.inMilliseconds;
      if (beam.value >= sweepEnd) return;
      p = Curves.easeInOut.transform(beam.value / sweepEnd);
      goingDown = true;
    }
    // Fades in at the top edge and out at the bottom edge.
    final o = scanning ? 1.0 : math.sin(math.pi * p).clamp(0.0, 1.0);
    if (o <= 0.01) return;
    final y = r.top + p * r.height;
    final a = Offset(r.left, y);
    final b = Offset(r.right, y);

    // A short light trail behind the beam.
    const trail = 34.0;
    final tail = goingDown
        ? Rect.fromLTRB(r.left, y - trail, r.right, y)
        : Rect.fromLTRB(r.left, y, r.right, y + trail);
    // The trail stays inside the frame, even at the top and bottom edges.
    canvas.drawRect(
      tail.intersect(r),
      Paint()
        ..shader = LinearGradient(
          begin: goingDown ? Alignment.bottomCenter : Alignment.topCenter,
          end: goingDown ? Alignment.topCenter : Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.16 * o),
            AppColors.primary.withValues(alpha: 0),
          ],
        ).createShader(tail),
    );
    // Glow, then the bright core line.
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.35 * o)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = AppColors.primary.withValues(alpha: o)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScanPainter oldDelegate) =>
      oldDelegate.scanning != scanning || oldDelegate.showBeam != showBeam;
}
