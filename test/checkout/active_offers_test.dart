import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/active_offers.dart';

const _offer = ActiveOffer(
  slowId: 'ruler',
  slowName: 'Ruler',
  anchorId: 'pen',
  anchorName: 'Blue pen',
  percent: 20,
);

void main() {
  test('an offer is read only from a valid, active product', () {
    final fields = ActiveOffer.startFields(anchorId: 'pen', anchorName: 'Blue pen', percent: 20);
    final offer = ActiveOffer.fromProduct('ruler', {'name': 'Ruler', ...fields})!;
    expect(offer.anchorId, 'pen');
    expect(offer.percent, 20);
    expect(
      ActiveOffer.fromProduct('ruler', {'name': 'Ruler', ...fields, ...ActiveOffer.stopFields}),
      isNull,
    );
    expect(ActiveOffer.fromProduct('pen', {...fields}), isNull, reason: 'cannot pair with itself');
    expect(ActiveOffer.fromProduct('ruler', {...fields, 'offerPercent': 90}), isNull);
    expect(
      ActiveOffer.startFields(anchorId: 'p', anchorName: 'P', percent: 80)['offerPercent'],
      50,
    );
  });

  test('the discount applies once per complete pair', () {
    final applied = OfferMath.apply(
      [(productId: 'pen', price: 0.5, quantity: 2), (productId: 'ruler', price: 0.4, quantity: 3)],
      [_offer],
    );
    expect(applied.single.pairs, 2);
    expect(applied.single.amount, 0.16); // 2 × 0.400 × 20%
    expect(OfferMath.total(applied), 0.16);
  });

  test('no discount without both products in the cart', () {
    expect(OfferMath.apply([(productId: 'ruler', price: 0.4, quantity: 5)], [_offer]), isEmpty);
    expect(OfferMath.apply([(productId: 'pen', price: 0.5, quantity: 5)], [_offer]), isEmpty);
    expect(OfferMath.apply(const [], [_offer]), isEmpty);
  });

  test('the same cart line is split across repeated scans', () {
    final applied = OfferMath.apply(
      [
        (productId: 'pen', price: 0.5, quantity: 1),
        (productId: 'ruler', price: 0.4, quantity: 1),
        (productId: 'pen', price: 0.5, quantity: 1),
      ],
      [_offer],
    );
    expect(applied.single.pairs, 1);
  });

  test('the safe maximum keeps the offer price at or above cost', () {
    expect(OfferMath.safeMaxPercent(price: 1.0, cost: 0.7), 30);
    expect(OfferMath.safeMaxPercent(price: 1.0, cost: 0.95), 5);
    expect(OfferMath.safeMaxPercent(price: 1.0, cost: 1.2), 0);
    expect(OfferMath.safeMaxPercent(price: 1.0, cost: 0.1), 50, reason: 'capped');
    expect(OfferMath.safeMaxPercent(price: 1.0), 30, reason: 'cautious without a cost');
  });
}
