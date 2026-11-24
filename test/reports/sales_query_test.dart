import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/sales_query.dart';

void main() {
  test('loads only recent sales for the store and cashier asked for', () async {
    final db = FakeFirebaseFirestore();
    final now = DateTime(2026, 11, 24, 12);
    Future<void> add(String id, String store, String cashier, DateTime when) =>
        db.collection('sales').doc(id).set({
          'storeCode': store,
          'cashierUid': cashier,
          'total': 1,
          'createdAt': Timestamp.fromDate(when),
        });
    await add('today-a', 'A', 'c1', now);
    await add('today-other-cashier', 'A', 'c2', now);
    await add('last-year', 'A', 'c1', DateTime(2025, 1, 5));
    await add('other-store', 'B', 'c1', now);

    final storeDocs = await SalesQuery.since(db, storeCode: 'A', from: DateTime(2026, 11, 24));
    expect(storeDocs.map((d) => d.id).toSet(), {'today-a', 'today-other-cashier'});

    final cashierDocs = await SalesQuery.since(
      db,
      storeCode: 'A',
      cashierUid: 'c1',
      from: DateTime(2026, 11, 24),
    );
    expect(cashierDocs.map((d) => d.id), ['today-a']);
  });
}
