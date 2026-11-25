import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_language.dart';
import '../app/app_spacing.dart';

/// Shared motion for the app: short, calm, and switched off entirely when the
/// device asks for reduced motion (MediaQuery.disableAnimations).
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 900);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Fades and rises into place once; [index] staggers siblings by 60 ms.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 14});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  // The stagger is part of the animation (an Interval), so no timer is left pending.
  late final int _delayMs = 60 * widget.index.clamp(0, 8);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium + Duration(milliseconds: _delayMs),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayMs / (Motion.medium.inMilliseconds + _delayMs), 1, curve: Motion.curve),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
      ),
    );
  }
}

/// A number that counts up to [value] the first time, then eases to each new value.
/// Only the shown digits move; the real value is never altered.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.format, this.style});

  final double value;
  final String Function(double value) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return Text(format(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: Motion.slow,
      curve: Curves.easeOutQuart,
      builder: (context, shown, _) => Text(
        // The final frame always prints the exact value.
        format(shown == value ? value : shown),
        style: style,
      ),
    );
  }
}

/// Gentle press feedback for cards and large buttons: scales to 97% while held.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: Motion.fast,
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}

/// A placeholder block that softly pulses while real data loads.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius});

  final double height;
  final double? width;
  final double? radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_controller),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(widget.radius ?? AppSpacing.controlRadius),
        ),
      ),
    );
  }
}

/// Loading layout for a home screen: the hero card and a grid of tiles as skeletons.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key, this.tiles = 4});

  final int tiles;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading'.tr,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 28, AppSpacing.page, 24),
        children: [
          const SkeletonBox(height: 14, width: 120),
          const SizedBox(height: 10),
          const SkeletonBox(height: 26, width: 200),
          const SizedBox(height: 20),
          SkeletonBox(height: 150, radius: AppSpacing.cardRadius),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [for (var i = 0; i < tiles; i++) SkeletonBox(radius: AppSpacing.cardRadius)],
          ),
        ],
      ),
    );
  }
}

/// Cross-fades between screens (bottom tabs), with a slight rise.
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Motion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Text that rolls up to its new value (a cart total, an item count), so each added
/// item is felt at a glance.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, key: ValueKey(text), style: style);
    if (Motion.reduced(context)) return label;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Motion.curve,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(text);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: Offset(0, incoming ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      layoutBuilder: (current, previous) =>
          Stack(alignment: AlignmentDirectional.centerEnd, children: [...previous, ?current]),
      child: label,
    );
  }
}

/// Page transition for every platform: a quick fade with a slight rise. Light on the
/// GPU, and none at all when the device asks for reduced motion.
class CalmPageTransitionsBuilder extends PageTransitionsBuilder {
  const CalmPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Motion.reduced(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
