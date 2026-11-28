import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/report_sale.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/sale_gateway.dart';

import '../support/optimistic_firestore.dart';

SaleRecord sale({double discount = 0, double vatRate = SaleRecord.bahrainVatRate}) => SaleRecord(
  id: 'sale-vat',
  storeCode: 'STORE-A',
  storeName: 'Store A',
  cashierUid: 'cashier-a',
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime.utc(2026, 11, 24, 10),
  items: const [
    SaleLine(productId: 'product-a', barcode: '123', name: 'Pen', price: 2.5, quantity: 2),
    SaleLine(productId: 'product-b', barcode: '456', name: 'Book', price: 6.0, quantity: 1),
  ],
  discount: discount,
  vatRate: vatRate,
);

void main() {
  group('VAT and discount maths', () {
    test('prices include 10% VAT; a discount lowers the amount paid and its VAT', () {
      final plain = sale();
      expect(plain.subtotal, 11.0);
      expect(plain.total, 11.0);
      expect(plain.tax, 1.0); // 11 × 10 / 110

      final discounted = sale(discount: 2.2);
      expect(discounted.subtotal, 11.0);
      expect(discounted.total, 8.8);
      expect(discounted.tax, 0.8);
    });

    test('older receipts without VAT or discount keep their totals', () {
      final legacy = SaleRecord.fromJson({...sale(vatRate: 0).toJson()}..remove('vatRate'));
      expect(legacy.vatRate, 0);
      expect(legacy.tax, 0);
      expect(legacy.total, 11.0);
    });

    test('discount and VAT survive the offline queue round trip', () {
      final restored = SaleRecord.fromJson(sale(discount: 1.5).toJson());
      expect(restored.discount, 1.5);
      expect(restored.vatRate, 10);
      expect(restored.total, 9.5);
    });
  });

  group('gateway', () {
    late OptimisticFirestore firestore;
    late FirestoreSaleGateway gateway;

    setUp(() async {
      firestore = OptimisticFirestore();
      gateway = FirestoreSaleGateway(firestore: firestore, currentUserId: () => 'cashier-a');
      await firestore.collection('users').doc('cashier-a').set({
        'storeCode': 'STORE-A',
        'role': 'cashier',
      });
      for (final p in [('product-a', '123'), ('product-b', '456')]) {
        await firestore.collection('products').doc(p.$1).set({
          'storeCode': 'STORE-A',
          'barcode': p.$2,
          'stock': 10,
        });
      }
    });

    test('saves subtotal, discount and VAT so the dashboard reads them', () async {
      await gateway.commit(sale(discount: 2.2));
      final saved = (await firestore.collection('sales').doc('sale-vat').get()).data()!;
      expect(saved['subtotal'], 11.0);
      expect(saved['discount'], 2.2);
      expect(saved['total'], 8.8);
      expect(saved['tax'], 0.8);

      final report = ReportSale.fromMap(saved);
      expect(report.grossSales, 11.0);
      expect(report.discount, 2.2);
      expect(report.netSales, 8.8);
    });

    test('rejects a discount larger than the subtotal', () async {
      await expectLater(gateway.commit(sale(discount: 20)), throwsA(isA<SaleConflictException>()));
      expect((await firestore.collection('sales').get()).docs, isEmpty);
    });
  });
  // The checkout-screen discount check runs as the owner in checkout_owner_options_test.dart:
  // discounts are an owner action, so cashiers no longer see the button.
}
