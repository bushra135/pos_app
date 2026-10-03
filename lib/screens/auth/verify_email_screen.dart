import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import 'auth_wrapper.dart';
import 'create_account_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.draftFullName = '',
    this.draftEmail = '',
    this.draftPassword = '',
    this.draftConfirmPassword = '',
    this.draftStoreName = '',
    this.draftStoreCode = '',
    this.draftIsOwner = true,
  });

  // Keep the registration draft when the user chooses a different account.
  final String draftFullName;
  final String draftEmail;
  final String draftPassword;
  final String draftConfirmPassword;
  final String draftStoreName;
  final String draftStoreCode;
  final bool draftIsOwner;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isChecking = false;
  bool _isResending = false;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      // Verification happens outside the app, so reload the user's status.
      await user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (refreshedUser?.emailVerified ?? false) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
        return;
      }

      _showMessage('Your email has not been verified yet.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Could not check verification.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() => _isResending = true);

    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _showMessage('Verification link sent to your email.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Could not resend the link.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(
          initialFullName: widget.draftFullName,
          initialEmail: widget.draftEmail,
          initialPassword: widget.draftPassword,
          initialConfirmPassword: widget.draftConfirmPassword,
          initialStoreName: widget.draftStoreName,
          initialStoreCode: widget.draftStoreCode,
          initialIsOwner: widget.draftIsOwner,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      color: AppColors.soft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_outlined,
                      color: AppColors.primaryDark,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Verify your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: AppTypography.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We sent a verification link to',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTypography.label,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Open the link in your inbox, then return here to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.controlRadius,
                        ),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isChecking ? null : _checkVerification,
                        icon: _isChecking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onBrand,
                                ),
                              )
                            : const Icon(Icons.verified_outlined),
                        label: Text(
                          _isChecking ? 'Checking...' : 'I verified my email',
                          style: const TextStyle(
                            fontSize: AppTypography.button,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _isResending ? null : _resendVerification,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                    ),
                    child: _isResending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryDark,
                            ),
                          )
                        : const Text(
                            'Resend verification link',
                            style: TextStyle(
                              fontSize: AppTypography.button,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text(
                      'Use a different account',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: AppTypography.button,
                        fontWeight: FontWeight.w600,
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
