import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../cashier/cashier_home_screen.dart';
import '../owner/owner_home_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Selects the screen from the Firebase session, verification, and Firestore role.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
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

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              return const LoginScreen();
            }

            final userData = userSnapshot.data!.data();
            final String role = (userData?['role'] ?? '').toString();

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
