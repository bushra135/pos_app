import '../models/report_sale.dart';
import 'store_insights.dart';

/// Builds [StoreInsights] input from raw Firestore product and sale maps, so screens
/// that already loaded them (the dashboard) need no extra reads.
abstract final class InsightsFromDocs {
  static List<Recommendation> build({
    required Iterable<({String id, Map<String, dynamic> data})> products,
    required Iterable<Map<String, dynamic>> sales,
    required Map<String, double> costs,
    required DateTime now,
    String Function(double amount)? money,
  }) {
    final from = now.subtract(const Duration(days: StoreInsights.days));
    return StoreInsights.build(
      products: [
        for (final p in products)
          (
            id: p.id,
            name: (p.data['name'] ?? '').toString(),
            category: (p.data['category'] ?? '').toString(),
            stock: (p.data['stock'] as num?)?.toInt() ?? 0,
            price: (p.data['price'] as num?)?.toDouble() ?? 0,
            cost: costs[p.id],
          ),
      ],
      sales: [
        for (final data in sales)
          if (reportDate(data['createdAt']) case final created? when !created.isBefore(from))
            sale(data, created),
      ],
      now: now,
      money: money,
    );
  }

  /// One Firestore sale map as [InsightSale] (lines carry quantity and revenue).
  static InsightSale sale(Map<String, dynamic> data, DateTime created) => (
    createdAt: created,
    total: reportNumber(data, ['total']),
    subtotal: reportNumber(data, ['subtotal', 'total']),
    discount: reportNumber(data, ['discount']),
    isRefund: data['type'] == 'refund',
    cashierName: (data['cashierName'] ?? '').toString(),
    items: [
      for (final item in (data['items'] as List?) ?? const [])
        if (item is Map)
          (
            productId: (item['productId'] ?? '').toString(),
            quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
            revenue:
                ((item['price'] as num?)?.toDouble() ?? 0) *
                ((item['quantity'] as num?)?.toDouble() ?? 0),
          ),
    ],
  );
}
