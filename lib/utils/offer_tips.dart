/// Practical promotion advice computed from the store's own last 30 days.
///
/// Every tip is plain arithmetic on the owner's data, so it can be explained and
/// checked: no guesses, and nothing is suggested when the data does not support it.
class OfferTip {
  const OfferTip(this.kind, this.text, [this.args = const {}]);

  /// clearance, restock, slowDay, basket, margin, costs, offersWorking
  final String kind;

  /// English source text for `.trArgs`.
  final String text;
  final Map<String, Object> args;
}

typedef TipProduct = ({
  String id,
  String name,
  int stock,
  double price,
  double? cost,
  int minStock,
  double soldUnits,
});

typedef TipSale = ({DateTime createdAt, double total, double offerDiscount});

abstract final class OfferTips {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static List<OfferTip> build({
    required List<TipProduct> products,
    required List<TipSale> sales,
    String Function(double amount)? money,
  }) {
    final fmt = money ?? (double v) => 'BD ${v.toStringAsFixed(3)}';
    final tips = <OfferTip>[];

    // 1. Stock that did not sell at all: money sitting on the shelf.
    final dead = products.where((p) => p.stock > 0 && p.soldUnits <= 0).toList();
    if (dead.isNotEmpty) {
      final tiedUp = dead.fold(0.0, (sum, p) => sum + p.stock * (p.cost ?? p.price));
      tips.add(
        OfferTip(
          'clearance',
          '{n} products have not sold in 30 days ({amount} on the shelf). Pair them with a best seller or clear them at 20–30% off.',
          {'n': dead.length, 'amount': fmt(tiedUp)},
        ),
      );
    }

    // 2. Never discount a best seller that is about to run out: restock it instead.
    final sellers = products.where((p) => p.soldUnits > 0).toList()
      ..sort((a, b) => b.soldUnits.compareTo(a.soldUnits));
    if (sellers.isNotEmpty) {
      final top = sellers.first;
      if (top.stock <= (top.minStock > 0 ? top.minStock : 5)) {
        tips.add(
          OfferTip(
            'restock',
            '{name} is your best seller and only {n} are left. Restock it before using it in an offer, and do not discount it.',
            {'name': top.name, 'n': top.stock},
          ),
        );
      }
    }

    // 3. The quietest weekday is the best day for a promotion.
    if (sales.length >= 7) {
      final byDay = List<double>.filled(7, 0);
      for (final sale in sales) {
        byDay[sale.createdAt.weekday - 1] += sale.total;
      }
      final busiest = byDay.reduce((a, b) => a > b ? a : b);
      var slowest = 0;
      for (var i = 1; i < 7; i++) {
        if (byDay[i] < byDay[slowest]) slowest = i;
      }
      if (busiest > 0 && byDay[slowest] < busiest * 0.6) {
        tips.add(
          OfferTip(
            'slowDay',
            '{day} is your quietest day. Run offers on {day}s to bring customers in.',
            {'day': _weekdays[slowest]},
          ),
        );
      }
    }

    // 4. Lift the average receipt with a spend threshold just above it.
    if (sales.length >= 5) {
      final average = sales.fold(0.0, (sum, s) => sum + s.total) / sales.length;
      if (average > 0) {
        final target = (average * 1.3 * 2).ceil() / 2; // rounded up to 0.500 BD
        tips.add(
          OfferTip(
            'basket',
            'Your average receipt is {average}. Try 5% off receipts above {target} to raise it.',
            {'average': fmt(average), 'target': fmt(target)},
          ),
        );
      }
    }

    // 5. Thin margins: discounting these sells at a loss.
    final thin =
        products
            .where((p) => p.cost != null && p.cost! > 0 && p.price > 0)
            .where((p) => (p.price - p.cost!) / p.price < 0.15)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (thin.isNotEmpty) {
      tips.add(
        OfferTip('margin', 'Avoid discounts on {names}: the profit on them is under 15%.', {
          'names': thin.take(3).map((p) => p.name).join('، '),
        }),
      );
    }

    // 6. Without cost prices the safe discount cannot be calculated.
    final withoutCost = products.where((p) => p.cost == null || p.cost! <= 0).length;
    if (products.isNotEmpty && withoutCost * 2 >= products.length) {
      tips.add(
        const OfferTip(
          'costs',
          'Add cost prices to your products to see the largest discount you can give without a loss.',
        ),
      );
    }

    // 7. How much the active offers gave away, so the owner can judge them.
    final offerSales = sales.where((s) => s.offerDiscount > 0).toList();
    if (offerSales.isNotEmpty) {
      tips.add(
        OfferTip(
          'offersWorking',
          'Bundle offers were used on {n} receipts ({amount} in discounts). Stop an offer once its slow product starts selling.',
          {
            'n': offerSales.length,
            'amount': fmt(offerSales.fold(0.0, (sum, s) => sum + s.offerDiscount)),
          },
        ),
      );
    }
    return tips;
  }
}
