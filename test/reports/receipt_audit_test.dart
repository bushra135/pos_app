import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/receipt_audit.dart';

void main() {
  Map<String, dynamic> sale({
    List<Map<String, Object>>? items,
    double subtotal = 3.6,
    DateTime? created,
    DateTime? synced,
    String type = 'sale',
  }) => {
    'type': type,
    'subtotal': subtotal,
    'createdAt': created ?? DateTime(2026, 11, 25, 10),
    'syncedAt': synced ?? DateTime(2026, 11, 25, 10, 1),
    'items':
        items ??
        [
          {'productId': 'pen', 'price': 0.5, 'quantity': 2},
          {'productId': 'book', 'price': 1.3, 'quantity': 2},
        ],
  };
  const prices = {'pen': 0.5, 'book': 1.3};

  test('a normal receipt has no issues', () {
    expect(ReceiptAudit.issues(sale(), catalogPrices: prices), isEmpty);
  });

  test('lines that do not add up to the subtotal are flagged', () {
    expect(ReceiptAudit.issues(sale(subtotal: 0.001), catalogPrices: prices), [
      ReceiptAudit.linesDontAddUp,
    ]);
  });

  test('zero, negative or fractional quantities are flagged', () {
    final issues = ReceiptAudit.issues(
      sale(
        items: [
          {'productId': 'pen', 'price': 0.5, 'quantity': -5},
        ],
        subtotal: -2.5,
      ),
    );
    expect(issues, contains(ReceiptAudit.badQuantity));
  });

  test('an item sold below its catalogue price is flagged', () {
    final issues = ReceiptAudit.issues(
      sale(
        items: [
          {'productId': 'book', 'price': 0.001, 'quantity': 1},
        ],
        subtotal: 0.001,
      ),
      catalogPrices: prices,
    );
    expect(issues, [ReceiptAudit.belowCatalogPrice]);
  });

  test('a receipt saved more than a day after the sale is flagged', () {
    expect(
      ReceiptAudit.issues(
        sale(created: DateTime(2026, 11, 20), synced: DateTime(2026, 11, 25)),
        catalogPrices: prices,
      ),
      [ReceiptAudit.lateSync],
    );
  });

  test('refund receipts are not checked', () {
    expect(ReceiptAudit.issues(sale(type: 'refund', subtotal: 0)), isEmpty);
  });
}
