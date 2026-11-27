import 'package:cloud_firestore/cloud_firestore.dart';

/// One atomic barcode claim per store. Existing document IDs and receipt links stay intact.
abstract final class ProductBarcodes {
  static DocumentReference<Map<String, dynamic>> claim(
    FirebaseFirestore db,
    String code,
    String barcode,
  ) => db.collection('productBarcodes').doc('${code}_$barcode');

  static Future<void> save(
    FirebaseFirestore db,
    DocumentReference<Map<String, dynamic>> product,
    Map<String, dynamic> data, {
    bool create = false,
  }) async {
    final code = data['storeCode'] as String;
    final barcode = (data['barcode'] as String).trim();
    if (barcode.isEmpty || barcode.contains('/')) throw StateError('Enter a valid barcode.');
    // Protect legacy records that predate claims as well as claimed records.
    final duplicates = await db
        .collection('products')
        .where('storeCode', isEqualTo: code)
        .where('barcode', isEqualTo: barcode)
        .get(const GetOptions(source: Source.server));
    if (duplicates.docs.any((d) => d.id != product.id)) {
      throw StateError('This barcode already exists');
    }
    await db.runTransaction((tx) async {
      final current = await tx.get(product);
      if (create && current.exists) throw StateError('This barcode already exists');
      final nextClaim = claim(db, code, barcode);
      final held = await tx.get(nextClaim);
      if (held.exists && held.data()?['productId'] != product.id) {
        final previous = await tx.get(
          db.collection('products').doc(held.data()!['productId'] as String),
        );
        if (previous.exists) throw StateError('This barcode already exists');
      }
      final oldBarcode = current.data()?['barcode']?.toString() ?? '';
      final oldClaim = oldBarcode.isNotEmpty && oldBarcode != barcode && !oldBarcode.contains('/')
          ? claim(db, code, oldBarcode)
          : null;
      final old = oldClaim == null ? null : await tx.get(oldClaim);
      tx.set(nextClaim, {'storeCode': code, 'barcode': barcode, 'productId': product.id});
      if (old?.data()?['productId'] == product.id) tx.delete(oldClaim!);
      if (current.exists) {
        tx.update(product, data);
      } else {
        tx.set(product, data);
      }
    });
  }
}
