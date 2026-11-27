import 'package:cloud_firestore/cloud_firestore.dart';

/// Saves the edits a user makes to their own profile.
///
/// Everyone can change their own name; only the owner can rename the store. Both match
/// what the Firestore rules allow (users: fullName/updatedAt, stores: storeName/updatedAt).
abstract final class ProfileEdits {
  static const maxLength = 60;

  /// English error text for `.tr`, or null when the value is fine.
  static String? checkName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter your name';
    if (name.length > maxLength) return 'Use 60 characters or fewer';
    return null;
  }

  /// Optional: empty is fine; otherwise digits with an optional +, spaces or dashes.
  static String? checkPhone(String value) {
    final phone = value.trim();
    if (phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(digits)) return 'Enter a valid phone number';
    return null;
  }

  static String? checkEmail(String value) {
    final email = value.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? checkStoreName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter the store name';
    if (name.length > maxLength) return 'Use 60 characters or fewer';
    return null;
  }

  /// Writes only what changed. Returns true when something was saved.
  static Future<bool> save(
    FirebaseFirestore firestore, {
    required String uid,
    required String storeCode,
    required bool isOwner,
    required String oldName,
    required String newName,
    required String oldStoreName,
    required String newStoreName,
    String oldPhone = '',
    String newPhone = '',
  }) async {
    final name = newName.trim();
    final store = newStoreName.trim();
    final phone = newPhone.trim();
    final batch = firestore.batch();
    var changed = false;
    final own = <String, dynamic>{
      if (name != oldName.trim()) 'fullName': name,
      if (phone != oldPhone.trim()) 'phone': phone,
    };
    if (own.isNotEmpty) {
      batch.update(firestore.collection('users').doc(uid), {
        ...own,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      changed = true;
    }
    if (isOwner && storeCode.isNotEmpty && store != oldStoreName.trim()) {
      batch.update(firestore.collection('stores').doc(storeCode), {
        'storeName': store,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      changed = true;
    }
    if (changed) await batch.commit();
    return changed;
  }

  /// Sets the user's own profile photo (a data URL from ProfilePhotoData), or removes
  /// it when [photo] is null. Touches only `photo` and `updatedAt`.
  static Future<void> savePhoto(
    FirebaseFirestore firestore, {
    required String uid,
    required String? photo,
  }) {
    return firestore
        .collection('users')
        .doc(uid)
        .update({'photo': photo ?? FieldValue.delete(), 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 20));
  }

  /// After the user confirms a new email (link sent by Firebase Auth), copies it to their
  /// profile so the owner's cashier list shows the right address. No-op when equal.
  static Future<bool> syncEmail(
    FirebaseFirestore firestore, {
    required String uid,
    required String profileEmail,
    required String? authEmail,
  }) async {
    final confirmed = (authEmail ?? '').trim().toLowerCase();
    if (confirmed.isEmpty || confirmed == profileEmail.trim().toLowerCase()) return false;
    await firestore.collection('users').doc(uid).update({
      'email': confirmed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }
}
