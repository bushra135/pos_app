import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';

/// Shows user details and payment settings shared by store employees.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String name = '';
  String email = '';
  String role = '';
  String storeName = '';
  String storeCode = '';
  String benefitQrBase64 = '';

  bool isLoading = true;
  bool isSaving = false;

  bool isPaymentExpanded = true;

  final TextEditingController benefitNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    benefitNumberController.dispose();
    super.dispose();
  }

  // Only the store owner can edit payment settings in this screen.
  bool get isOwner => role.toLowerCase() == 'owner';

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userData = userDoc.data()!;

      final String fetchedStoreCode = userData['storeCode'] ?? '';
      String fetchedStoreName = userData['storeName'] ?? '';
      String fetchedBenefitNumber = '';
      String fetchedBenefitQrBase64 = '';

      if (fetchedStoreCode.isNotEmpty) {
        final storeDoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(fetchedStoreCode)
            .get();

        if (storeDoc.exists) {
          final storeData = storeDoc.data()!;
          fetchedStoreName = storeData['storeName'] ?? fetchedStoreName;
          fetchedBenefitNumber = storeData['benefitNumber'] ?? '';
          fetchedBenefitQrBase64 = storeData['benefitQrBase64'] ?? '';
        }
      }

      setState(() {
        name = userData['fullName'] ?? '';
        email = userData['email'] ?? '';
        role = userData['role'] ?? '';
        storeName = fetchedStoreName;
        storeCode = fetchedStoreCode;
        benefitQrBase64 = fetchedBenefitQrBase64;
        benefitNumberController.text = fetchedBenefitNumber;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _pickQrImage() async {
    if (!isOwner) return;

    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 40,
      );

      if (pickedFile == null) return;

      setState(() {
        isSaving = true;
      });

      final Uint8List bytes = await pickedFile.readAsBytes();
      // The receipt screen reads this Base64 payment image from the store record.
      final String base64String = base64Encode(bytes);

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeCode)
          .update({'benefitQrBase64': base64String});

      setState(() {
        benefitQrBase64 = base64String;
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('QR uploaded successfully')));
    } catch (e) {
      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to upload QR: $e')));
    }
  }

  Future<void> _savePaymentData() async {
    if (!isOwner) return;

    try {
      setState(() {
        isSaving = true;
      });

      final String newBenefitNumber = benefitNumberController.text.trim();

      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeCode)
          .update({'benefitNumber': newBenefitNumber});

      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment settings saved')));
    } catch (e) {
      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save payment settings: $e')),
      );
    }
  }

  Future<void> _logout() async {
    // AuthWrapper shows the login screen when the session ends.
    await FirebaseAuth.instance.signOut();
  }

  Widget _buildQrPlaceholder() {
    return Container(
      height: 160,
      width: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: const Icon(Icons.qr_code_2, size: 70, color: AppColors.muted),
    );
  }

  Widget _buildQrPreview() {
    if (benefitQrBase64.isEmpty) return _buildQrPlaceholder();

    try {
      final Uint8List bytes = base64Decode(benefitQrBase64);

      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        child: Image.memory(
          bytes,
          height: 160,
          width: 160,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildQrPlaceholder();
          },
        ),
      );
    } catch (_) {
      // Invalid data and unsupported images use the same placeholder.
      return _buildQrPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            24,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(26),
                    bottomRight: Radius.circular(26),
                  ),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.surface,
                      child: Icon(
                        Icons.person_outline,
                        size: 42,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      name.isEmpty ? 'User' : name,
                      style: const TextStyle(
                        fontSize: AppTypography.title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBrand,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      role.isEmpty ? 'User' : role,
                      style: const TextStyle(
                        fontSize: AppTypography.label,
                        color: AppColors.onBrand,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.text.withValues(alpha: 0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.storefront_outlined,
                        iconBg: AppColors.soft,
                        iconColor: AppColors.primaryDark,
                        title: 'Store Name',
                        value: storeName.isEmpty ? 'No store' : storeName,
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.tag_outlined,
                        iconBg: AppColors.warningSoft,
                        iconColor: AppColors.warning,
                        title: 'Store Code',
                        value: storeCode.isEmpty ? '-' : storeCode,
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.email_outlined,
                        iconBg: AppColors.accentSoft,
                        iconColor: AppColors.primaryDark,
                        title: 'Email',
                        value: email.isEmpty ? '-' : email,
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.account_circle_outlined,
                        iconBg: AppColors.accentSoft,
                        iconColor: AppColors.primaryDark,
                        title: 'Role',
                        value: role.isEmpty ? '-' : role,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.controlRadius,
                      ),
                      onTap: () {
                        setState(() {
                          isPaymentExpanded = !isPaymentExpanded;
                        });
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppColors.soft,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.controlRadius,
                              ),
                            ),
                            child: const Icon(
                              Icons.payments_outlined,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Payment Settings',
                                  style: TextStyle(
                                    fontSize: AppTypography.section,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Manage Benefit payment information',
                                  style: TextStyle(
                                    fontSize: AppTypography.caption,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isPaymentExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                    if (isPaymentExpanded) ...[
                      const SizedBox(height: 18),
                      TextField(
                        controller: benefitNumberController,
                        enabled: isOwner,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Benefit Number',
                          hintText: 'Enter your Benefit number',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.controlRadius,
                            ),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Benefit QR',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildQrPreview(),
                            if (isOwner) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: isSaving ? null : _pickQrImage,
                                icon: const Icon(Icons.upload_outlined),
                                label: const Text('Upload QR'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.primaryDark,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (isOwner) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : _savePaymentData,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.controlRadius,
                                ),
                              ),
                            ),
                            child: isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onBrand,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Save Payment Settings',
                                    style: TextStyle(
                                      color: AppColors.onBrand,
                                      fontSize: AppTypography.button,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    Text(
                      'AI Assisted Pocket Register',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.muted,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    border: Border.all(color: AppColors.danger, width: 1.6),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, color: AppColors.danger),
                      SizedBox(width: 10),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
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
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
