/// Checks a saved receipt for signs of tampering that security rules cannot catch line by
/// line (they cannot loop over items). Used to flag receipts for the owner to review.
///
/// The rules already guarantee total = subtotal - discount, a sane discount and a real
/// sale time; this adds the per-line checks.
abstract final class ReceiptAudit {
  static const linesDontAddUp = 'lines_dont_add_up';
  static const badQuantity = 'bad_quantity';
  static const belowCatalogPrice = 'below_catalog_price';
  static const lateSync = 'late_sync';

  /// Owner-facing explanation of each issue (English source text for `.tr`).
  static const messages = {
    linesDontAddUp: 'Item lines do not add up to the receipt subtotal',
    badQuantity: 'A line has a zero, negative or fractional quantity',
    belowCatalogPrice: 'An item was sold below its current catalogue price',
    lateSync: 'Saved more than a day after the sale (offline or back-dated)',
  };

  /// Issues found on [sale]; empty when it looks normal. Refunds are not checked.
  /// [catalogPrices] maps product id to the current selling price.
  static List<String> issues(
    Map<String, dynamic> sale, {
    Map<String, double> catalogPrices = const {},
  }) {
    if (sale['type'] == 'refund') return const [];
    final items = sale['items'] is List ? sale['items'] as List : const [];
    final found = <String>[];
    var sum = 0.0;
    var quantityProblem = false;
    var belowCatalog = false;
    for (final item in items) {
      if (item is! Map) continue;
      final price = _number(item['price']);
      final quantity = _number(item['quantity']);
      if (quantity <= 0 || quantity != quantity.roundToDouble()) quantityProblem = true;
      sum += price * quantity;
      final catalog = catalogPrices[(item['productId'] ?? '').toString()];
      if (catalog != null && price < catalog - 0.0005) belowCatalog = true;
    }
    final subtotal = sale['subtotal'];
    if (subtotal is num && (sum - subtotal).abs() > 0.0005) found.add(linesDontAddUp);
    if (quantityProblem) found.add(badQuantity);
    if (belowCatalog) found.add(belowCatalogPrice);
    final created = _date(sale['createdAt']);
    final synced = _date(sale['syncedAt']);
    if (created != null && synced != null && synced.difference(created) > const Duration(days: 1)) {
      found.add(lateSync);
    }
    return found;
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  /// Firestore Timestamps expose toDate(); ISO strings and DateTimes are accepted too.
  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic)?.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
