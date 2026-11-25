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
  }) async {
    final name = newName.trim();
    final store = newStoreName.trim();
    final batch = firestore.batch();
    var changed = false;
    if (name != oldName.trim()) {
      batch.update(firestore.collection('users').doc(uid), {
        'fullName': name,
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
}
