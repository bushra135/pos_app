import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/offer_tips.dart';

TipProduct _p(
  String name, {
  int stock = 10,
  double sold = 0,
  double price = 1,
  double? cost,
  int min = 5,
}) =>
    (id: name, name: name, stock: stock, price: price, cost: cost, minStock: min, soldUnits: sold);

void main() {
  test('unsold stock, a low best seller and thin margins each get a tip', () {
    final tips = OfferTips.build(
      products: [
        _p('Pen', stock: 3, sold: 40, cost: 0.6),
        _p('Glue', stock: 12, sold: 0, cost: 0.5),
        _p('Tape', stock: 5, sold: 2, price: 1, cost: 0.9),
      ],
      sales: const [],
    );
    final kinds = tips.map((t) => t.kind).toList();
    expect(kinds, containsAll(['clearance', 'restock', 'margin']));
    expect(tips.firstWhere((t) => t.kind == 'clearance').args['n'], 1);
    expect(tips.firstWhere((t) => t.kind == 'margin').args['names'], 'Tape');
    expect(kinds, isNot(contains('costs')), reason: 'costs are filled in');
  });

  test('the quietest weekday and a basket target come from sales', () {
    final monday = DateTime(2026, 11, 23);
    final sales = [
      for (var day = 0; day < 7; day++)
        for (var i = 0; i < (day == 3 ? 1 : 4); i++)
          (createdAt: monday.add(Duration(days: day)), total: 2.0, offerDiscount: 0.0),
    ];
    final tips = OfferTips.build(products: [_p('Pen', sold: 3)], sales: sales);
    expect(tips.firstWhere((t) => t.kind == 'slowDay').args['day'], 'Thursday');
    final basket = tips.firstWhere((t) => t.kind == 'basket');
    expect(basket.args['average'], 'BD 2.000');
    expect(basket.args['target'], 'BD 3.000');
    expect(tips.map((t) => t.kind), contains('costs'), reason: 'no cost prices yet');
  });

  test('used offers are reported, and no tips without data', () {
    final tips = OfferTips.build(
      products: const [],
      sales: [(createdAt: DateTime(2026, 11, 25), total: 3, offerDiscount: 0.2)],
    );
    expect(tips.single.kind, 'offersWorking');
    expect(OfferTips.build(products: const [], sales: const []), isEmpty);
  });
}
