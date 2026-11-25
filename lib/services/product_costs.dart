import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Cost prices are kept apart from products (`productCosts/{productId}`) so only the
/// owner can read them; cashiers read products for selling and never see a cost.
abstract final class ProductCosts {
  static const collection = 'productCosts';

  /// Owner only: product id -> cost. Empty when nothing is saved or access is denied.
  static Future<Map<String, double>> load(FirebaseFirestore firestore, String storeCode) async {
    try {
      final snapshot = await firestore
          .collection(collection)
          .where('storeCode', isEqualTo: storeCode)
          .get();
      return {
        for (final doc in snapshot.docs)
          if (doc.data()['cost'] is num) doc.id: (doc.data()['cost'] as num).toDouble(),
      };
    } catch (error) {
      debugPrint('Cost prices not loaded: $error');
      return const {};
    }
  }

  static Future<void> save(
    FirebaseFirestore firestore, {
    required String productId,
    required String storeCode,
    required double cost,
  }) => firestore.collection(collection).doc(productId).set({
    'storeCode': storeCode,
    'cost': cost,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// Owner only: removes a deleted product's cost. Errors are logged, never thrown.
  static Future<void> delete(FirebaseFirestore firestore, String productId) async {
    try {
      await firestore.collection(collection).doc(productId).delete();
    } catch (error) {
      debugPrint('Cost price not removed: $error');
    }
  }

  /// Moves cost prices still saved on product documents (older versions) into the
  /// owner-only collection and removes them from the product. Safe to call repeatedly.
  static Future<int> migrateLegacy(
    FirebaseFirestore firestore,
    String storeCode,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  ) async {
    final legacy = products.where((doc) => doc.data().containsKey('cost')).toList();
    if (legacy.isEmpty) return 0;
    var moved = 0;
    for (final doc in legacy) {
      try {
        final cost = doc.data()['cost'];
        final batch = firestore.batch();
        if (cost is num && cost > 0) {
          batch.set(firestore.collection(collection).doc(doc.id), {
            'storeCode': storeCode,
            'cost': cost.toDouble(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        batch.update(doc.reference, {'cost': FieldValue.delete()});
        await batch.commit();
        moved++;
      } catch (error) {
        debugPrint('Cost move skipped for ${doc.id}: $error');
      }
    }
    return moved;
  }
}
