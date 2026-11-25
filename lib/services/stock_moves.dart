import 'package:cloud_firestore/cloud_firestore.dart';

/// Every stock change outside a sale (restock, count correction, write-off) is saved with
/// who made it, why, and the stock before and after. Owners read the history; for
/// cashiers the security rules only accept a stock change that arrives with its move.
abstract final class StockMoves {
  static const collection = 'stockMoves';
  static const reasons = ['restock', 'count_correction', 'damaged', 'other'];

  /// Sets the product's stock to `newStock(current)` and records the move, in one
  /// transaction, so a sale saved at the same moment is never overwritten.
  static Future<({int before, int after})> adjust(
    FirebaseFirestore firestore, {
    required DocumentReference<Map<String, dynamic>> product,
    required String storeCode,
    required String reason,
    required String byUid,
    required String byName,
    required int Function(int current) newStock,
  }) {
    assert(reasons.contains(reason));
    final move = firestore.collection(collection).doc();
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(product);
      final data = snapshot.data();
      if (data == null || data['storeCode'] != storeCode) {
        throw StateError('This product was removed or belongs to another store.');
      }
      final raw = data['stock'] ?? data['quantity'] ?? 0;
      final before = raw is num ? raw.toInt() : 0;
      final after = newStock(before);
      if (after < 0) throw StateError('Stock cannot go below zero.');
      transaction.set(move, {
        'storeCode': storeCode,
        'productId': product.id,
        'productName': (data['name'] ?? '').toString(),
        'before': before,
        'after': after,
        'delta': after - before,
        'reason': reason,
        'byUid': byUid,
        'byName': byName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(product, {
        'stock': after,
        if (data.containsKey('quantity')) 'quantity': after,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastStockMoveId': move.id,
      });
      return (before: before, after: after);
    });
  }

  /// The latest moves of one product, newest first (owner only).
  static Future<List<Map<String, dynamic>>> history(
    FirebaseFirestore firestore, {
    required String storeCode,
    required String productId,
    int limit = 10,
  }) async {
    final snapshot = await firestore
        .collection(collection)
        .where('storeCode', isEqualTo: storeCode)
        .where('productId', isEqualTo: productId)
        .get();
    final moves = snapshot.docs.map((doc) => doc.data()).toList()
      ..sort((a, b) {
        final at = a['createdAt'], bt = b['createdAt'];
        if (at is! Timestamp || bt is! Timestamp) return 0;
        return bt.compareTo(at);
      });
    return moves.take(limit).toList();
  }
}
