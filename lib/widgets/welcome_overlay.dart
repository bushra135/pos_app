import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_language.dart';
import '../app/app_typography.dart';
import 'motion.dart';

/// A short welcome over the first screen after signing in: the person's first name,
/// their store and role. Shown once per sign-in, fades away by itself in about a
/// second, can be tapped away, and is skipped entirely with reduced motion.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({
    super.key,
    required this.uid,
    required this.name,
    required this.storeName,
    required this.isOwner,
    required this.child,
  });

  final String uid;
  final String name;
  final String storeName;
  final bool isOwner;
  final Widget child;

  /// Accounts already welcomed in this app session (a refresh does not repeat it).
  static final Set<String> _welcomed = {};

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _visible = false;
  Timer? _done;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visible || WelcomeGate._welcomed.contains(widget.uid)) return;
    WelcomeGate._welcomed.add(widget.uid);
    if (Motion.reduced(context)) return;
    _visible = true;
    _controller.forward();
    _done = Timer(const Duration(milliseconds: 1500), _dismiss);
  }

  void _dismiss() {
    _done?.cancel();
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _done?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    final first = widget.name.trim().split(' ').first;
    final hello = hour < 12
        ? 'Good morning'.tr
        : hour < 18
        ? 'Good afternoon'.tr
        : 'Good evening'.tr;
    return first.isEmpty ? hello : '$hello${AppLanguage.isArabic ? '،' : ','} $first';
  }

  @override
  Widget build(BuildContext context) {
    // In, hold, out: the overlay fades in over the first 20% and out over the last 25%.
    final fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
    ]).animate(_controller);
    final rise = Tween(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.35, curve: Motion.curve),
      ),
    );
    return Stack(
      // Always the full screen, whatever the screen beneath measures.
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismiss,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Opacity(
                  opacity: fade.value,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.background, AppColors.hero],
                      ),
                    ),
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, rise.value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Icons.point_of_sale_rounded,
                                color: AppColors.onBrand,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _greeting,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: AppTypography.display,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (widget.storeName.isNotEmpty) widget.storeName,
                                (widget.isOwner ? 'Owner' : 'Cashier').tr,
                              ].join(' · '),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
