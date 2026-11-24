import 'dart:math' as math;

/// One product as the planner sees it: stock on hand plus recent units sold.
class BundleCandidate {
  const BundleCandidate({
    required this.key,
    required this.name,
    required this.stock,
    required this.soldRecently,
    this.category = '',
    this.price = 0,
  });

  final String key;
  final String name;
  final int stock;
  final double soldRecently;
  final String category;
  final double price;
}

/// A suggested promotion: buy the popular [anchor], get [slowMover] at a discount.
class BundleOffer {
  const BundleOffer({
    required this.anchor,
    required this.slowMover,
    required this.discountPercent,
    required this.sameCategory,
  });

  final BundleCandidate anchor;
  final BundleCandidate slowMover;
  final int discountPercent;
  final bool sameCategory;

  /// Slow mover's price after the suggested discount, or 0 when no price is stored.
  double get discountedPrice => slowMover.price * (100 - discountPercent) / 100;
}

/// Pairs best sellers with slow-moving stock so popular items help clear inventory.
///
/// Rules, kept deterministic so the owner can see why each offer appears:
/// 1. Best sellers are the products with the most units sold in the period.
/// 2. A slow mover still has stock and sold at most a quarter of the top seller.
/// 3. Each slow mover is paired with an unused best seller from the same category
///    when possible (customers already buying that kind of item), otherwise the
///    strongest remaining best seller.
/// 4. Unsold items get a deeper discount than items that sell a little.
abstract final class BundleOfferPlanner {
  static const int maxOffers = 3;
  static const double slowShareOfTop = 0.25;

  static List<BundleOffer> plan(List<BundleCandidate> products) {
    final bestSellers = products.where((p) => p.soldRecently > 0).toList()
      ..sort((a, b) => b.soldRecently.compareTo(a.soldRecently));
    if (bestSellers.isEmpty) return const [];

    final topSold = bestSellers.first.soldRecently;
    final slowLimit = topSold * slowShareOfTop;
    // Only clearly popular items anchor an offer; a product that barely sells is a slow mover.
    final anchors = bestSellers
        .where((p) => p.soldRecently > slowLimit)
        .take(maxOffers * 2)
        .toList();
    final anchorKeys = anchors.map((p) => p.key).toSet();

    // Most stuck stock first: fewest sales, then the most units waiting on the shelf.
    final slowMovers =
        products
            .where((p) => p.stock > 0 && !anchorKeys.contains(p.key))
            .where((p) => p.soldRecently <= slowLimit)
            .toList()
          ..sort((a, b) {
            final sold = a.soldRecently.compareTo(b.soldRecently);
            return sold != 0 ? sold : b.stock.compareTo(a.stock);
          });

    final offers = <BundleOffer>[];
    final usedAnchors = <String>{};
    for (final slow in slowMovers) {
      if (offers.length >= maxOffers) break;
      final available = anchors.where((a) => !usedAnchors.contains(a.key)).toList();
      if (available.isEmpty) break;

      final category = _normalize(slow.category);
      final match = category.isEmpty
          ? null
          : available.where((a) => _normalize(a.category) == category).firstOrNull;
      final anchor = match ?? available.first;
      usedAnchors.add(anchor.key);

      offers.add(
        BundleOffer(
          anchor: anchor,
          slowMover: slow,
          discountPercent: _discountFor(slow),
          sameCategory: match != null,
        ),
      );
    }
    return offers;
  }

  /// 25% for items that did not sell at all, 15% otherwise; +5% for a large backlog.
  static int _discountFor(BundleCandidate slow) {
    final base = slow.soldRecently <= 0 ? 25 : 15;
    final backlog = slow.stock >= math.max(20, slow.soldRecently * 4) ? 5 : 0;
    return base + backlog;
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
