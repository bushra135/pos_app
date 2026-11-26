import '../app/money.dart';

/// Bundle offers the owner switched on: "buy [anchorName], get [slowName] [percent]% off".
///
/// An offer is stored on the slow-moving product itself (offerActive, offerWithId,
/// offerWithName, offerPercent). Owners may write any product field; cashiers cannot
/// touch these fields, so only the owner starts or stops an offer.
class ActiveOffer {
  const ActiveOffer({
    required this.slowId,
    required this.slowName,
    required this.anchorId,
    required this.anchorName,
    required this.percent,
  });

  final String slowId;
  final String slowName;
  final String anchorId;
  final String anchorName;
  final int percent;

  static const minPercent = 5;
  static const maxPercent = 50;

  /// Reads the offer saved on a product, or null when there is no active, valid offer.
  static ActiveOffer? fromProduct(String id, Map<String, dynamic> data) {
    if (data['offerActive'] != true) return null;
    final anchorId = (data['offerWithId'] ?? '').toString();
    final percent = (data['offerPercent'] as num?)?.round() ?? 0;
    if (anchorId.isEmpty || anchorId == id || percent < minPercent || percent > maxPercent) {
      return null;
    }
    return ActiveOffer(
      slowId: id,
      slowName: (data['name'] ?? '').toString(),
      anchorId: anchorId,
      anchorName: (data['offerWithName'] ?? '').toString(),
      percent: percent,
    );
  }

  /// Fields written on the slow product to start this offer.
  static Map<String, dynamic> startFields({
    required String anchorId,
    required String anchorName,
    required int percent,
  }) => {
    'offerActive': true,
    'offerWithId': anchorId,
    'offerWithName': anchorName,
    'offerPercent': percent.clamp(minPercent, maxPercent),
  };

  static const stopFields = {'offerActive': false};
}

/// One cart line as the offer calculator sees it.
typedef OfferCartLine = ({String productId, double price, int quantity});

/// An offer that applied to this cart.
typedef AppliedOffer = ({ActiveOffer offer, int pairs, double amount});

/// Applies running bundle offers to a cart.
abstract final class OfferMath {
  /// Discount for every complete pair in the cart: each anchor unit unlocks one slow
  /// unit at the offer price. Lines with a missing anchor get nothing.
  static List<AppliedOffer> apply(List<OfferCartLine> cart, List<ActiveOffer> offers) {
    final quantity = <String, int>{};
    final price = <String, double>{};
    for (final line in cart) {
      if (line.productId.isEmpty || line.quantity <= 0) continue;
      quantity[line.productId] = (quantity[line.productId] ?? 0) + line.quantity;
      price[line.productId] = line.price;
    }
    final applied = <AppliedOffer>[];
    final used = <String>{};
    for (final offer in offers) {
      // One offer per slow product, and a product discounted once.
      if (!used.add(offer.slowId)) continue;
      final pairs = [
        quantity[offer.slowId] ?? 0,
        quantity[offer.anchorId] ?? 0,
      ].reduce((a, b) => a < b ? a : b);
      if (pairs <= 0) continue;
      final amount = Money.round(pairs * (price[offer.slowId] ?? 0) * offer.percent / 100);
      if (amount > 0) applied.add((offer: offer, pairs: pairs, amount: amount));
    }
    return applied;
  }

  static double total(List<AppliedOffer> applied) =>
      Money.round(applied.fold(0.0, (sum, a) => sum + a.amount));

  /// Largest whole-percent discount that still sells at or above cost (capped at 50%).
  /// Without a cost the cap is 30%, a cautious default.
  static int safeMaxPercent({required double price, double? cost}) {
    if (price <= 0) return 0;
    if (cost == null || cost <= 0) return 30;
    final margin = ((price - cost) / price * 100).floor();
    return margin.clamp(0, ActiveOffer.maxPercent);
  }
}
