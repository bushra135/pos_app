import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../cashier/cashier_home_screen.dart';
import '../owner/owner_home_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Selects the screen from the Firebase session, verification, and Firestore role.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Stream<Map<String, dynamic>?> _profile(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.data());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryDark),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        final user = snapshot.data!;

        if (!user.emailVerified) {
          return const VerifyEmailScreen();
        }

        // Load the user profile before choosing the owner or cashier screen.
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _profile(user.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryDark,
                  ),
                ),
              );
            }

            if (userSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to check account access. Check your connection and sign in again.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (!userSnapshot.hasData) {
              return const LoginScreen();
            }

            final userData = userSnapshot.data!;
            final String role = (userData['role'] ?? '').toString();

            final blocked =
                userData['isActive'] == false ||
                ['disabled', 'pending'].contains(userData['status']) ||
                (role != 'owner' && role != 'cashier') ||
                (role == 'cashier' && userData['isActive'] != true);
            if (blocked) {
              return Scaffold(
                appBar: AppBar(title: const Text('Account access')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This account needs store owner approval or has been disabled. Contact your store owner.',
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            if (role == 'owner') {
              return const OwnerHomeScreen();
            }

            return const CashierHomeScreen();
          },
        );
      },
    );
  }
}
