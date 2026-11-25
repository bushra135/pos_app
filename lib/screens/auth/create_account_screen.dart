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

/// Strong ease-out for entrances and state changes (Emil Kowalski's UI curve).
const _easeOut = Cubic(0.23, 1, 0.32, 1);

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
            label.tr,
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

  // A role tile: icon, name and what it does. The chosen one gets the brand
  // border, an ice fill and a check that pops in.
  Widget _roleOption({required bool owner}) {
    final selected = _isOwner == owner;
    final reduced = Motion.reduced(context);
    final duration = reduced ? Duration.zero : const Duration(milliseconds: 200);
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: PressableScale(
          child: AnimatedContainer(
            duration: duration,
            curve: _easeOut,
            decoration: BoxDecoration(
              color: selected ? AppColors.ice : AppColors.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(() => _isOwner = owner),
                borderRadius: radius,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, selected ? 13 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: duration,
                            curve: _easeOut,
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: selected ? AppColors.primary : AppColors.soft,
                              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                            ),
                            child: Icon(
                              owner ? Icons.storefront_outlined : Icons.point_of_sale_outlined,
                              size: 20,
                              color: selected ? AppColors.onBrand : AppColors.navy,
                            ),
                          ),
                          const Spacer(),
                          AnimatedScale(
                            scale: selected ? 1 : 0.6,
                            duration: duration,
                            curve: _easeOut,
                            child: AnimatedOpacity(
                              opacity: selected ? 1 : 0,
                              duration: duration,
                              child: const Icon(
                                Icons.check_circle_rounded,
                                size: 20,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (owner ? 'Owner' : 'Cashier').tr,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: AppTypography.subtitle,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (owner ? 'Set up a new store' : 'Join with a store code').tr,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: AppTypography.caption,
                          height: 1.35,
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

  // The grey header: back, then a start-aligned title. The short scan line under
  // the title draws in once, echoing the scanner frame on sign-in.
  Widget _header() => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.hero,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
    ),
    child: SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 468),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 24, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back to sign in'.tr,
                  onPressed: () => Navigator.pop(context),
                  icon: const BackButtonIcon(),
                  color: AppColors.navy,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: FadeSlideIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create your account'.tr,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: AppTypography.display,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const _ScanRule(),
                        const SizedBox(height: 10),
                        Text(
                          'Set up your store or join one as a cashier.'.tr,
                          style: TextStyle(
                            color: AppColors.onHeroMuted,
                            fontSize: AppTypography.button,
                          ),
                        ),
                      ],
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
      body: Theme(
        // Same roles as sign-in: electric blue brand and focus.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: FadeSlideIn(
                        index: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'I am a...'.tr,
                              style: TextStyle(
                                fontSize: AppTypography.body,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _roleOption(owner: true),
                                  const SizedBox(width: 12),
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
                                  _hasAttemptedSubmit &&
                                      !_isStrongPassword(_passwordController.text)
                                  ? 'Please meet all password requirements.'.tr
                                  : null,
                              suffixIcon: _passwordToggle(
                                _isPasswordVisible,
                                () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                              ),
                            ),
                            if (_hasStartedPassword)
                              _passwordRequirements(_passwordController.text),
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
                                  ? 'Passwords do not match.'.tr
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
                              (_isOwner
                                      ? "You'll create a new store and receive a store code"
                                      : 'Ask your store owner for the store code')
                                  .tr,
                              style: const TextStyle(
                                fontSize: AppTypography.caption,
                                color: AppColors.muted,
                              ),
                            ),

                            const SizedBox(height: 30),

                            PressableScale(
                              enabled: !_isLoading,
                              child: ElevatedButton(
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
                                  style: TextStyle(
                                    fontSize: AppTypography.body,
                                    color: AppColors.muted,
                                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// A short electric-blue line under the title that draws in from the start edge
/// once (the scan line). Shown complete with reduced motion.
class _ScanRule extends StatelessWidget {
  const _ScanRule();

  @override
  Widget build(BuildContext context) {
    const line = SizedBox(
      width: 44,
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
    if (Motion.reduced(context)) return line;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: const Interval(0.3, 1, curve: _easeOut),
      builder: (context, t, child) => Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: ClipRect(
          child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: t, child: child),
        ),
      ),
      child: line,
    );
  }
}
