import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_language.dart';
import '../app/app_spacing.dart';
import '../app/app_typography.dart';
import 'motion.dart';

/// The ShopPad mark, shared between sign-in and sign-up (it carries across the page
/// change) and easing in with a small lift when a screen opens.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 112});

  final double size;

  static const heroTag = 'shoppad-logo';

  @override
  Widget build(BuildContext context) {
    final logo = Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: AppColors.primaryDark,
      colorBlendMode: BlendMode.srcIn,
      semanticLabel: 'ShopPad logo'.tr,
    );
    // A soft halo behind the mark: the only gradient on the sign-in screens.
    final mark = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 1.55,
          height: size * 1.55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [AppColors.accentSoft, AppColors.background.withValues(alpha: 0)],
            ),
          ),
        ),
        logo,
      ],
    );
    final hero = Hero(tag: heroTag, child: mark);
    if (Motion.reduced(context)) return hero;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
      ),
      child: hero,
    );
  }
}

/// A form field that glows softly and lifts its label to the brand colour while
/// focused. Wraps any TextField / TextFormField.
class GlowField extends StatefulWidget {
  const GlowField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<GlowField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final duration = reduced ? Duration.zero : Motion.fast;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedDefaultTextStyle(
              duration: duration,
              style: TextStyle(
                fontFamily: AppTypography.family,
                color: _focused ? AppColors.primaryDark : AppColors.text,
                fontSize: AppTypography.body,
                fontWeight: FontWeight.w700,
              ),
              child: Text(widget.label),
            ),
          ),
          AnimatedContainer(
            duration: duration,
            curve: Motion.curve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _focused ? 0.16 : 0),
                  blurRadius: _focused ? 16 : 0,
                  spreadRadius: _focused ? 1 : 0,
                ),
              ],
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// The eye that shows or hides the password, flipping as it changes.
class PasswordEye extends StatelessWidget {
  const PasswordEye({super.key, required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      key: ValueKey(visible),
      color: visible ? AppColors.primaryDark : AppColors.muted,
    );
    return IconButton(
      tooltip: (visible ? 'Hide password' : 'Show password').tr,
      onPressed: onPressed,
      icon: Motion.reduced(context)
          ? icon
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: RotationTransition(
                  turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: icon,
            ),
    );
  }
}

/// Shakes its child sideways once each time [trigger] changes (a failed sign-in).
class ShakeOnChange extends StatelessWidget {
  const ShakeOnChange({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (trigger == 0 || Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, child) => Transform.translate(
        // Three decaying swings, 8 px at most.
        offset: Offset(math.sin(t * math.pi * 6) * 8 * (1 - t), 0),
        child: child,
      ),
      child: child,
    );
  }
}

/// A friendly inline message under a form; slides open and closed.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, required this.message});

  /// Already translated text, or null for none.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final text = message;
    return AnimatedSize(
      duration: reduced ? Duration.zero : Motion.medium,
      curve: Motion.curve,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : FadeSlideIn(
              key: ValueKey(text),
              offset: 6,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            text,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Styles shared by Sign in and Create account, so both screens stay identical.
abstract final class AuthStyles {
  /// Electric-blue focus outline and cursor for the auth forms.
  static ThemeData fields(BuildContext context) => Theme.of(context).copyWith(
    inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.primary),
  );

  /// The tall main button (Sign in, Create account). It keeps its colour while busy.
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    minimumSize: const Size.fromHeight(54),
    backgroundColor: AppColors.primaryDark,
    foregroundColor: AppColors.onBrand,
    disabledBackgroundColor: AppColors.primaryDark,
    disabledForegroundColor: AppColors.onBrand,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.controlRadius)),
    textStyle: const TextStyle(
      fontFamily: AppTypography.family,
      fontSize: AppTypography.subtitle,
      fontWeight: FontWeight.w800,
    ),
  );
}
