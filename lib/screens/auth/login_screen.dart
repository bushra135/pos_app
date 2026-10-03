import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import 'create_account_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _showPassword = false;
  bool _loading = false;
  late final AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _signIn() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || _password.text.isEmpty) {
      _message('Enter your email and password.');
      return;
    }
    setState(() => _loading = true);
    try {
      // AuthWrapper handles navigation when the Firebase auth state changes.
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'user-not-found' => 'No account exists with this email.',
        'wrong-password' ||
        'invalid-credential' => 'Your email or password is incorrect.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => error.message ?? 'Unable to sign in right now.',
      };
      _message(message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) {
      _message('Enter your email first, then choose Forgot password.');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://shoppad-f3d43.firebaseapp.com',
          handleCodeInApp: false,
        ),
      );
      _message('A password reset link was sent to your email.');
    } on FirebaseAuthException catch (error) {
      _message(error.message ?? 'Could not send the reset email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: _animatedHeader(height: wide ? 270 : 230),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    wide ? 40 : 25,
                    AppSpacing.page,
                    28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        constraints.maxHeight - (wide ? 68 : 53),
                      ),
                    ),
                    // Keep the brand inside the colored header on tall screens.
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          children: [
                            _brand(),
                            SizedBox(height: wide ? 36 : 30),
                            _card(),
                            const SizedBox(height: 20),
                            const Text(
                              'Secure access for your store team',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _animatedHeader({required double height}) {
    return AnimatedBuilder(
      animation: _backgroundController,
      builder: (context, child) {
        final progress = _backgroundController.value;
        return Container(
          height: height,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(44),
              bottomRight: Radius.circular(44),
            ),
          ),
          child: CustomPaint(
            painter: _HeaderSheenPainter(progress),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  Widget _brand() => Column(
    children: [
      Container(
        width: 100,
        height: 100,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Image.asset('assets/logo.png'),
      ),
      const SizedBox(height: 13),
      const Text(
        'ShopPad',
        style: TextStyle(
          color: AppColors.onBrand,
          fontSize: AppTypography.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        'Smart tools for your store',
        style: TextStyle(
          color: AppColors.onBrand,
          fontSize: AppTypography.body,
        ),
      ),
    ],
  );

  Widget _card() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.text.withValues(alpha: 0.10),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to continue to your workspace.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: AppTypography.body,
            ),
          ),
          const SizedBox(height: 27),
          const Text(
            'Email address',
            style: TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: _input(
              'you@example.com',
              Icons.alternate_email_rounded,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Password',
            style: TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _loading ? null : _signIn(),
            decoration: _input(
              'Enter your password',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                color: AppColors.primaryDark,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontSize: AppTypography.button,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 53,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _loading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  foregroundColor: AppColors.onBrand,
                  disabledForegroundColor: AppColors.onBrand,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.controlRadius,
                    ),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.onBrand,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: AppTypography.button,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 23),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'NEW TO SHOPPAD?',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateAccountScreen()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.primaryDark),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
              ),
            ),
            child: const Text(
              'Create account',
              style: TextStyle(
                fontSize: AppTypography.button,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  InputDecoration _input(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.primaryDark),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(color: AppColors.primaryDark, width: 1.6),
      );

  OutlineInputBorder _border({
    Color color = AppColors.border,
    double width = 1,
  }) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _HeaderSheenPainter extends CustomPainter {
  const _HeaderSheenPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress * math.pi * 2;
    final center = Offset(size.width * 0.82, size.height * 0.48);
    final rx = size.width * 0.53;
    final ry = size.height * 0.47;

    // Draw the glow first so the animated rings appear above it.
    final glowRect = Rect.fromCircle(center: center, radius: rx * 0.92);
    canvas.drawCircle(
      center,
      rx * 0.92,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.20),
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.primary.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(glowRect),
    );

    for (var ring = 0; ring < 3; ring++) {
      final tilt = (ring - 1) * 0.62;
      final oval = Rect.fromCenter(
        center: Offset.zero,
        width: rx * 2,
        height: ry * (1.05 + ring * 0.12) * 2,
      );
      final rotation = tilt + 0.08 * math.sin(phase * 0.5 + ring);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring == 1 ? 1.1 : 0.8
          ..color = Colors.white.withValues(alpha: ring == 1 ? 0.25 : 0.13),
      );

      final start = phase * (ring.isEven ? 1 : -1) + ring * 2.08;
      final sweep = ring == 1 ? math.pi * 0.62 : math.pi * 0.42;
      final trail = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ring == 1 ? 4.2 : 2.8
        ..shader = LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0),
            AppColors.accent.withValues(alpha: 0.47),
            AppColors.soft,
            AppColors.soft,
            AppColors.primary.withValues(alpha: 0),
          ],
          stops: const [0, 0.24, 0.48, 0.68, 1],
        ).createShader(oval);
      canvas.drawArc(
        oval,
        start,
        sweep,
        false,
        trail..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      trail.maskFilter = null;
      canvas.drawArc(oval, start, sweep, false, trail);

      final angle = start + sweep * 0.72;
      final position = Offset(
        rx * math.cos(angle),
        oval.height * 0.5 * math.sin(angle),
      );
      canvas.drawCircle(
        position,
        ring == 1 ? 4.3 : 3,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.84)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        position,
        ring == 1 ? 2.2 : 1.5,
        Paint()..color = AppColors.accentSoft,
      );
      canvas.restore();
    }

    // Reuse the animation progress for the light sweep without another timer.
    final sweepX = size.width * (-0.4 + progress * 1.8);
    canvas.save();
    canvas.translate(sweepX, size.height * 0.5);
    canvas.rotate(-0.32);
    final streak = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.14,
      height: size.height * 2.3,
    );
    canvas.drawRect(
      streak,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(streak),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeaderSheenPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
