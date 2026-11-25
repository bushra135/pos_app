/// Recommendations for the owner, computed from the store's last 30 days.
///
/// Every rule is plain arithmetic on the owner's own data and says why it fired, so a
/// recommendation can always be checked. Nothing is suggested without enough data.
class Recommendation {
  const Recommendation(this.kind, this.priority, this.text, [this.args = const {}]);

  /// reorder, outOfStock, trendUp, trendDown, peakHour, priceUp, refunds, discounts,
  /// category, cashier
  final String kind;

  /// 0 urgent, 1 worth doing, 2 good to know.
  final int priority;

  /// English source text for `.trArgs`.
  final String text;
  final Map<String, Object> args;
}

typedef InsightProduct = ({
  String id,
  String name,
  String category,
  int stock,
  double price,
  double? cost,
});

typedef InsightLine = ({String productId, double quantity, double revenue});

typedef InsightSale = ({
  DateTime createdAt,
  double total,
  double subtotal,
  double discount,
  bool isRefund,
  String cashierName,
  List<InsightLine> items,
});

abstract final class StoreInsights {
  static const days = 30;

  static List<Recommendation> build({
    required List<InsightProduct> products,
    required List<InsightSale> sales,
    required DateTime now,
    String Function(double amount)? money,
  }) {
    final fmt = money ?? (double v) => 'BD ${v.toStringAsFixed(3)}';
    final from = now.subtract(const Duration(days: days));
    final recent = sales.where((s) => !s.createdAt.isBefore(from) && !s.createdAt.isAfter(now));
    final sold = recent.where((s) => !s.isRefund).toList();
    final refunds = recent.where((s) => s.isRefund).toList();
    final recs = <Recommendation>[];

    final units = <String, double>{};
    final revenue = <String, double>{};
    for (final sale in sold) {
      for (final line in sale.items) {
        units[line.productId] = (units[line.productId] ?? 0) + line.quantity;
        revenue[line.productId] = (revenue[line.productId] ?? 0) + line.revenue;
      }
    }

    // 1. Stock running out at the current selling pace: order before it is gone.
    final reorders = <({InsightProduct p, double daysLeft, int order})>[];
    for (final p in products) {
      final perDay = (units[p.id] ?? 0) / days;
      if (perDay <= 0) continue;
      if (p.stock <= 0) {
        recs.add(
          Recommendation(
            'outOfStock',
            0,
            '{name} is out of stock but sold {n} in 30 days. Every day without it is lost sales; restock it now.',
            {'name': p.name, 'n': (units[p.id] ?? 0).toStringAsFixed(0)},
          ),
        );
        continue;
      }
      final daysLeft = p.stock / perDay;
      if (daysLeft < 7) {
        // Enough for two weeks of sales.
        final order = (perDay * 14 - p.stock).ceil();
        if (order > 0) reorders.add((p: p, daysLeft: daysLeft, order: order));
      }
    }
    reorders.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    for (final r in reorders.take(5)) {
      recs.add(
        Recommendation(
          'reorder',
          r.daysLeft < 3 ? 0 : 1,
          'Order {qty} of {name}: at your selling pace it runs out in about {days} days.',
          {'qty': r.order, 'name': r.p.name, 'days': r.daysLeft.ceil()},
        ),
      );
    }

    // 2. This week against the week before.
    double net(DateTime start, DateTime end) => recent
        .where((s) => !s.createdAt.isBefore(start) && s.createdAt.isBefore(end))
        .fold(0.0, (sum, s) => sum + (s.isRefund ? -s.total.abs() : s.total));
    final weekStart = now.subtract(const Duration(days: 7));
    final thisWeek = net(weekStart, now.add(const Duration(seconds: 1)));
    final lastWeek = net(now.subtract(const Duration(days: 14)), weekStart);
    if (lastWeek > 0 && thisWeek > 0) {
      final change = ((thisWeek - lastWeek) / lastWeek * 100).round();
      if (change >= 10) {
        recs.add(
          Recommendation(
            'trendUp',
            2,
            'Sales are up {pct}% on last week ({now} against {before}). Keep your best sellers well stocked.',
            {'pct': change, 'now': fmt(thisWeek), 'before': fmt(lastWeek)},
          ),
        );
      } else if (change <= -10) {
        recs.add(
          Recommendation(
            'trendDown',
            1,
            'Sales are down {pct}% on last week ({now} against {before}). A bundle offer on slow items can bring customers back.',
            {'pct': -change, 'now': fmt(thisWeek), 'before': fmt(lastWeek)},
          ),
        );
      }
    }

    // 3. Busiest hour: when a cashier must be on the counter.
    if (sold.length >= 10) {
      final byHour = List<int>.filled(24, 0);
      for (final sale in sold) {
        byHour[sale.createdAt.hour]++;
      }
      var peak = 0;
      for (var h = 1; h < 24; h++) {
        if (byHour[h] > byHour[peak]) peak = h;
      }
      final share = (byHour[peak] / sold.length * 100).round();
      if (share >= 15) {
        String hour(int h) => '${h.toString().padLeft(2, '0')}:00';
        recs.add(
          Recommendation(
            'peakHour',
            2,
            '{pct}% of your receipts are between {from} and {to}. Keep a cashier on the counter then and restock before it.',
            {'pct': share, 'from': hour(peak), 'to': hour((peak + 1) % 24)},
          ),
        );
      }
    }

    // 4. Popular products with a thin margin: a small price rise adds real profit.
    final byUnits = products.where((p) => (units[p.id] ?? 0) > 0).toList()
      ..sort((a, b) => (units[b.id] ?? 0).compareTo(units[a.id] ?? 0));
    for (final p in byUnits.take(5)) {
      final cost = p.cost;
      if (cost == null || cost <= 0 || p.price <= 0) continue;
      final margin = (p.price - cost) / p.price;
      if (margin < 0.2) {
        recs.add(
          Recommendation(
            'priceUp',
            1,
            '{name} sells well but keeps only {pct}% profit. A price of {price} would give 25% and still be competitive.',
            {
              'name': p.name,
              'pct': (margin * 100).round(),
              'price': fmt(((cost / 0.75) * 20).ceil() / 20), // rounded up to 0.050
            },
          ),
        );
        break;
      }
    }

    // 5. Money leaking through refunds or discounts.
    final gross = sold.fold(0.0, (sum, s) => sum + s.subtotal);
    if (gross > 0) {
      final refunded = refunds.fold(0.0, (sum, s) => sum + s.total.abs());
      final refundShare = refunded / gross * 100;
      if (refundShare >= 5) {
        recs.add(
          Recommendation(
            'refunds',
            1,
            'Refunds took {pct}% of sales ({amount}). Check which products come back and why.',
            {'pct': refundShare.round(), 'amount': fmt(refunded)},
          ),
        );
      }
      final discounted = sold.fold(0.0, (sum, s) => sum + s.discount);
      final discountShare = discounted / gross * 100;
      if (discountShare >= 10) {
        recs.add(
          Recommendation(
            'discounts',
            1,
            'Discounts took {pct}% of sales ({amount}). Make sure each one brings extra sales.',
            {'pct': discountShare.round(), 'amount': fmt(discounted)},
          ),
        );
      }
    }

    // 6. The category earning the most: give it the best shelf space.
    final byCategory = <String, double>{};
    for (final p in products) {
      if (p.category.trim().isEmpty) continue;
      byCategory[p.category] = (byCategory[p.category] ?? 0) + (revenue[p.id] ?? 0);
    }
    final categoryTotal = byCategory.values.fold(0.0, (a, b) => a + b);
    if (byCategory.length >= 2 && categoryTotal > 0) {
      final top = byCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
      recs.add(
        Recommendation(
          'category',
          2,
          '{category} brings {pct}% of your sales. Give it the best shelf space and never let it run out.',
          {'category': top.key, 'pct': (top.value / categoryTotal * 100).round()},
        ),
      );
    }

    // 7. The cashier with the most sales, when there is more than one.
    final byCashier = <String, double>{};
    for (final sale in sold) {
      final name = sale.cashierName.trim();
      if (name.isEmpty) continue;
      byCashier[name] = (byCashier[name] ?? 0) + sale.total;
    }
    if (byCashier.length >= 2) {
      final top = byCashier.entries.reduce((a, b) => a.value >= b.value ? a : b);
      recs.add(
        Recommendation(
          'cashier',
          2,
          '{name} made the most sales this month ({amount}). Thank them, and let them show the others how.',
          {'name': top.key, 'amount': fmt(top.value)},
        ),
      );
    }

    recs.sort((a, b) => a.priority.compareTo(b.priority));
    return recs;
  }
}
