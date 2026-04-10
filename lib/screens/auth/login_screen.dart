import 'package:flutter/material.dart';

// Import destination screens
import '../owner/owner_home_screen.dart';
import '../cashier/cashier_home_screen.dart';
import 'create_account_screen.dart';

// Login screen widget
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// State class for LoginScreen
class _LoginScreenState extends State<LoginScreen> {
  // Controller for email input
  final TextEditingController emailController =
      TextEditingController(text: 'owner@shop.com');

  // Controller for password input
  final TextEditingController passwordController =
      TextEditingController(text: '12345678');

  // Controls password visibility
  bool obscurePassword = true;

  @override
  void dispose() {
    // Dispose controllers to free memory
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // Temporary sign-in logic
  // Later, this should be replaced with Firebase/Auth database logic
  void signIn() {
    final email = emailController.text.trim().toLowerCase();

    if (email == 'owner@shop.com') {
      // Navigate to owner home screen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OwnerHomeScreen()),
      );
    } else {
      // Navigate to cashier home screen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CashierHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Full-screen gradient around the white card
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF08C08C),
              Color(0xFF0A84FF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Top header section with gradient background
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                    top: 36,
                    bottom: 110,
                    left: 24,
                    right: 24,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF08C08C),
                        Color(0xFF0A84FF),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    children: [
                      SizedBox(height: 10),
                      Text(
                        'Welcome Back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Sign in to continue',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Main white card
                Transform.translate(
                  offset: const Offset(0, -72),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 22),
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF102A43).withOpacity(0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email label
                        const Text(
                          'Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF263247),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Email field
                        TextField(
                          controller: emailController,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF263247),
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.mail_outline_rounded,
                              color: Color(0xFF98A2B3),
                              size: 24,
                            ),
                            hintText: 'Enter your email',
                            hintStyle: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 15,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFF08C08C),
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // Password label
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF263247),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Password field
                        TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF263247),
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFF98A2B3),
                              size: 24,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  obscurePassword = !obscurePassword;
                                });
                              },
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: const Color(0xFF98A2B3),
                              ),
                            ),
                            hintText: 'Enter your password',
                            hintStyle: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 15,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(
                                color: Color(0xFF08C08C),
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 55),

                        // Sign in button
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            onPressed: signIn,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFF08C08C),
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Forgot password text
                        Center(
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: Color(0xFF7B8794),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(text: 'Forgot password? '),
                                TextSpan(
                                  text: 'Reset here',
                                  style: TextStyle(
                                    color: Color(0xFF08C08C),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // Divider with OR text
                        Row(
                          children: const [
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE4E7EC),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE4E7EC),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 25),

                        // Create account button
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateAccountScreen(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF08C08C),
                              side: const BorderSide(
                                color: Color(0xFF08C08C),
                                width: 1.7,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Create Account',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }
}