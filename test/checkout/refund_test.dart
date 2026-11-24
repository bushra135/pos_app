import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/report_sale.dart';
import 'package:pos_app/screens/closing/end_of_day_screen.dart';
import 'package:pos_app/services/refund_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  final original = {
    'storeCode': 'A',
    'storeName': 'Test Store',
    'paymentMethod': 'Cash',
    'receiptNumber': 'RCPT-sale-1',
    'status': 'completed',
    'type': 'sale',
    // 2 pens at 1.000 + 1 book at 6.000 = 8.000, then a 2.000 discount (25% off).
    'subtotal': 8.0,
    'discount': 2.0,
    'total': 6.0,
    'vatRate': 10,
    'tax': 0.545,
    'items': [
      {'productId': 'pen', 'barcode': '1', 'name': 'Pen', 'price': 1.0, 'quantity': 2},
      {'productId': 'book', 'barcode': '2', 'name': 'Book', 'price': 6.0, 'quantity': 1},
    ],
  };

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('products').doc('pen').set({'storeCode': 'A', 'stock': 5});
    await db.collection('products').doc('book').set({'storeCode': 'A', 'stock': 0});
  });

  Future<double> refund(Map<String, int> quantities) => RefundService.refund(
    db,
    originalSaleId: 'sale-1',
    original: original,
    quantities: quantities,
    ownerUid: 'owner',
    ownerName: 'Owner',
    now: DateTime(2026, 11, 24, 12),
  );

  test('partial return pays back the discounted share and restocks', () async {
    final amount = await refund({'book': 1});
    expect(amount, 4.5); // 6.000 × (6/8)

    final book = (await db.collection('products').doc('book').get()).data()!;
    expect(book['stock'], 1);
    final pen = (await db.collection('products').doc('pen').get()).data()!;
    expect(pen['stock'], 5);

    final refunds = await db.collection('sales').where('originalSaleId', isEqualTo: 'sale-1').get();
    final saved = refunds.docs.single.data();
    expect(saved['type'], 'refund');
    expect(saved['total'], -4.5);
    expect(saved['refund'], 4.5);
    expect(saved['tax'], -0.409);
    expect(saved['originalReceipt'], 'RCPT-sale-1');

    final report = ReportSale.fromMap(saved);
    expect(report.isRefund, isTrue);
    expect(report.netSales, -4.5);
  });

  test('cannot return more than was sold, across several refunds', () async {
    await refund({'pen': 1});
    await expectLater(refund({'pen': 2}), throwsA(isA<StateError>()));
    await refund({'pen': 1});
    expect(await RefundService.refundedQuantities(db, storeCode: 'A', originalSaleId: 'sale-1'), {
      'pen': 2,
    });
    expect((await db.collection('products').doc('pen').get()).data()!['stock'], 7);
  });

  test('a refund lowers the day close: net, cash and VAT', () async {
    await refund({'book': 1});
    final refundDoc = (await db.collection('sales').get()).docs.single.data();
    final day = DaySummary.fromSales([original, refundDoc]);
    expect(day.receipts, 1);
    expect(day.net, closeTo(1.5, 1e-9));
    expect(day.cashSales, closeTo(1.5, 1e-9));
    expect(day.vat, closeTo(0.136, 1e-9));
  });

  test('refund receipts and empty choices are rejected', () async {
    await expectLater(
      RefundService.refund(
        db,
        originalSaleId: 'r',
        original: {...original, 'type': 'refund'},
        quantities: {'pen': 1},
        ownerUid: 'owner',
        ownerName: 'Owner',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(refund({'pen': 0}), throwsA(isA<StateError>()));
  });
}
