import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import 'auth_wrapper.dart';
import 'create_account_screen.dart';
import '../../app/app_language.dart';
import '../../app/app_typography.dart';

/// Sends verification links and reloads the user after the emailed link is opened.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    this.draftFullName = '',
    this.draftEmail = '',
    this.draftStoreName = '',
    this.draftStoreCode = '',
    this.draftIsOwner = true,
  });
  final String draftFullName, draftEmail, draftStoreName, draftStoreCode;
  final bool draftIsOwner;
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

/// Sends the verification link (with a 60 s cooldown) and checks when it is confirmed.
class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  bool _busy = false;
  int _cooldown = 0;
  String? _error;
  String _notice = 'Send a verification link to your email to activate your ShopPad account.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Show recovery instructions instead of raw SDK exception details.
  String _verificationError(Object error) {
    if (error is TimeoutException) {
      return 'The connection timed out. Check your internet and try again.';
    }
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'too-many-requests' => 'Too many requests. Please wait a few minutes before trying again.',
        'network-request-failed' => 'Check your internet connection and try again.',
        'user-token-expired' ||
        'invalid-user-token' ||
        'user-disabled' => 'Please use a different account and sign in again.',
        _ => 'Unable to verify your email right now. Please try again.',
      };
    }
    if (error is StateError) return error.message.toString();
    return 'Unable to verify your email right now. Please try again.';
  }

  /// Sends the verification email, then starts the resend cooldown.
  Future<void> _send() async {
    if (_busy || _cooldown > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in again to verify your email.');
      await FirebaseAuth.instance.setLanguageCode('en');
      await user.sendEmailVerification().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _cooldown = 60;
        _notice =
            'Verification email sent. Open the link in your inbox, then return here and tap I have verified my email. Check spam if needed.';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _cooldown <= 1) {
          timer.cancel();
          if (mounted) setState(() => _cooldown = 0);
        } else {
          setState(() => _cooldown--);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _verificationError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reloads the user; once the email is verified, AuthWrapper opens the right home.
  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in again to verify your email.');
      await user.reload().timeout(const Duration(seconds: 20));
      if (FirebaseAuth.instance.currentUser?.emailVerified != true) {
        throw StateError(
          'Your email is not verified yet. Open the link in your email, then try again.',
        );
      }
      await FirebaseAuth.instance.currentUser!
          .getIdToken(true)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthWrapper()), (_) => false);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _verificationError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Signs out and returns to Create account with the earlier values filled in.
  Future<void> _differentAccount() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(
          initialFullName: widget.draftFullName,
          initialEmail: widget.draftEmail,
          initialStoreName: widget.draftStoreName,
          initialStoreCode: widget.draftStoreCode,
          initialIsOwner: widget.draftIsOwner,
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mark_email_read_outlined,
                          size: 40,
                          color: AppColors.onBrand,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'ShopPad'.tr,
                        style: TextStyle(
                          fontSize: AppTypography.display,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verify your email'.tr,
                        style: TextStyle(
                          fontSize: AppTypography.metric,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        FirebaseAuth.instance.currentUser?.email ?? '',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _notice,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _verify,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text('I have verified my email'.tr),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || _cooldown > 0 ? null : _send,
                        child: Text(
                          _cooldown > 0
                              ? 'Resend in {n}s'.trArgs({'n': _cooldown})
                              : 'Resend verification email'.tr,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _differentAccount,
                        child: Text('Use a different account'.tr),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
