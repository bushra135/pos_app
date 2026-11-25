import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/today_summary.dart';

void main() {
  final now = DateTime(2026, 11, 24, 18);
  ({DateTime date, Map<String, dynamic> data}) receipt(
    DateTime date,
    double total,
    List<(String id, String name, int qty, double price)> items, {
    bool refund = false,
  }) => (
    date: date,
    data: {
      'total': total,
      if (refund) 'type': 'refund' else 'type': 'sale',
      'items': [
        for (final i in items) {'productId': i.$1, 'name': i.$2, 'quantity': i.$3, 'price': i.$4},
      ],
    },
  );

  test('refunds lower sales but are not counted as orders', () {
    final summary = TodaySummary.fromReceipts([
      receipt(DateTime(2026, 11, 24, 10), 2.85, [
        ('p1', 'Blue pen', 2, 0.5),
        ('p2', 'Notebook', 1, 1.85),
      ]),
      receipt(DateTime(2026, 11, 24, 11), 1.98, [
        ('p3', 'Juice', 1, 0.35),
        ('p2', 'Notebook', 1, 1.85),
      ]),
      receipt(DateTime(2026, 11, 24, 12), -0.5, [('p1', 'Blue pen', 1, 0.5)], refund: true),
    ], now);
    expect(summary.orders, 2);
    expect(summary.sales, closeTo(4.33, 1e-9));
    expect(summary.sales / summary.orders, closeTo(2.165, 1e-9));
  });

  test('best seller comes from today\'s receipts, after refunds', () {
    final summary = TodaySummary.fromReceipts([
      receipt(DateTime(2026, 11, 24, 10), 2.85, [
        ('p1', 'Blue pen', 2, 0.5),
        ('p2', 'Notebook', 1, 1.85),
      ]),
      receipt(DateTime(2026, 11, 24, 11), 1.85, [('p2', 'Notebook', 1, 1.85)]),
      receipt(DateTime(2026, 11, 24, 12), -0.5, [('p1', 'Blue pen', 1, 0.5)], refund: true),
    ], now);
    // Blue pen: 2 sold - 1 returned = 1; Notebook: 2.
    expect(summary.bestSeller, 'Notebook');
    expect(summary.bestSellerUnits, 2);
  });

  test('a tie goes to the product that brought in more money', () {
    final summary = TodaySummary.fromReceipts([
      receipt(DateTime(2026, 11, 24, 10), 4.7, [
        ('p1', 'Blue pen', 2, 0.5),
        ('p2', 'Notebook', 2, 1.85),
      ]),
    ], now);
    expect(summary.bestSeller, 'Notebook');
  });

  test('other days do not count; yesterday is kept for the comparison', () {
    final summary = TodaySummary.fromReceipts([
      receipt(DateTime(2026, 11, 23, 20), 10, [('p1', 'Blue pen', 20, 0.5)]),
      receipt(DateTime(2026, 11, 20, 9), 99, [('p2', 'Notebook', 50, 1.85)]),
    ], now);
    expect(summary.orders, 0);
    expect(summary.sales, 0);
    expect(summary.yesterdaySales, 10);
    expect(summary.bestSeller, isEmpty);
  });

  test('everything refunded leaves no best seller', () {
    final summary = TodaySummary.fromReceipts([
      receipt(DateTime(2026, 11, 24, 10), 0.5, [('p1', 'Blue pen', 1, 0.5)]),
      receipt(DateTime(2026, 11, 24, 11), -0.5, [('p1', 'Blue pen', 1, 0.5)], refund: true),
    ], now);
    expect(summary.bestSeller, isEmpty);
    expect(summary.orders, 1);
  });
}
