import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../cashier/cashier_home_screen.dart';
import '../owner/owner_home_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';
import '../../app/app_language.dart';
import '../../services/profile_edits.dart';
import '../../widgets/welcome_overlay.dart';

/// Selects the screen from the Firebase session, verification, and Firestore role.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Stream<Map<String, dynamic>?> _profile(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data != null) unawaited(_syncConfirmedEmail(uid, data));
      return data;
    });
  }

  /// After the user opens the email-change link, the signed-in email differs from the
  /// profile; copy it so the owner's cashier list shows the new address. Best effort.
  Future<void> _syncConfirmedEmail(String uid, Map<String, dynamic> profile) async {
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    if ((authEmail ?? '').toLowerCase() == (profile['email'] ?? '').toString().toLowerCase()) {
      return;
    }
    try {
      await ProfileEdits.syncEmail(
        FirebaseFirestore.instance,
        uid: uid,
        profileEmail: (profile['email'] ?? '').toString(),
        authEmail: authEmail,
      );
    } catch (e) {
      debugPrint('Email sync skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.primaryDark)),
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
                body: Center(child: CircularProgressIndicator(color: AppColors.primaryDark)),
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
                        Text(
                          'Unable to check account access. Check your connection and sign in again.'
                              .tr,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: Text('Sign out'.tr),
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
                appBar: AppBar(title: Text('Account access'.tr)),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'This account needs store owner approval or has been disabled. Contact your store owner.'
                              .tr,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: Text('Sign out'.tr),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // A short welcome after signing in, then the home screen beneath it.
            return WelcomeGate(
              uid: user.uid,
              name: (userData['fullName'] ?? '').toString(),
              storeName: (userData['storeName'] ?? '').toString(),
              isOwner: role == 'owner',
              child: role == 'owner' ? const OwnerHomeScreen() : const CashierHomeScreen(),
            );
          },
        );
      },
    );
  }
}
