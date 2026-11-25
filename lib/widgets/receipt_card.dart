import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_spacing.dart';

/// The app's one signature shape: a card cut like a till receipt, with rounded top
/// corners and a torn, zig-zag bottom edge.
///
/// Used only where money is totalled (today's sales, checkout total) so the shape
/// itself says "this is the receipt number". Everything else stays a plain card.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({
    super.key,
    required this.child,
    this.color = AppColors.hero,
    this.gradient,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 16),
  });

  final Widget child;
  final Color color;

  /// Optional soft gradient in place of [color] (the sales card).
  final Gradient? gradient;
  final EdgeInsets padding;

  /// Height of one zig-zag tooth.
  static const double tooth = 7;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _ReceiptEdge(),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: gradient == null ? color : null, gradient: gradient),
        child: Padding(
          padding: padding.copyWith(bottom: padding.bottom + tooth),
          // Screen readers announce the label and amount together.
          child: MergeSemantics(child: child),
        ),
      ),
    );
  }
}

class _ReceiptEdge extends CustomClipper<Path> {
  const _ReceiptEdge();

  @override
  Path getClip(Size size) {
    const radius = AppSpacing.cardRadius;
    const toothWidth = 14.0;
    const depth = ReceiptCard.tooth;
    final count = (size.width / toothWidth).floor().clamp(1, 1000);
    final step = size.width / count;
    final bottom = size.height;

    final path = Path()
      ..moveTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, bottom - depth);
    // Teeth run right to left back to the start.
    for (var i = count; i > 0; i--) {
      final x = i * step;
      path
        ..lineTo(x - step / 2, bottom)
        ..lineTo(x - step, bottom - depth);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Dotted tear line, like the perforation between a receipt's total and its details.
class ReceiptRule extends StatelessWidget {
  const ReceiptRule({super.key, this.color = AppColors.heroLine});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + dash, size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
