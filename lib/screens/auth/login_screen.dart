import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../widgets/auth_motion.dart';
import '../../widgets/motion.dart';
import 'create_account_screen.dart';
import '../../app/app_language.dart';

/// Signs in through Firebase Auth; AuthWrapper decides which workspace is allowed.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _showPassword = false;
  bool _loading = false;

  /// Sign-in problems are shown under the form (translated), with a gentle shake.
  String? _error;
  int _errorCount = 0;

  void _showError(String text) {
    if (!mounted) return;
    setState(() {
      _error = text.tr;
      _errorCount++;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.tr)));
    }
  }

  Future<void> _signIn() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || _password.text.isEmpty) {
      _showError('Enter your email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // AuthWrapper handles navigation when the Firebase auth state changes.
      await _auth.signInWithEmailAndPassword(email: email, password: _password.text);
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'user-not-found' => 'Your email or password is incorrect.',
        'wrong-password' || 'invalid-credential' => 'Your email or password is incorrect.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Unable to sign in right now. Please try again.',
      };
      _showError(message);
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
      _message('If this account exists, a password reset link will be sent.');
    } on FirebaseAuthException catch (error) {
      _message(
        error.code == 'too-many-requests'
            ? 'Too many attempts. Try again later.'
            : 'If this account exists, a password reset link will be sent.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - 68)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeSlideIn(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              onPressed: AppLanguage.toggle,
                              style: TextButton.styleFrom(foregroundColor: AppColors.text),
                              icon: const Icon(Icons.translate_rounded, size: 18),
                              // Each language is written in itself so it can be found.
                              label: Text(AppLanguage.isArabic ? 'English' : 'العربية'),
                            ),
                          ),
                        ),
                        _brand(),
                        const SizedBox(height: 28),
                        _form(),
                        const Spacer(),
                        const SizedBox(height: 32),
                        FadeSlideIn(index: 6, child: _createAccount()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() => Column(
    children: [
      const BrandLogo(),
      const SizedBox(height: 8),
      FadeSlideIn(
        index: 1,
        child: Text(
          'Welcome back'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.text,
            fontSize: AppTypography.display,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ),
      const SizedBox(height: 4),
      FadeSlideIn(
        index: 2,
        child: Text(
          'Sign in to your ShopPad workspace.'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: AppTypography.button),
        ),
      ),
    ],
  );

  Widget _form() => Theme(
    // Focused fields use ink here, since indigo carries the brand on this screen.
    data: Theme.of(context).copyWith(
      inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.primary),
    ),
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShakeOnChange(
            trigger: _errorCount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(
                  index: 3,
                  child: GlowField(
                    label: 'Email address'.tr,
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                      onChanged: (_) => _error == null ? null : setState(() => _error = null),
                      decoration: InputDecoration(hintText: 'you@example.com'.tr),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  index: 4,
                  child: GlowField(
                    label: 'Password'.tr,
                    child: TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _loading ? null : _signIn(),
                      onChanged: (_) => _error == null ? null : setState(() => _error = null),
                      decoration: InputDecoration(
                        hintText: 'Enter your password'.tr,
                        suffixIcon: PasswordEye(
                          visible: _showPassword,
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          InlineErrorBanner(message: _error),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: Text('Forgot password?'.tr),
            ),
          ),
          const SizedBox(height: 4),
          FadeSlideIn(
            index: 5,
            child: PressableScale(
              enabled: !_loading,
              child: ElevatedButton(
                onPressed: _loading ? null : _signIn,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onBrand,
                  disabledBackgroundColor: AppColors.primaryDark,
                  disabledForegroundColor: AppColors.onBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppTypography.family,
                    fontSize: AppTypography.subtitle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // The button keeps its size while it changes to a progress state.
                child: AnimatedSwitcher(
                  duration: Motion.reduced(context) ? Duration.zero : Motion.fast,
                  child: _loading
                      ? Row(
                          key: const ValueKey('signing-in'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: AppColors.onBrand,
                                strokeWidth: 2.4,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('Signing in...'.tr),
                          ],
                        )
                      : Text('Sign in'.tr, key: const ValueKey('sign-in')),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _createAccount() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'New to ShopPad?'.tr,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: AppTypography.body),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAccountScreen())),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: Color(0xFFD9D9D2)),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          ),
        ),
        child: Text('Create an account'.tr),
      ),
    ],
  );
}
