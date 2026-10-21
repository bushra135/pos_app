import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../services/sale_sync_service.dart';
import '../cashier/cashier_home_screen.dart';
import '../owner/owner_home_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Selects the screen from the Firebase session, verification, and Firestore role.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<Map<String, dynamic>?> _profile(String uid) async {
    final sync = SaleSyncService.maybeInstance;
    if (sync != null) {
      final context = await sync.loadContext(uid);
      return Map<String, dynamic>.from(context['profile'] as Map);
    }
    return (await FirebaseFirestore.instance.collection('users').doc(uid).get())
        .data();
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
        return FutureBuilder<Map<String, dynamic>?>(
          future: _profile(user.uid),
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
                    child: Text(
                      userSnapshot.error.toString(),
                      textAlign: TextAlign.center,
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
