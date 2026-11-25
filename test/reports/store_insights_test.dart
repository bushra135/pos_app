import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/store_insights.dart';

final _now = DateTime(2026, 11, 25, 18);

InsightProduct _p(
  String id, {
  int stock = 20,
  double price = 1,
  double? cost,
  String category = '',
}) => (id: id, name: id, category: category, stock: stock, price: price, cost: cost);

InsightSale _sale(
  int daysAgo,
  Map<String, double> units, {
  double total = 2,
  int hour = 10,
  String cashier = 'Noora',
  bool refund = false,
  double discount = 0,
}) => (
  createdAt: DateTime(_now.year, _now.month, _now.day - daysAgo, hour),
  total: total,
  subtotal: total + discount,
  discount: discount,
  isRefund: refund,
  cashierName: cashier,
  items: [for (final e in units.entries) (productId: e.key, quantity: e.value, revenue: e.value)],
);

void main() {
  test('stock that runs out soon is reordered, out of stock first', () {
    final recs = StoreInsights.build(
      products: [_p('Pen', stock: 4), _p('Glue', stock: 0), _p('Tape', stock: 100)],
      sales: [
        for (var d = 0; d < 30; d++) _sale(d, {'Pen': 1, 'Glue': 1, 'Tape': 1}),
      ],
      now: _now,
    );
    expect(recs.first.kind, 'outOfStock');
    expect(recs.first.args['name'], 'Glue');
    final reorder = recs.firstWhere((r) => r.kind == 'reorder');
    expect(reorder.args['name'], 'Pen');
    expect(reorder.args['qty'], 10); // 14 days × 1/day − 4 in stock
    expect(reorder.priority, 1, reason: '4 days left');
    expect(recs.where((r) => r.args['name'] == 'Tape'), isEmpty, reason: '100 days of stock');
  });

  test('weekly trend, peak hour, thin margin, refunds and discounts', () {
    final sales = [
      for (var d = 8; d < 14; d++) _sale(d, {'Pen': 1}, total: 2),
      for (var d = 0; d < 7; d++) _sale(d, {'Pen': 2}, total: 4, hour: 17, discount: 1),
      _sale(1, {}, total: 5, refund: true),
    ];
    final recs = StoreInsights.build(
      products: [_p('Pen', price: 1, cost: 0.9)],
      sales: sales,
      now: _now,
    );
    final kinds = recs.map((r) => r.kind).toSet();
    expect(kinds, containsAll(['trendUp', 'peakHour', 'priceUp', 'refunds', 'discounts']));
    expect(recs.firstWhere((r) => r.kind == 'priceUp').args['price'], 'BD 1.200');
    expect(recs.firstWhere((r) => r.kind == 'peakHour').args['from'], '17:00');
  });

  test('top category and top cashier need at least two to compare', () {
    final recs = StoreInsights.build(
      products: [
        _p('Pen', category: 'Stationery'),
        _p('Juice', category: 'Drinks'),
      ],
      sales: [
        _sale(1, {'Pen': 8}, total: 8, cashier: 'Noora'),
        _sale(2, {'Juice': 2}, total: 2, cashier: 'Sara'),
      ],
      now: _now,
    );
    expect(recs.firstWhere((r) => r.kind == 'category').args['category'], 'Stationery');
    expect(recs.firstWhere((r) => r.kind == 'cashier').args['name'], 'Noora');
  });

  test('no sales, no recommendations', () {
    expect(StoreInsights.build(products: [_p('Pen')], sales: const [], now: _now), isEmpty);
  });
}
