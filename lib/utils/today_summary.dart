/// Today's figures for the owner home, from the store's receipts.
///
/// Refund receipts (`type: 'refund'`, negative totals) lower today's sales and give back
/// the units they return, but are not orders. The best seller is the product with the
/// most units sold today after refunds; ties go to the higher revenue, then the name.
class TodaySummary {
  const TodaySummary({
    required this.sales,
    required this.orders,
    required this.yesterdaySales,
    required this.bestSeller,
    required this.bestSellerUnits,
  });

  final double sales;
  final int orders;
  final double yesterdaySales;

  /// Empty when nothing sold today (or everything sold was refunded).
  final String bestSeller;
  final int bestSellerUnits;

  static TodaySummary fromReceipts(
    Iterable<({DateTime date, Map<String, dynamic> data})> receipts,
    DateTime now,
  ) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfYesterday = startOfDay.subtract(const Duration(days: 1));

    var sales = 0.0;
    var orders = 0;
    var yesterday = 0.0;
    final units = <String, int>{};
    final revenue = <String, double>{};
    final names = <String, String>{};

    for (final receipt in receipts) {
      final data = receipt.data;
      final amount = _number(data['total']);
      final isRefund = data['type'] == 'refund';
      if (!receipt.date.isBefore(startOfDay) && receipt.date.isBefore(endOfDay)) {
        sales += amount;
        if (!isRefund) orders++;
        for (final item in data['items'] is List ? data['items'] as List : const []) {
          if (item is! Map) continue;
          final name = (item['name'] ?? '').toString();
          final key = _productKey(item, name);
          if (key.isEmpty) continue;
          final quantity = _number(item['quantity']).round();
          names.putIfAbsent(key, () => name);
          units[key] = (units[key] ?? 0) + (isRefund ? -quantity : quantity);
          if (!isRefund) {
            revenue[key] = (revenue[key] ?? 0) + _number(item['price']) * quantity;
          }
        }
      } else if (!receipt.date.isBefore(startOfYesterday) && receipt.date.isBefore(startOfDay)) {
        yesterday += amount;
      }
    }

    String? best;
    for (final key in units.keys) {
      if ((units[key] ?? 0) <= 0) continue;
      if (best == null || _ranksAbove(key, best, units, revenue, names)) best = key;
    }
    return TodaySummary(
      sales: sales,
      orders: orders,
      yesterdaySales: yesterday,
      bestSeller: best == null ? '' : names[best] ?? '',
      bestSellerUnits: best == null ? 0 : units[best] ?? 0,
    );
  }

  static bool _ranksAbove(
    String a,
    String b,
    Map<String, int> units,
    Map<String, double> revenue,
    Map<String, String> names,
  ) {
    final byUnits = (units[a] ?? 0).compareTo(units[b] ?? 0);
    if (byUnits != 0) return byUnits > 0;
    final byRevenue = (revenue[a] ?? 0).compareTo(revenue[b] ?? 0);
    if (byRevenue != 0) return byRevenue > 0;
    return (names[a] ?? '').compareTo(names[b] ?? '') < 0;
  }

  static String _productKey(Map item, String name) {
    for (final field in const ['productId', 'barcode']) {
      final value = (item[field] ?? '').toString();
      if (value.isNotEmpty) return '$field:$value';
    }
    return name.isEmpty ? '' : 'name:$name';
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}
