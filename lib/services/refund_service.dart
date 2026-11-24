import 'package:cloud_firestore/cloud_firestore.dart';

/// Owner-approved returns. A refund is its own sales document (`type: refund`) that links
/// to the original receipt, so the original stays unchanged for the audit trail.
/// Returned units go back into stock in the same transaction.
abstract final class RefundService {
  static double _fils(double value) => (value * 1000).roundToDouble() / 1000;

  static int _int(Object? value) => value is num ? value.toInt() : 0;
  static double _num(Object? value) => value is num ? value.toDouble() : 0;

  /// Units of each product already returned from [originalSaleId].
  static Future<Map<String, int>> refundedQuantities(
    FirebaseFirestore db, {
    required String storeCode,
    required String originalSaleId,
  }) async {
    final snapshot = await db
        .collection('sales')
        .where('storeCode', isEqualTo: storeCode)
        .where('originalSaleId', isEqualTo: originalSaleId)
        .get();
    final returned = <String, int>{};
    for (final doc in snapshot.docs) {
      for (final item in (doc.data()['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = (item['productId'] ?? '').toString();
        returned[id] = (returned[id] ?? 0) + _int(item['quantity']);
      }
    }
    return returned;
  }

  /// Records a refund of [quantities] (productId → units) from the original sale.
  /// Returns the refund amount in BD.
  static Future<double> refund(
    FirebaseFirestore db, {
    required String originalSaleId,
    required Map<String, dynamic> original,
    required Map<String, int> quantities,
    required String ownerUid,
    required String ownerName,
    DateTime? now,
  }) async {
    final storeCode = (original['storeCode'] ?? '').toString();
    final type = (original['type'] ?? original['status'] ?? '').toString();
    if (storeCode.isEmpty || type.contains('refund')) {
      throw StateError('This receipt cannot be refunded.');
    }
    final requested = Map.of(quantities)..removeWhere((_, qty) => qty <= 0);
    if (requested.isEmpty) throw StateError('Choose at least one item to return.');

    final lines = <String, Map>{};
    final sold = <String, int>{};
    for (final item in (original['items'] as List? ?? const [])) {
      if (item is! Map) continue;
      final id = (item['productId'] ?? '').toString();
      lines.putIfAbsent(id, () => item);
      sold[id] = (sold[id] ?? 0) + _int(item['quantity']);
    }
    final already = await refundedQuantities(
      db,
      storeCode: storeCode,
      originalSaleId: originalSaleId,
    );
    for (final entry in requested.entries) {
      final left = (sold[entry.key] ?? 0) - (already[entry.key] ?? 0);
      if (entry.value > left) {
        throw StateError(
          'Only $left of ${lines[entry.key]?['name'] ?? 'this item'} can be returned.',
        );
      }
    }

    // Discounts reduce what was paid, so refunds pay back the same share.
    final subtotal = _num(original['subtotal']);
    final total = _num(original['total']);
    final paidShare = subtotal > 0 && total > 0 ? total / subtotal : 1.0;
    final vatRate = _num(original['vatRate']) > 0
        ? _num(original['vatRate'])
        : (_num(original['tax']) > 0 ? 10.0 : 0.0);

    final items = <Map<String, dynamic>>[];
    double amount = 0;
    for (final entry in requested.entries) {
      final line = lines[entry.key]!;
      final price = _num(line['price']);
      amount += price * entry.value * paidShare;
      items.add({
        'productId': entry.key,
        'barcode': (line['barcode'] ?? '').toString(),
        'name': (line['name'] ?? '').toString(),
        'price': price,
        'quantity': entry.value,
        'subtotal': _fils(price * entry.value),
      });
    }
    amount = _fils(amount);
    final tax = vatRate <= 0 ? 0.0 : _fils(amount * vatRate / (100 + vatRate));

    final refundRef = db.collection('sales').doc();
    final when = now ?? DateTime.now();
    await db.runTransaction((transaction) async {
      final products = <DocumentReference<Map<String, dynamic>>, int>{};
      for (final entry in requested.entries) {
        final ref = db.collection('products').doc(entry.key);
        final snapshot = await transaction.get(ref);
        // Deleted or foreign products are refunded in money but not restocked.
        if (snapshot.exists && snapshot.data()?['storeCode'] == storeCode) {
          products[ref] = entry.value;
        }
      }
      transaction.set(refundRef, {
        'id': refundRef.id,
        'storeCode': storeCode,
        'storeName': (original['storeName'] ?? '').toString(),
        'cashierUid': ownerUid,
        'cashierName': ownerName,
        'paymentMethod': (original['paymentMethod'] ?? 'Cash').toString(),
        'createdAt': Timestamp.fromDate(when),
        'receiptNumber': 'RFND-${refundRef.id}',
        'items': items,
        'productIds': requested.keys.toList(),
        'subtotal': -amount,
        'total': -amount,
        'refund': amount,
        'tax': -tax,
        'discount': 0.0,
        'status': 'refund',
        'type': 'refund',
        'originalSaleId': originalSaleId,
        'originalReceipt': (original['receiptNumber'] ?? '').toString(),
      });
      for (final entry in products.entries) {
        transaction.update(entry.key, {
          'stock': FieldValue.increment(entry.value),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return amount;
  }
}
