import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Loads only the sales a screen needs instead of the store's whole history.
///
/// Reading every receipt on each visit gets slower and costs more reads as a store
/// grows. These queries filter by `createdAt` on the server; they need the composite
/// indexes in `firestore.indexes.json`. Until an index is built (or on an emulator
/// without it) the query falls back to the full store query, so screens never break.
abstract final class SalesQuery {
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> since(
    FirebaseFirestore firestore, {
    required String storeCode,
    required DateTime from,
    String? cashierUid,
    GetOptions options = const GetOptions(),
    Duration? timeout,
  }) async {
    Query<Map<String, dynamic>> base = firestore.collection('sales');
    if (cashierUid != null) base = base.where('cashierUid', isEqualTo: cashierUid);
    base = base.where('storeCode', isEqualTo: storeCode);

    Future<QuerySnapshot<Map<String, dynamic>>> run(Query<Map<String, dynamic>> query) {
      final future = query.get(options);
      return timeout == null ? future : future.timeout(timeout);
    }

    try {
      final snapshot = await run(
        base.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from)),
      );
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      debugPrint('Sales index not ready; loading the full history instead.');
    }
    // Fallback: same results, filtered on the device.
    final snapshot = await run(base);
    return snapshot.docs.where((doc) {
      final created = doc.data()['createdAt'];
      return created is! Timestamp || !created.toDate().isBefore(from);
    }).toList();
  }
}
