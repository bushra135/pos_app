import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../widgets/auth_motion.dart';
import '../../widgets/motion.dart';
import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import 'verify_email_screen.dart';
import '../../app/app_language.dart';

/// Creates an owner/store or a cashier awaiting approval; passwords belong to Firebase Auth.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    this.initialFullName = '',
    this.initialEmail = '',
    this.initialPassword = '',
    this.initialConfirmPassword = '',
    this.initialStoreName = '',
    this.initialStoreCode = '',
    this.initialIsOwner = true,
  });

  final String initialFullName;
  final String initialEmail;
  final String initialPassword;
  final String initialConfirmPassword;
  final String initialStoreName;
  final String initialStoreCode;
  final bool initialIsOwner;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late bool _isOwner;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _hasStartedPassword = false;
  bool _hasAttemptedSubmit = false;

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();
  final TextEditingController _storeCodeController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Restore the registration draft when returning from verification.
    _isOwner = widget.initialIsOwner;
    _fullNameController.text = widget.initialFullName;
    _emailController.text = widget.initialEmail;
    _passwordController.text = widget.initialPassword;
    _confirmPasswordController.text = widget.initialConfirmPassword;
    _storeNameController.text = widget.initialStoreName;
    _storeCodeController.text = widget.initialStoreCode;
    _hasStartedPassword = widget.initialPassword.isNotEmpty;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _storeNameController.dispose();
    _storeCodeController.dispose();
    super.dispose();
  }

  // The store code is the stores document ID used by cashiers to join.
  String _generateStoreCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return 'SHOP${List.generate(12, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }

  bool _hasMinimumLength(String password) => password.length >= 12;
  bool _hasUppercase(String password) => RegExp(r'[A-Z]').hasMatch(password);
  bool _hasLowercase(String password) => RegExp(r'[a-z]').hasMatch(password);
  bool _hasNumber(String password) => RegExp(r'[0-9]').hasMatch(password);
  bool _hasSpecialCharacter(String password) => RegExp(r'[^A-Za-z0-9]').hasMatch(password);

  // Validation uses the same requirements shown below the password field.
  bool _isStrongPassword(String password) {
    return _hasMinimumLength(password) &&
        _hasUppercase(password) &&
        _hasLowercase(password) &&
        _hasNumber(password) &&
        _hasSpecialCharacter(password);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.tr)));
  }

  Future<void> _sendVerificationAndContinue(User user) async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => VerifyEmailScreen(
          draftFullName: _fullNameController.text,
          draftEmail: _emailController.text,
          draftStoreName: _storeNameController.text,
          draftStoreCode: _storeCodeController.text,
          draftIsOwner: _isOwner,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _handleCreateAccount() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final storeName = _storeNameController.text.trim();
    final storeCode = _storeCodeController.text.trim().toUpperCase();

    if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in all required fields');
      return;
    }

    if (!_isStrongPassword(password)) {
      setState(() {
        _hasStartedPassword = true;
        _hasAttemptedSubmit = true;
      });
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Passwords do not match');
      return;
    }

    if (_isOwner && storeName.isEmpty) {
      _showMessage('Please enter your store name');
      return;
    }

    if (!_isOwner && storeCode.isEmpty) {
      _showMessage('Please enter store code');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    User? createdUser;
    var profileSaved = false;
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      createdUser = userCredential.user;
      final String uid = createdUser!.uid;

      if (_isOwner) {
        final String newStoreCode = _generateStoreCode();

        final batch = _firestore.batch();
        batch.set(_firestore.collection('users').doc(uid), {
          'uid': uid,
          'fullName': fullName,
          'email': email,
          'role': 'owner',
          'storeName': storeName,
          'storeCode': newStoreCode,
          'createdAt': FieldValue.serverTimestamp(),
        });

        batch.set(_firestore.collection('stores').doc(newStoreCode), {
          'storeCode': newStoreCode,
          'storeName': storeName,
          'ownerUid': uid,
          'ownerEmail': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } else {
        // The cashier profile uses the auth uid and links to the store by code.
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'fullName': fullName,
          'email': email,
          'role': 'cashier',
          'storeCode': storeCode,
          'storeName': '',
          'isActive': false,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      profileSaved = true;
      await _sendVerificationAndContinue(createdUser);
    } on FirebaseAuthException catch (e) {
      String message = 'Account creation failed';

      if (e.code == 'email-already-in-use') {
        message = 'This email is already in use';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      }

      _showMessage(message);
    } catch (e) {
      if (!profileSaved && createdUser != null) {
        // Do not leave an unusable Auth account after a rejected profile write.
        try {
          await createdUser.delete();
        } catch (_) {
          /* Retry through sign-in if cleanup is unavailable. */
        }
      }
      _showMessage('Could not create the store account. Check the store code and try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppColors.muted),
      suffixIcon: suffixIcon,
      errorText: errorText,
      errorMaxLines: 2,
    );
  }

  Widget _passwordRequirement(String label, bool isMet) {
    final color = isMet ? AppColors.primaryDark : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(isMet ? Icons.check_circle : Icons.radio_button_unchecked, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: AppTypography.caption, color: color),
          ),
        ],
      ),
    );
  }

  Widget _passwordRequirements(String password) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use a strong password'.tr,
            style: TextStyle(fontSize: AppTypography.caption, fontWeight: FontWeight.w600),
          ),
          _passwordRequirement('At least 12 characters', _hasMinimumLength(password)),
          _passwordRequirement('One uppercase letter', _hasUppercase(password)),
          _passwordRequirement('One lowercase letter', _hasLowercase(password)),
          _passwordRequirement('One number', _hasNumber(password)),
          _passwordRequirement('One special character', _hasSpecialCharacter(password)),
        ],
      ),
    );
  }

  Widget _roleOption({required bool owner}) {
    final selected = _isOwner == owner;
    return Expanded(
      child: Material(
        color: selected ? AppColors.primaryDark : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        child: InkWell(
          onTap: () => setState(() => _isOwner = owner),
          borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  owner ? Icons.storefront_outlined : Icons.point_of_sale_outlined,
                  size: 18,
                  color: selected ? AppColors.onBrand : AppColors.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  owner ? 'Owner' : 'Cashier',
                  style: TextStyle(
                    color: selected ? AppColors.onBrand : AppColors.text,
                    fontSize: AppTypography.label,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // One field layout keeps labels, spacing and decoration consistent.
  Widget _accountField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    ValueChanged<String>? onChanged,
    String? errorText,
    Widget? suffixIcon,
  }) => GlowField(
    label: label.tr,
    child: TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: _inputDecoration(
        hintText: hint.tr,
        icon: icon,
        errorText: errorText,
        suffixIcon: suffixIcon,
      ),
    ),
  );

  Widget _passwordToggle(bool visible, VoidCallback toggle) =>
      PasswordEye(visible: visible, onPressed: toggle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Theme(
          // Same roles as sign-in: indigo brand, ink focus and secondary actions.
          data: Theme.of(context).copyWith(
            inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
              ),
            ),
            textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.primary),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeSlideIn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IconButton(
                          tooltip: 'Back to sign in'.tr,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Create your account'.tr,
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
                      Center(
                        child: Text(
                          'Set up your store or join one as a cashier.'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.muted, fontSize: AppTypography.button),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'I am a...'.tr,
                        style: TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            _roleOption(owner: true),
                            const SizedBox(width: 4),
                            _roleOption(owner: false),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      _accountField(
                        label: 'Full name'.tr,
                        controller: _fullNameController,
                        hint: 'Enter your full name',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 20),
                      _accountField(
                        label: 'Email'.tr,
                        controller: _emailController,
                        hint: 'Enter your email',
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 20),
                      _accountField(
                        label: 'Password'.tr,
                        controller: _passwordController,
                        hint: 'Create a password',
                        icon: Icons.lock_outline,
                        obscureText: !_isPasswordVisible,
                        onChanged: (_) => setState(() => _hasStartedPassword = true),
                        errorText:
                            _hasAttemptedSubmit && !_isStrongPassword(_passwordController.text)
                            ? 'Please meet all password requirements.'
                            : null,
                        suffixIcon: _passwordToggle(
                          _isPasswordVisible,
                          () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      if (_hasStartedPassword) _passwordRequirements(_passwordController.text),
                      const SizedBox(height: 20),
                      _accountField(
                        label: 'Confirm password'.tr,
                        controller: _confirmPasswordController,
                        hint: 'Confirm your password',
                        icon: Icons.lock_outline,
                        obscureText: !_isConfirmPasswordVisible,
                        onChanged: (_) => setState(() {}),
                        errorText:
                            _hasAttemptedSubmit &&
                                _confirmPasswordController.text.isNotEmpty &&
                                _confirmPasswordController.text != _passwordController.text
                            ? 'Passwords do not match.'
                            : null,
                        suffixIcon: _passwordToggle(
                          _isConfirmPasswordVisible,
                          () => setState(
                            () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _accountField(
                        label: _isOwner ? 'Store name' : 'Store code',
                        controller: _isOwner ? _storeNameController : _storeCodeController,
                        hint: _isOwner ? 'Enter your store name' : 'Enter store code',
                        icon: _isOwner ? Icons.store_outlined : Icons.numbers,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isOwner
                            ? "You'll create a new store and receive a store code"
                            : 'Ask your store owner for the store code',
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.muted,
                        ),
                      ),

                      const SizedBox(height: 30),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleCreateAccount,
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
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: AppColors.onBrand,
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Text('Create account'.tr),
                      ),

                      const SizedBox(height: 20),

                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Text.rich(
                            TextSpan(
                              text: "Already have an account? ".tr,
                              children: [
                                TextSpan(
                                  text: "Sign in".tr,
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: AppTypography.button,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: AppTypography.body, color: AppColors.muted),
                          ),
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
    );
  }
}
