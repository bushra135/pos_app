import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/bundle_offer_planner.dart';

BundleCandidate _p(
  String name, {
  required double sold,
  int stock = 10,
  String category = '',
  double price = 0,
}) => BundleCandidate(
  key: name,
  name: name,
  stock: stock,
  soldRecently: sold,
  category: category,
  price: price,
);

void main() {
  test('pairs the best seller with unsold stock and a deeper discount', () {
    final offers = BundleOfferPlanner.plan([
      _p('Pen', sold: 40),
      _p('Notebook', sold: 0, stock: 12, price: 2),
      _p('Ruler', sold: 25),
    ]);

    expect(offers, hasLength(1));
    expect(offers.single.anchor.name, 'Pen');
    expect(offers.single.slowMover.name, 'Notebook');
    expect(offers.single.discountPercent, 25);
    expect(offers.single.discountedPrice, closeTo(1.5, 1e-9));
  });

  test('prefers a best seller from the same category', () {
    final offers = BundleOfferPlanner.plan([
      _p('Pen', sold: 40, category: 'Writing'),
      _p('Juice', sold: 30, category: 'Drinks'),
      _p('Water', sold: 1, category: 'drinks '),
    ]);

    expect(offers.single.anchor.name, 'Juice');
    expect(offers.single.sameCategory, isTrue);
    expect(offers.single.discountPercent, 15);
  });

  test('ignores slow items without stock and items selling close to the top', () {
    final offers = BundleOfferPlanner.plan([
      _p('Pen', sold: 40),
      _p('Eraser', sold: 0, stock: 0),
      _p('Marker', sold: 30),
    ]);

    expect(offers, isEmpty);
  });

  test('suggests no offers before any sales exist', () {
    expect(BundleOfferPlanner.plan([_p('Pen', sold: 0), _p('Book', sold: 0)]), isEmpty);
  });

  test('uses each best seller once, limits offers, and adds a backlog discount', () {
    final offers = BundleOfferPlanner.plan([
      _p('A', sold: 100),
      _p('B', sold: 90),
      _p('C', sold: 80),
      _p('D', sold: 70),
      _p('S1', sold: 0, stock: 50),
      _p('S2', sold: 2, stock: 5),
      _p('S3', sold: 1, stock: 8),
      _p('S4', sold: 3, stock: 9),
    ]);

    expect(offers, hasLength(BundleOfferPlanner.maxOffers));
    expect(offers.map((o) => o.anchor.name).toSet(), hasLength(3));
    expect(offers.map((o) => o.slowMover.name), ['S1', 'S3', 'S2']);
    expect(offers.first.discountPercent, 30);
  });
}
