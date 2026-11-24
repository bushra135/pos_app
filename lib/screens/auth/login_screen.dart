import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
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

  @override
  void dispose() {
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
      await _auth.signInWithEmailAndPassword(email: email, password: _password.text);
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'user-not-found' => 'Your email or password is incorrect.',
        'wrong-password' || 'invalid-credential' => 'Your email or password is incorrect.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Unable to sign in right now. Please try again.',
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
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton.icon(
                            onPressed: AppLanguage.toggle,
                            style: TextButton.styleFrom(foregroundColor: AppColors.text),
                            icon: const Icon(Icons.translate_rounded, size: 18),
                            // Each language is written in itself so it can be found.
                            label: Text(AppLanguage.isArabic ? 'English' : 'العربية'),
                          ),
                        ),
                        _brand(),
                        const SizedBox(height: 32),
                        _form(),
                        const Spacer(),
                        const SizedBox(height: 32),
                        _createAccount(),
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
      // Large ink logo, centred, with no background tile.
      Image.asset(
        'assets/logo.png',
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        // Sign-in swaps the app's roles: indigo brand, ink for secondary actions.
        color: AppColors.primaryDark,
        colorBlendMode: BlendMode.srcIn,
        semanticLabel: 'ShopPad logo'.tr,
      ),
      const SizedBox(height: 16),
      Text(
        'Welcome back'.tr,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.text,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Sign in to your ShopPad workspace.'.tr,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted, fontSize: AppTypography.button),
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
          _label('Email address'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: InputDecoration(hintText: 'you@example.com'.tr),
          ),
          const SizedBox(height: 16),
          _label('Password'),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _loading ? null : _signIn(),
            decoration: InputDecoration(
              hintText: 'Enter your password'.tr,
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                color: AppColors.muted,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _resetPassword,
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: Text('Forgot password?'.tr),
            ),
          ),
          const SizedBox(height: 4),
          ElevatedButton(
            onPressed: _loading ? null : _signIn,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onBrand,
              disabledBackgroundColor: AppColors.primaryDark,
              disabledForegroundColor: AppColors.onBrand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(
                fontFamily: AppTypography.family,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: AppColors.onBrand, strokeWidth: 2.4),
                  )
                : Text('Sign in'.tr),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text('Create an account'.tr),
      ),
    ],
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: AppTypography.caption + 1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
