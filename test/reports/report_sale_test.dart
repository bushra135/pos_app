import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/report_sale.dart';

void main() {
  group('Shared report interpretation', () {
    test('current sale keeps amounts and line data', () {
      final sale = ReportSale.fromMap({
        'total': 8.0,
        'discount': 2.0,
        'refund': 1.0,
        'paymentMethod': 'benefitpay',
        'items': [
          {'name': 'Pen', 'quantity': 2},
        ],
      });
      expect(sale.grossSales, 10);
      expect(sale.netSales, 7);
      expect(sale.discount, 2);
      expect(sale.refund, 1);
      expect(sale.paymentMethod, 'BenefitPay');
      expect(sale.items.single['name'], 'Pen');
    });
    test('legacy fields and numeric text retain their priority', () {
      final sale = ReportSale.fromMap({
        'netTotal': '0',
        'total': 999,
        'subTotal': '12.5',
        'discountAmount': '2',
        'paymentType': 'visa',
        'cartItems': [
          false,
          {},
          <Object, Object>{'name': 'Book'},
        ],
      });
      expect(sale.netSales, 0);
      expect(sale.grossSales, 12.5);
      expect(sale.paymentMethod, 'Card');
      expect(sale.items.length, 1);
    });
    test('standalone returns subtract their amount exactly once', () {
      final sale = ReportSale.fromMap({'type': 'return', 'totalAmount': 6});
      expect(sale.isRefund, isTrue);
      expect(sale.grossSales, 0);
      expect(sale.refund, 6);
      expect(sale.netSales, -6);
      final partial = ReportSale.fromMap({
        'status': 'refunded',
        'total': 6,
        'refundAmount': 2,
      });
      expect(partial.netSales, -2);
    });
    test('item identity and date compatibility remain stable', () {
      expect(reportProductKey({'barcode': '001', 'id': 'x'}, 'Pen'), '001');
      expect(reportProductKey({'id': 'x'}, 'Pen'), 'x');
      expect(reportProductKey({}, ' Blue Pen '), 'blue pen');
      final date = DateTime(2026, 10, 29);
      expect(reportDate(Timestamp.fromDate(date)), date);
      expect(reportDate(date.toIso8601String()), date);
      expect(reportDate('invalid'), isNull);
    });
  });
}
