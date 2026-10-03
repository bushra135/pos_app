import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import 'verify_email_screen.dart';

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
  final TextEditingController _confirmPasswordController =
      TextEditingController();
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
    final milliseconds = DateTime.now().millisecondsSinceEpoch.toString();
    return 'SHOP${milliseconds.substring(milliseconds.length - 6)}';
  }

  bool _hasMinimumLength(String password) => password.length >= 8;
  bool _hasUppercase(String password) => RegExp(r'[A-Z]').hasMatch(password);
  bool _hasLowercase(String password) => RegExp(r'[a-z]').hasMatch(password);
  bool _hasNumber(String password) => RegExp(r'[0-9]').hasMatch(password);
  bool _hasSpecialCharacter(String password) =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(password);

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendVerificationAndContinue(User user) async {
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException {
      // The account already exists; the verification screen can retry sending.
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => VerifyEmailScreen(
          draftFullName: _fullNameController.text,
          draftEmail: _emailController.text,
          draftPassword: _passwordController.text,
          draftConfirmPassword: _confirmPasswordController.text,
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
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
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

    try {
      // Verify the store exists before creating a cashier account.
      DocumentSnapshot<Map<String, dynamic>>? storeDoc;
      if (!_isOwner) {
        storeDoc = await _firestore.collection('stores').doc(storeCode).get();

        if (!storeDoc.exists) {
          _showMessage('Invalid store code');
          return;
        }
      }

      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      final String uid = userCredential.user!.uid;

      if (_isOwner) {
        final String newStoreCode = _generateStoreCode();

        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'fullName': fullName,
          'email': email,
          'role': 'owner',
          'storeName': storeName,
          'storeCode': newStoreCode,
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _firestore.collection('stores').doc(newStoreCode).set({
          'storeCode': newStoreCode,
          'storeName': storeName,
          'ownerUid': uid,
          'ownerEmail': email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // The cashier profile uses the auth uid and links to the store by code.
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'fullName': fullName,
          'email': email,
          'role': 'cashier',
          'storeCode': storeCode,
          'storeName': storeDoc!.data()?['storeName'] ?? '',
          'ownerUid': storeDoc.data()?['ownerUid'] ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _sendVerificationAndContinue(userCredential.user!);
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
      _showMessage('Something went wrong: $e');
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
      prefixIcon: Icon(icon, color: AppColors.primaryDark),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
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
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 17,
            color: color,
          ),
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
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use a strong password',
            style: TextStyle(
              fontSize: AppTypography.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
          _passwordRequirement(
            'At least 8 characters',
            _hasMinimumLength(password),
          ),
          _passwordRequirement('One uppercase letter', _hasUppercase(password)),
          _passwordRequirement('One lowercase letter', _hasLowercase(password)),
          _passwordRequirement('One number', _hasNumber(password)),
          _passwordRequirement(
            'One special character',
            _hasSpecialCharacter(password),
          ),
        ],
      ),
    );
  }

  Widget _roleOption({required bool owner}) {
    final selected = _isOwner == owner;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isOwner = owner),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? null : AppColors.background,
            gradient: selected ? AppColors.brandGradient : null,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          alignment: Alignment.center,
          child: Text(
            owner ? 'Owner' : 'Cashier',
            style: TextStyle(
              color: selected ? AppColors.onBrand : AppColors.text,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: AppTypography.label,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'I am a...',
                    style: TextStyle(
                      fontSize: AppTypography.section,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      _roleOption(owner: true),
                      const SizedBox(width: 10),
                      _roleOption(owner: false),
                    ],
                  ),

                  const SizedBox(height: 30),

                  _fieldLabel('Full Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fullNameController,
                    decoration: _inputDecoration(
                      hintText: 'Enter your full name',
                      icon: Icons.person_outline,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _fieldLabel('Email'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    decoration: _inputDecoration(
                      hintText: 'Enter your email',
                      icon: Icons.email_outlined,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _fieldLabel('Password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    onChanged: (_) {
                      setState(() {
                        _hasStartedPassword = true;
                      });
                    },
                    decoration: _inputDecoration(
                      hintText: 'Create a password',
                      icon: Icons.lock_outline,
                      errorText:
                          _hasAttemptedSubmit &&
                              !_isStrongPassword(_passwordController.text)
                          ? 'Please meet all password requirements.'
                          : null,
                      suffixIcon: IconButton(
                        color: AppColors.primaryDark,
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  if (_hasStartedPassword)
                    _passwordRequirements(_passwordController.text),

                  const SizedBox(height: 20),

                  _fieldLabel('Confirm Password'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmPasswordVisible,
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      hintText: 'Confirm your password',
                      icon: Icons.lock_outline,
                      errorText:
                          _hasAttemptedSubmit &&
                              _confirmPasswordController.text.isNotEmpty &&
                              _confirmPasswordController.text !=
                                  _passwordController.text
                          ? 'Passwords do not match.'
                          : null,
                      suffixIcon: IconButton(
                        color: AppColors.primaryDark,
                        onPressed: () {
                          setState(() {
                            _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible;
                          });
                        },
                        icon: Icon(
                          _isConfirmPasswordVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_isOwner) ...[
                    _fieldLabel('Store Name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _storeNameController,
                      decoration: _inputDecoration(
                        hintText: 'Enter your store name',
                        icon: Icons.store_outlined,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "You'll create a new store and receive a store code",
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.muted,
                      ),
                    ),
                  ] else ...[
                    _fieldLabel('Store Code'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _storeCodeController,
                      decoration: _inputDecoration(
                        hintText: 'Enter store code',
                        icon: Icons.numbers,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Ask your store owner for the store code",
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.muted,
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  GestureDetector(
                    onTap: _isLoading ? null : _handleCreateAccount,
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.controlRadius,
                        ),
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: AppColors.onBrand,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Create Account',
                                style: TextStyle(
                                  color: AppColors.onBrand,
                                  fontSize: AppTypography.button,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: const Text.rich(
                        TextSpan(
                          text: "Already have an account? ",
                          children: [
                            TextSpan(
                              text: "Sign in",
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: AppTypography.button,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(fontSize: AppTypography.body),
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
