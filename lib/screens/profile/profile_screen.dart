import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../widgets/motion.dart';
import '../../widgets/sale_sync_panel.dart';
import '../../utils/cart_manager.dart';
import '../backup/backup_screen.dart';
import '../../app/app_language.dart';
import '../../widgets/adaptive_layout.dart';
import '../../services/profile_edits.dart';
import '../../utils/profile_photo_data.dart';
import 'unknown_items_card.dart';
import 'vat_settings_card.dart';
import '../../widgets/qr_image_box.dart';

/// Shows user details and payment settings shared by store employees.
/// Shows account details, payment settings, sync status and owner recovery access.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onSwitchMode, this.cashierMode = false});

  final VoidCallback? onSwitchMode;
  final bool cashierMode;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// Account details, profile photo, payment and VAT settings (owner), sync status,
/// backup, password reset and sign-out.
class _ProfileScreenState extends State<ProfileScreen> {
  String name = '';
  String phone = '';
  String email = '';
  String role = '';
  String storeName = '';
  String storeCode = '';
  String benefitQrBase64 = '';
  String photo = '';
  bool _photoSaving = false;
  Map<String, dynamic> storeData = const {};

  bool isLoading = true;
  bool isSaving = false;
  bool _loggingOut = false;

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

  /// Loads the user's profile and store; copies a newly confirmed email to the profile.
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userData = userDoc.data()!;
      // A new email confirmed through the link from Firebase is copied to the profile.
      try {
        await user.reload();
        final fresh = FirebaseAuth.instance.currentUser;
        if ((fresh?.email ?? '').toLowerCase() !=
            (userData['email'] ?? '').toString().toLowerCase()) {
          await fresh?.getIdToken(true);
          if (await ProfileEdits.syncEmail(
            FirebaseFirestore.instance,
            uid: user.uid,
            profileEmail: (userData['email'] ?? '').toString(),
            authEmail: fresh?.email,
          )) {
            userData['email'] = fresh!.email!.toLowerCase();
          }
        }
      } catch (e) {
        debugPrint('Email sync skipped: $e');
      }

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
          this.storeData = storeData;
          fetchedStoreName = storeData['storeName'] ?? fetchedStoreName;
          fetchedBenefitNumber = storeData['benefitNumber'] ?? '';
          fetchedBenefitQrBase64 = storeData['benefitQrBase64'] ?? '';
        }
      }

      setState(() {
        name = userData['fullName'] ?? '';
        email = userData['email'] ?? '';
        phone = (userData['phone'] ?? '').toString();
        photo = (userData['photo'] ?? '').toString();
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

  /// Lets the user add, replace or remove their own profile photo.
  Future<void> _changePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _photoSaving) return;
    final hasPhoto = ProfilePhotoData.decode(photo) != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Profile photo'.tr,
                style: const TextStyle(
                  fontSize: AppTypography.section,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primaryDark),
              title: Text('Choose from gallery'.tr),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primaryDark),
              title: Text('Take a photo'.tr),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: Text('Remove photo'.tr, style: const TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    String? next;
    if (action != 'remove') {
      final XFile? picked;
      try {
        picked = await ImagePicker().pickImage(
          source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
          preferredCameraDevice: CameraDevice.front,
        );
      } catch (e) {
        debugPrint('Photo pick failed: $e');
        _photoMessage('Could not open the camera or gallery.');
        return;
      }
      if (picked == null || !mounted) return;
      setState(() => _photoSaving = true);
      try {
        next = await ProfilePhotoData.prepare(await picked.readAsBytes());
      } catch (e) {
        debugPrint('Photo resize failed: $e');
        if (mounted) setState(() => _photoSaving = false);
        _photoMessage('Could not use this image. Choose another one.');
        return;
      }
    }

    if (mounted) setState(() => _photoSaving = true);
    try {
      await ProfileEdits.savePhoto(FirebaseFirestore.instance, uid: user.uid, photo: next);
      if (!mounted) return;
      setState(() {
        photo = next ?? '';
        _photoSaving = false;
      });
      _photoMessage(next == null ? 'Profile photo removed' : 'Profile photo updated');
    } catch (e) {
      debugPrint('Photo save failed: $e');
      if (mounted) setState(() => _photoSaving = false);
      _photoMessage('Could not update the photo. Try again.');
    }
  }

  void _photoMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.tr)));
  }

  /// Owner picks the BenefitPay QR image; it is saved on the store for receipts.
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

      await FirebaseFirestore.instance.collection('stores').doc(storeCode).update({
        'benefitQrBase64': base64String,
      });

      setState(() {
        benefitQrBase64 = base64String;
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('QR uploaded successfully'.tr)));
    } catch (e) {
      // Details go to the debug log only; the owner sees a friendly message.
      debugPrint('QR upload failed: $e');
      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not upload the QR image. Try again.'.tr)));
    }
  }

  /// Saves the store's BenefitPay number.
  Future<void> _savePaymentData() async {
    if (!isOwner) return;

    try {
      setState(() {
        isSaving = true;
      });

      final String newBenefitNumber = benefitNumberController.text.trim();

      await FirebaseFirestore.instance.collection('stores').doc(storeCode).update({
        'benefitNumber': newBenefitNumber,
      });

      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payment settings saved'.tr)));
    } catch (e) {
      debugPrint('Payment settings save failed: $e');
      setState(() {
        isSaving = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save payment settings. Try again.'.tr)));
    }
  }

  /// Saves the cart on the device, then signs out.
  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await CartManager.flush();
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Your cart could not be saved. Check device storage and try signing out again.'.tr,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  /// Edit your name (everyone), the store name (owner), or get a password reset link.
  Future<void> _openEditor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final nameController = TextEditingController(text: name);
    final storeController = TextEditingController(text: storeName);
    final emailController = TextEditingController(text: email);
    final phoneController = TextEditingController(text: phone);
    final passwordController = TextEditingController();
    String? emailSentTo;
    final formKey = GlobalKey<FormState>();
    var saving = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Future<void> save() async {
            if (!formKey.currentState!.validate()) return;
            setSheet(() {
              saving = true;
              error = null;
            });
            final newEmail = emailController.text.trim().toLowerCase();
            final emailChanged = newEmail != email.trim().toLowerCase();
            try {
              if (emailChanged) {
                // Firebase asks for the password again, then emails a confirmation link
                // to the new address; the email changes only once that link is opened.
                await user.reauthenticateWithCredential(
                  EmailAuthProvider.credential(
                    email: user.email ?? email,
                    password: passwordController.text,
                  ),
                );
                await user.verifyBeforeUpdateEmail(
                  newEmail,
                  ActionCodeSettings(
                    url: 'https://shoppad-f3d43.firebaseapp.com',
                    handleCodeInApp: false,
                  ),
                );
                emailSentTo = newEmail;
              }
              await ProfileEdits.save(
                FirebaseFirestore.instance,
                uid: user.uid,
                storeCode: storeCode,
                isOwner: isOwner,
                oldName: name,
                newName: nameController.text,
                oldStoreName: storeName,
                newStoreName: storeController.text,
                oldPhone: phone,
                newPhone: phoneController.text,
              ).timeout(const Duration(seconds: 15));
              if (sheetContext.mounted) Navigator.pop(sheetContext, true);
            } on FirebaseAuthException catch (e) {
              debugPrint('Email change failed: ${e.code}');
              setSheet(() {
                saving = false;
                error = switch (e.code) {
                  'wrong-password' || 'invalid-credential' => 'Your current password is incorrect.',
                  'email-already-in-use' => 'This email is already in use',
                  'invalid-email' => 'Enter a valid email address.',
                  'too-many-requests' => 'Too many attempts. Please try again later.',
                  _ => 'Could not change your email. Try again later.',
                };
              });
            } catch (e) {
              debugPrint('Profile save failed: $e');
              setSheet(() {
                saving = false;
                error = 'Could not save your changes. Check your connection and try again.';
              });
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit profile'.tr,
                    style: const TextStyle(
                      fontSize: AppTypography.section,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    enabled: !saving,
                    textInputAction: isOwner ? TextInputAction.next : TextInputAction.done,
                    maxLength: ProfileEdits.maxLength,
                    decoration: InputDecoration(
                      labelText: 'Full name'.tr,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) => ProfileEdits.checkName(value ?? '')?.tr,
                    onFieldSubmitted: isOwner ? null : (_) => save(),
                  ),
                  if (isOwner) ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: storeController,
                      enabled: !saving,
                      textInputAction: TextInputAction.done,
                      maxLength: ProfileEdits.maxLength,
                      decoration: InputDecoration(
                        labelText: 'Store name'.tr,
                        helperText: 'Shown to your cashiers and on new receipts'.tr,
                        prefixIcon: const Icon(Icons.storefront_outlined),
                      ),
                      validator: (value) => ProfileEdits.checkStoreName(value ?? '')?.tr,
                      onFieldSubmitted: (_) => save(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: phoneController,
                    enabled: !saving,
                    keyboardType: TextInputType.phone,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: 'Phone number (optional)'.tr,
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    validator: (value) => ProfileEdits.checkPhone(value ?? '')?.tr,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailController,
                    enabled: !saving,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email'.tr,
                      helperText: 'A new email changes after you open the link we send to it'.tr,
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (value) => ProfileEdits.checkEmail(value ?? '')?.tr,
                    onChanged: (_) => setSheet(() {}),
                  ),
                  if (emailController.text.trim().toLowerCase() != email.trim().toLowerCase()) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordController,
                      enabled: !saving,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Current password'.tr,
                        helperText: 'Needed to change your email'.tr,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (value) =>
                          (value ?? '').isEmpty ? 'Enter your current password'.tr : null,
                    ),
                  ],
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryDark),
                    title: Text('Change password'.tr),
                    subtitle: Text('We will email you a link to set a new one'.tr),
                    onTap: saving ? null : () => _sendPasswordReset(sheetContext),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!.tr, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? 'Saving...'.tr : 'Save'.tr),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    nameController.dispose();
    storeController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    if (saved == true) {
      await _loadUserData();
      if (mounted) {
        final sentTo = emailSentTo;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: Duration(seconds: sentTo == null ? 4 : 8),
            content: Text(
              sentTo == null
                  ? 'Profile updated'.tr
                  : 'Profile updated. Open the link we sent to {email} to finish changing your email, then sign in with it.'
                        .trArgs({'email': sentTo}),
            ),
          ),
        );
      }
    }
  }

  /// Emails a password reset link to the signed-in address.
  Future<void> _sendPasswordReset(BuildContext sheetContext) async {
    final address = FirebaseAuth.instance.currentUser?.email ?? email;
    if (address.isEmpty) return;
    var message = 'Password reset link sent to {email}';
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: address,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://shoppad-f3d43.firebaseapp.com',
          handleCodeInApp: false,
        ),
      );
    } catch (e) {
      // Only the error code: the full error may carry the address.
      debugPrint('Reset email failed: ${e is FirebaseAuthException ? e.code : e.runtimeType}');
      message = 'Could not send the link. Try again later.';
    }
    if (!sheetContext.mounted) return;
    ScaffoldMessenger.of(
      sheetContext,
    ).showSnackBar(SnackBar(content: Text(message.trArgs({'email': address}))));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: HomeSkeleton(tiles: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 720,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 24),
            child: FadeSlideIn(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, 24, 0, 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Profile'.tr,
                        style: TextStyle(
                          fontSize: AppTypography.display,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AppColors.heroGradient,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    ),
                    child: Row(
                      children: [
                        ProfileAvatar(
                          name: name,
                          photo: photo,
                          saving: _photoSaving,
                          onTap: _changePhoto,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? 'User'.tr : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: AppTypography.section,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.onHero,
                                ),
                              ),
                              Text(
                                isOwner
                                    ? 'Owner'.tr
                                    : role.toLowerCase() == 'cashier'
                                    ? 'Cashier'.tr
                                    : 'User'.tr,
                                style: const TextStyle(
                                  fontSize: AppTypography.body,
                                  color: AppColors.onHeroMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openEditor,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text('Edit'.tr),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Transform.translate(
                    offset: Offset.zero,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.storefront_outlined,
                            iconBg: AppColors.soft,
                            iconColor: AppColors.primaryDark,
                            title: 'Store name'.tr,
                            value: storeName.isEmpty ? 'No store'.tr : storeName,
                          ),
                          const SizedBox(height: 16),
                          _InfoRow(
                            icon: Icons.tag_outlined,
                            iconBg: AppColors.warningSoft,
                            iconColor: AppColors.warning,
                            title: 'Store code'.tr,
                            value: storeCode.isEmpty ? '-' : storeCode,
                          ),
                          const SizedBox(height: 16),
                          _InfoRow(
                            icon: Icons.email_outlined,
                            iconBg: AppColors.accentSoft,
                            iconColor: AppColors.primaryDark,
                            title: 'Email'.tr,
                            value: email.isEmpty ? '-' : email,
                          ),
                          if (phone.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _InfoRow(
                              icon: Icons.phone_outlined,
                              iconBg: AppColors.successSoft,
                              iconColor: AppColors.success,
                              title: 'Phone'.tr,
                              value: phone,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isOwner && widget.onSwitchMode != null) ...[
                    Card(
                      child: ListTile(
                        leading: Icon(
                          widget.cashierMode ? Icons.manage_accounts_outlined : Icons.point_of_sale,
                          color: AppColors.primaryDark,
                        ),
                        title: Text(
                          (widget.cashierMode ? 'Switch to owner' : 'Switch to cashier').tr,
                        ),
                        subtitle: Text(
                          (widget.cashierMode
                                  ? 'Return to store management'
                                  : 'Scan products and complete sales')
                              .tr,
                        ),
                        trailing: const Icon(Icons.swap_horiz),
                        onTap: widget.onSwitchMode,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SaleSyncPanel(inProfile: true),
                  const SizedBox(height: 16),
                  if (isOwner && storeCode.isNotEmpty) ...[
                    VatSettingsCard(
                      key: ValueKey(storeData.hashCode),
                      storeCode: storeCode,
                      store: storeData,
                      onSaved: _loadUserData,
                    ),
                    const SizedBox(height: 16),
                    UnknownItemsCard(
                      key: ValueKey('unknown-${storeData.hashCode}'),
                      storeCode: storeCode,
                      store: storeData,
                      onSaved: _loadUserData,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
                          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
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
                                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                ),
                                child: const Icon(
                                  Icons.payments_outlined,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Payment settings'.tr,
                                      style: TextStyle(
                                        fontSize: AppTypography.section,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Manage Benefit payment information'.tr,
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
                              labelText: 'Benefit number'.tr,
                              hintText: 'Enter your Benefit number'.tr,
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
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
                              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Benefit QR'.tr,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                QrImageBox(
                                  base64: benefitQrBase64,
                                  size: 160,
                                  placeholderColor: AppColors.surface,
                                  placeholderIcon: Icons.qr_code_2,
                                ),
                                if (isOwner) ...[
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(
                                    onPressed: isSaving ? null : _pickQrImage,
                                    icon: const Icon(Icons.upload_outlined),
                                    label: Text('Upload QR'.tr),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.primaryDark),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
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
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
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
                                    : Text(
                                        'Save payment settings'.tr,
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
                  if (isOwner && storeCode.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: Text('Backup & recovery'.tr),
                        subtitle: Text('Create a cloud copy or recover missing records'.tr),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => BackupScreen(storeCode: storeCode)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
                        Text(
                          'AI Assisted Pocket Register'.tr,
                          style: TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Version 1.0.0'.tr,
                          style: TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Language: the whole app switches text and direction at once.
                  OutlinedButton.icon(
                    onPressed: AppLanguage.toggle,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.text,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      ),
                    ),
                    icon: const Icon(Icons.translate_rounded, color: AppColors.primaryDark),
                    label: Text(
                      '${'Language'.tr}: ${AppLanguage.isArabic ? 'العربية' : 'English'}  ·  ${AppLanguage.isArabic ? 'English' : 'العربية'}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _loggingOut ? null : _logout,
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                        border: Border.all(color: AppColors.danger, width: 1.6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, color: AppColors.danger),
                          const SizedBox(width: 10),
                          Text(
                            _loggingOut ? 'Signing out...'.tr : 'Logout'.tr,
                            style: const TextStyle(
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
        ),
      ),
    );
  }
}

/// Icon, label and value row in the account details card.
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
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
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
                style: const TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
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

/// The profile picture: the user's photo, or the first letter of their name.
/// A small camera badge shows that it can be changed; tapping opens the choices.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.photo,
    required this.onTap,
    this.saving = false,
    this.radius = 30,
  });

  final String name;
  final String photo;
  final VoidCallback onTap;
  final bool saving;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = ProfilePhotoData.decode(photo);
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    final reduced = Motion.reduced(context);
    final face = bytes == null
        ? Container(
            key: const ValueKey('initial'),
            color: AppColors.primaryDark,
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.onBrand,
                fontSize: AppTypography.metric,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : Image.memory(
            bytes,
            key: ValueKey(photo.length ^ photo.hashCode),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Container(color: AppColors.primaryDark),
          );
    return Semantics(
      button: true,
      label: (bytes == null ? 'Add a profile photo' : 'Change profile photo').tr,
      child: PressableScale(
        enabled: !saving,
        child: GestureDetector(
          onTap: saving ? null : onTap,
          child: SizedBox.square(
            dimension: radius * 2 + 6,
            child: Stack(
              children: [
                Positioned.fill(
                  left: 3,
                  top: 3,
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedSwitcher(
                            duration: reduced ? Duration.zero : Motion.fast,
                            child: face,
                          ),
                          if (saving)
                            const ColoredBox(
                              color: Color(0x66142C4E),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.onBrand,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: ExcludeSemantics(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: Icon(
                        bytes == null ? Icons.add_a_photo_outlined : Icons.photo_camera_outlined,
                        size: 13,
                        color: AppColors.onBrand,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
