import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../products/products_screen.dart';
import '../owner/offers_screen.dart';
import '../../services/product_costs.dart';
import '../../services/sales_query.dart';
import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/report_sale.dart';
import '../../models/sale_record.dart';
import '../closing/end_of_day_screen.dart';
import 'sales_history_screen.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';
import '../../utils/insights_from_docs.dart';
import '../../utils/store_insights.dart';
import '../../widgets/motion.dart';
import '../../widgets/receipt_card.dart';

/// Dashboard periods use local dates; history filters live on their separate route.
enum ReportPeriod { today, week, month, year }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.returnToAssistant = false,
    this.firestore,
    this.currentUserId,
  });
  final bool returnToAssistant;
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? get _uid => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  static const _requestTimeout = Duration(seconds: 10);

  ReportPeriod _selectedPeriod = ReportPeriod.week;

  _DashboardSection _section = _DashboardSection.sales;

  bool _isLoading = true;
  bool _canOpenSalesHistory = false;
  String? _errorMessage;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _salesDocuments = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _productDocuments = [];

  /// Owner-only cost prices (product id -> cost); cashier sales carry no cost.
  Map<String, double> _costs = const {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  // Load records for the signed-in store.
  Future<void> _loadReports() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final uid = _uid;
      if (uid == null) throw Exception('No user');

      final userDoc = await _firestore.collection('users').doc(uid).get().timeout(_requestTimeout);
      final storeCode = (userDoc.data()?['storeCode'] ?? '').toString().trim();

      if (storeCode.isEmpty) throw Exception('Store code not found');

      // The longest period is a year; last year is kept for period comparisons.
      final now = DateTime.now();
      final salesDocs = await SalesQuery.since(
        _firestore,
        storeCode: storeCode,
        from: DateTime(now.year - 1),
        timeout: _requestTimeout,
      );

      final productsSnapshot = await _firestore
          .collection('products')
          .where('storeCode', isEqualTo: storeCode)
          .get()
          .timeout(_requestTimeout);

      final storeProducts = productsSnapshot.docs.where((doc) {
        final productStoreCode = (doc.data()['storeCode'] ?? '').toString().trim();
        return productStoreCode == storeCode;
      }).toList();

      final isOwner = userDoc.data()?['role'] == 'owner';
      var costs = const <String, double>{};
      if (isOwner) {
        await ProductCosts.migrateLegacy(_firestore, storeCode, storeProducts);
        costs = await ProductCosts.load(_firestore, storeCode);
      }

      if (!mounted) return;

      setState(() {
        _canOpenSalesHistory = isOwner;
        _salesDocuments = salesDocs;
        _productDocuments = storeProducts;
        _costs = costs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Reports error: $e');

      if (!mounted) return;

      setState(() {
        _errorMessage = 'Failed to load reports';
        _isLoading = false;
      });
    }
  }

  // Aggregate the selected period into chart and summary data.
  _ReportsData _calculateReports() {
    final range = _periodRange(_selectedPeriod);
    final buckets = _emptyBuckets(_selectedPeriod);

    double grossSales = 0;
    double netSales = 0;
    double discounts = 0;
    double refunds = 0;
    int ordersCount = 0;

    final paymentMethods = <String, double>{};
    final productSales = <String, _ProductSales>{};

    // Profit, VAT, timing and category breakdowns for the selected period.
    double costedRevenue = 0, costOfGoods = 0, uncostedRevenue = 0, vatCollected = 0;
    final hourly = List<double>.filled(24, 0);
    final weekday = List<double>.filled(7, 0); // Sunday first
    final categorySales = <String, double>{};
    final categoryByKey = <String, String>{};
    double stockRetailValue = 0, stockCostValue = 0;
    int uncostedProducts = 0;
    for (final doc in _productDocuments) {
      final data = doc.data();
      final name = (data['name'] ?? data['productName'] ?? 'Unknown product').toString();
      final category = (data['category'] ?? '').toString().trim();
      categoryByKey[reportProductKey(data, name)] = category.isEmpty ? 'Uncategorized' : category;
      final stock = reportNumber(data, ['stock', 'quantity']);
      final price = reportNumber(data, ['price']);
      final cost = _costs[doc.id] ?? reportNumber(data, ['cost']);
      if (stock > 0) {
        stockRetailValue += stock * price;
        if (cost > 0) {
          stockCostValue += stock * cost;
        } else {
          uncostedProducts++;
        }
      }
    }

    // Same-length window right before the selected one, for the % change.
    final previousStart = range.start.subtract(range.end.difference(range.start));
    double previousNet = 0;
    int previousOrders = 0;

    // Seed inventory first so unsold products appear among the least-selling items.
    for (final doc in _productDocuments) {
      final data = doc.data();
      final name = (data['name'] ?? data['productName'] ?? 'Unknown Product').toString();

      final key = reportProductKey(data, name);
      productSales[key] = _ProductSales(name: name);
    }

    for (final doc in _salesDocuments) {
      final saleData = doc.data();
      final createdAt = reportDate(saleData['createdAt']);

      if (createdAt == null) continue;
      if (_inRange(createdAt, previousStart, range.start)) {
        final previous = ReportSale.fromMap(saleData);
        previousNet += previous.netSales;
        if (!previous.isRefund) previousOrders++;
        continue;
      }
      if (!_inRange(createdAt, range.start, range.end)) continue;

      final sale = ReportSale.fromMap(saleData);
      // Refund documents carry negative VAT, so they reduce what is owed.
      vatCollected += reportNumber(saleData, ['tax', 'vat', 'vatAmount']);
      if (!sale.isRefund) {
        hourly[createdAt.hour] += sale.netSales;
        weekday[createdAt.weekday % 7] += sale.netSales;
      }
      // Share of the sale actually paid, so discounts reduce each line's revenue.
      final paidShare = sale.grossSales > 0 ? sale.netSales / sale.grossSales : 1.0;

      grossSales += sale.grossSales;
      netSales += sale.netSales;
      discounts += sale.discount;
      refunds += sale.refund;

      // Refunds affect net sales but do not count as orders or new product sales.
      if (!sale.isRefund) ordersCount++;

      final bucketIndex = _bucketIndex(createdAt, _selectedPeriod);
      if (bucketIndex >= 0 && bucketIndex < buckets.values.length) {
        buckets.values[bucketIndex] += sale.netSales;
      }

      if (!sale.isRefund) {
        paymentMethods[sale.paymentMethod] =
            (paymentMethods[sale.paymentMethod] ?? 0) + sale.netSales;

        for (final rawItem in sale.items) {
          final item = ReportSaleItem.fromMap(rawItem);
          final product = productSales[item.key] ?? _ProductSales(name: item.name);
          product.quantity += item.quantity;
          product.revenue += item.subtotal;
          productSales[item.key] = product;

          final paid = item.subtotal * paidShare;
          // Sales record a cost only when the seller could see it (the owner); otherwise
          // the owner's current cost price for that product is used.
          final lineCost = reportNumber(rawItem, ['cost', 'unitCost']);
          final unitCost = lineCost > 0
              ? lineCost
              : _costs[(rawItem['productId'] ?? '').toString()] ?? 0;
          if (unitCost > 0) {
            costedRevenue += paid;
            costOfGoods += unitCost * item.quantity;
          } else {
            uncostedRevenue += paid;
          }
          final category =
              categoryByKey[item.key] ??
              ((rawItem['category'] ?? '').toString().trim().isEmpty
                  ? 'Uncategorized'
                  : rawItem['category'].toString().trim());
          categorySales[category] = (categorySales[category] ?? 0) + paid;
        }
      }
    }

    paymentMethods.removeWhere((key, value) => value <= 0);

    final topSelling = productSales.values.toList()
      ..sort((a, b) {
        final quantityCompare = b.quantity.compareTo(a.quantity);
        if (quantityCompare != 0) return quantityCompare;
        return b.revenue.compareTo(a.revenue);
      });

    final leastSelling = productSales.values.toList()
      ..sort((a, b) {
        final quantityCompare = a.quantity.compareTo(b.quantity);
        if (quantityCompare != 0) return quantityCompare;
        return a.revenue.compareTo(b.revenue);
      });

    final topRevenue = productSales.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    final paymentReports =
        paymentMethods.entries.map((entry) => _PaymentReport(entry.key, entry.value)).toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return _ReportsData(
      grossSales: grossSales,
      netSales: netSales,
      discounts: discounts,
      refunds: refunds,
      ordersCount: ordersCount,
      averageOrder: ordersCount == 0 ? 0 : netSales / ordersCount,
      chartLabels: buckets.labels,
      chartValues: buckets.values,
      topSelling: topSelling.take(10).toList(),
      leastSelling: leastSelling.take(10).toList(),
      topRevenue: topRevenue.take(10).toList(),
      paymentMethods: paymentReports,
      costedRevenue: costedRevenue,
      costOfGoods: costOfGoods,
      uncostedRevenue: uncostedRevenue,
      vatCollected: vatCollected,
      hourly: hourly,
      weekday: weekday,
      categories: (categorySales.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((entry) => _PaymentReport(entry.key, entry.value))
          .toList(),
      previousNet: previousNet,
      previousOrders: previousOrders,
      stockRetailValue: stockRetailValue,
      stockCostValue: stockCostValue,
      uncostedProducts: uncostedProducts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _calculateReports();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.returnToAssistant
          ? AppBar(
              leading: IconButton(
                tooltip: 'Back to assistant'.tr,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text('Back to assistant'.tr),
            )
          : null,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadReports)
            : RefreshIndicator(
                onRefresh: _loadReports,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      if (_canOpenSalesHistory) ...[
                        _buildOwnerShortcuts(),
                        const SizedBox(height: 16),
                      ],
                      _buildPeriodSelector(),
                      const SizedBox(height: 16),
                      _buildHeroCard(data),
                      const SizedBox(height: 18),
                      _buildSectionTabs(),
                      const SizedBox(height: 16),
                      // One topic at a time instead of every report stacked in one long page.
                      ...switch (_section) {
                        _DashboardSection.sales => [
                          _buildTrendChart(data),
                          const SizedBox(height: 16),
                          _buildSummaryCards(data),
                          const SizedBox(height: 16),
                          _buildPeakTimesSection(data),
                          const SizedBox(height: 16),
                          _buildPaymentMethodsSection(data),
                        ],
                        _DashboardSection.profit => [
                          _buildProfitSection(data),
                          const SizedBox(height: 16),
                          _buildNetSalesSection(data),
                          const SizedBox(height: 16),
                          _buildVatSection(data),
                        ],
                        _DashboardSection.products => [
                          _buildProductCards(data),
                          const SizedBox(height: 16),
                          _buildCategorySection(data),
                        ],
                      },
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// Owner only: the analysis screens, at the top of the dashboard.
  Widget _buildOwnerShortcuts() {
    Widget card({
      required IconData icon,
      required String label,
      required bool main,
      required VoidCallback onTap,
    }) {
      final radius = BorderRadius.circular(AppSpacing.cardRadius);
      return Material(
        color: main ? AppColors.accentSoft : AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: main ? AppColors.primaryDark : AppColors.border,
                width: main ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primaryDark, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label.tr,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    void openInsights() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OffersScreen(firestore: _firestore, currentUserId: widget.currentUserId),
      ),
    );
    final recs = InsightsFromDocs.build(
      products: [for (final d in _productDocuments) (id: d.id, data: d.data())],
      sales: _salesDocuments.map((d) => d.data()),
      costs: _costs,
      now: DateTime.now(),
      money: _money,
    );
    final top = recs.isEmpty ? null : recs.first;
    final shortcuts = Row(
      children: [
        Expanded(
          child: card(
            icon: Icons.insights_rounded,
            label: 'Insights',
            main: true,
            onTap: openInsights,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: card(
            icon: Icons.emoji_events_outlined,
            label: 'Top cashiers',
            main: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SalesHistoryScreen(
                  firestore: _firestore,
                  currentUserId: widget.currentUserId,
                  showTopCashiers: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    if (top == null) return shortcuts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(
          child: _TopRecommendationCard(rec: top, onTap: () => _showRecommendation(top)),
        ),
        const SizedBox(height: 12),
        shortcuts,
      ],
    );
  }

  /// The highlighted recommendation in full, with the one action that answers it.
  /// "Insights" stays the way to every recommendation, offer and tip.
  void _showRecommendation(Recommendation rec) {
    final (label, color, soft) = _priorityStyle(rec.priority);
    final title = switch (rec.kind) {
      'outOfStock' => 'Out of stock',
      'reorder' => 'Time to reorder',
      'trendUp' => 'Sales are growing',
      'trendDown' => 'Sales are slowing',
      'peakHour' => 'Your busiest hour',
      'priceUp' => 'Check this price',
      'refunds' => 'Refunds are high',
      'discounts' => 'Discounts are high',
      'category' => 'Your strongest category',
      'cashier' => 'Top cashier',
      _ => 'Most important now',
    };
    void go(Widget screen) {
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    final action = switch (rec.kind) {
      'outOfStock' || 'reorder' || 'priceUp' || 'category' => (
        icon: Icons.inventory_2_outlined,
        text: 'Open products',
        run: () => go(ProductsScreen(firestore: _firestore, currentUserId: widget.currentUserId)),
      ),
      'refunds' || 'discounts' => (
        icon: Icons.receipt_long_outlined,
        text: 'Open sales history',
        run: () =>
            go(SalesHistoryScreen(firestore: _firestore, currentUserId: widget.currentUserId)),
      ),
      'trendDown' => (
        icon: Icons.local_offer_outlined,
        text: 'Start a bundle offer',
        run: () => go(OffersScreen(firestore: _firestore, currentUserId: widget.currentUserId)),
      ),
      _ => null,
    };
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                    child: Icon(Icons.auto_awesome_rounded, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title.tr,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: soft,
                      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                    ),
                    child: Text(
                      label.tr,
                      style: TextStyle(
                        color: color,
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                rec.text.trArgs(rec.args),
                style: const TextStyle(fontSize: AppTypography.body, height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                'Based on your sales in the last 30 days.'.tr,
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
              const SizedBox(height: 18),
              if (action != null)
                FilledButton.icon(
                  onPressed: action.run,
                  icon: Icon(action.icon),
                  label: Text(action.text.tr),
                )
              else
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text('Got it'.tr),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Report presentation.
  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard'.tr,
                style: TextStyle(
                  fontSize: AppTypography.display,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Sales, payments, and product performance'.tr,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Compact actions: the long buttons used to push the report down.
        if (_canOpenSalesHistory) ...[
          IconButton.outlined(
            tooltip: 'Sales history'.tr,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SalesHistoryScreen(firestore: _firestore, currentUserId: widget.currentUserId),
              ),
            ),
            style: _headerAction,
            icon: const Icon(Icons.receipt_long_outlined, color: AppColors.text),
          ),
          const SizedBox(width: 6),
        ],
        IconButton.outlined(
          tooltip: 'End of day (Z-report)'.tr,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  EndOfDayScreen(firestore: _firestore, currentUserId: widget.currentUserId),
            ),
          ),
          style: _headerAction,
          icon: const Icon(Icons.point_of_sale_outlined, color: AppColors.text),
        ),
        const SizedBox(width: 6),
        IconButton.outlined(
          tooltip: 'Refresh'.tr,
          onPressed: _loadReports,
          style: _headerAction,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.text),
        ),
      ],
    );
  }

  static final ButtonStyle _headerAction = IconButton.styleFrom(
    backgroundColor: AppColors.surface,
    side: const BorderSide(color: AppColors.border),
  );

  /// Topic tabs under the period: underlined text, so they read differently from the
  /// period selector above them.
  Widget _buildSectionTabs() {
    Widget tab(String label, _DashboardSection section) {
      final selected = _section == section;
      return InkWell(
        key: ValueKey('dashboard-tab-${section.name}'),
        onTap: () => setState(() => _section = section),
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primaryDark : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label.tr,
            style: TextStyle(
              fontSize: AppTypography.button,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.text : AppColors.muted,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      // Scrolls sideways instead of clipping when the labels are long or the text is large.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tab('Sales', _DashboardSection.sales),
            const SizedBox(width: 22),
            tab('Profit & VAT', _DashboardSection.profit),
            const SizedBox(width: 22),
            tab('Products', _DashboardSection.products),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.soft,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: Row(
        children: [
          _periodButton('Today', ReportPeriod.today),
          _periodButton('Week', ReportPeriod.week),
          _periodButton('Month', ReportPeriod.month),
          _periodButton('Year', ReportPeriod.year),
        ],
      ),
    );
  }

  Widget _periodButton(String label, ReportPeriod period) {
    final isSelected = _selectedPeriod == period;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPeriod = period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.08),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label.tr,
            style: TextStyle(
              color: isSelected ? AppColors.text : AppColors.muted,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
              fontSize: AppTypography.body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendChart(_ReportsData data) {
    final maxY = _niceMax(data.chartValues);

    return _SectionCard(
      title: 'Sales trend'.tr,
      subtitle: _periodSubtitle(_selectedPeriod),
      // Bars grow from zero when the period or data changes (instant with reduced motion).
      child: TweenAnimationBuilder<double>(
        key: ValueKey('${_selectedPeriod}_${data.chartValues.join(',')}'),
        tween: Tween(begin: Motion.reduced(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, grow, _) => SizedBox(
          height: 250,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: _gridData(maxY),
              borderData: _chartBorder(),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: _leftTitles(maxY),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();

                      if (index < 0 || index >= data.chartLabels.length) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        // Arabic day and month names are longer; shrink instead of overlapping.
                        child: SizedBox(
                          width: 34,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              data.chartLabels[index].tr,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.caption,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List.generate(
                data.chartValues.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: math.max(0.0, data.chartValues[index]) * grow,
                      width: _barWidth(_selectedPeriod),
                      borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.primaryDark, AppColors.accent],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ink summary card: net sales for the period with orders, average and gross sales.
  Widget _buildHeroCard(_ReportsData data) {
    Widget figure(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.onHeroMuted, fontSize: AppTypography.caption),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.onHero,
                fontSize: AppTypography.subtitle,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    return ReceiptCard(
      gradient: AppColors.heroGradient,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Net sales · {period}'.trArgs({'period': _periodLabel(_selectedPeriod)}),
                  style: const TextStyle(
                    color: AppColors.onHeroMuted,
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (data.netChange != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                  ),
                  child: Text(
                    '{change}% vs {previous}'.trArgs({
                      'change':
                          '${data.netChange! >= 0 ? '+' : ''}${data.netChange!.toStringAsFixed(0)}',
                      'previous': _previousLabel(_selectedPeriod),
                    }),
                    style: TextStyle(
                      color: data.netChange! >= 0 ? AppColors.success : AppColors.danger,
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: CountUpText(
              value: data.netSales,
              format: _money,
              style: const TextStyle(
                color: AppColors.onHero,
                fontSize: AppTypography.display,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              figure('Orders'.tr, '${data.ordersCount}'),
              const SizedBox(width: 8),
              figure('Average'.tr, _money(data.averageOrder)),
              const SizedBox(width: 8),
              figure('Gross'.tr, _money(data.grossSales)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(_ReportsData data) {
    // Summary cards differ only in their content; share the construction.
    Widget stat(String title, String value, IconData icon, Color color, {String? subtitle}) =>
        _TopStatCard(
          icon: icon,
          color: color,
          title: title,
          value: value,
          subtitle: subtitle ?? _periodLabel(_selectedPeriod),
        );
    // Sales, net sales, orders and average order are in the hero card above.
    final cards = [
      stat('Discounts', _money(data.discounts), Icons.local_offer_rounded, AppColors.warning),
      stat('Refunds', _money(data.refunds), Icons.undo_rounded, AppColors.danger),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700
            ? 3
            : constraints.maxWidth >= 320
            ? 2
            : 1;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }

  Widget _buildProductCards(_ReportsData data) {
    final top = _productInsight(
      data.topSelling,
      icon: Icons.trending_up_rounded,
      color: AppColors.primaryDark,
      title: 'Top sellers'.tr,
      sheetTitle: 'Top 10 sellers'.tr,
      emptySubtitle: 'Tap to view top 10'.tr,
    );
    final least = _productInsight(
      data.leastSelling,
      icon: Icons.south_rounded,
      color: AppColors.warning,
      title: 'Least selling'.tr,
      sheetTitle: 'Least 10 selling'.tr,
      emptySubtitle: 'Tap to view lowest 10'.tr,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Product names need a full row on phones; keep the paired desktop layout.
        final stacked = constraints.maxWidth < 600;
        return Column(
          children: [
            if (stacked) ...[
              top,
              const SizedBox(height: 12),
              least,
            ] else
              Row(
                children: [
                  Expanded(child: top),
                  const SizedBox(width: 12),
                  Expanded(child: least),
                ],
              ),
            const SizedBox(height: 12),
            _productInsight(
              data.topRevenue,
              icon: Icons.workspace_premium_rounded,
              color: AppColors.primaryDark,
              title: 'Top revenue products'.tr,
              sheetTitle: 'Top 10 Revenue Products'.tr,
              emptySubtitle: 'Tap to view top 10'.tr,
              mode: _ProductSheetMode.revenue,
            ),
          ],
        );
      },
    );
  }

  // All product rankings share the same preview and bottom-sheet behavior.
  Widget _productInsight(
    List<_ProductSales> products, {
    required IconData icon,
    required Color color,
    required String title,
    required String sheetTitle,
    required String emptySubtitle,
    _ProductSheetMode mode = _ProductSheetMode.quantity,
  }) {
    final first = products.isEmpty ? null : products.first;
    return _InsightCard(
      icon: icon,
      color: color,
      title: title,
      value: first?.name ?? 'No data',
      subtitle: first == null
          ? emptySubtitle
          : mode == _ProductSheetMode.revenue
          ? _money(first.revenue)
          : '{n} sold'.trArgs({'n': first.quantity.toStringAsFixed(0)}),
      onTap: () => _showProductSheet(title: sheetTitle, products: products, mode: mode),
    );
  }

  String _previousLabel(ReportPeriod period) => switch (period) {
    ReportPeriod.today => 'yesterday'.tr,
    ReportPeriod.week => 'last week'.tr,
    ReportPeriod.month => 'last month'.tr,
    ReportPeriod.year => 'last year'.tr,
  };

  /// Gross profit from items with a cost price, plus what the shelves are worth.
  Widget _buildProfitSection(_ReportsData data) {
    final hasCosts = data.costedRevenue > 0;
    return _SectionCard(
      title: 'Profit'.tr,
      subtitle: 'Sales minus the cost of the items sold'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasCosts)
            _EmptyState(
              text: 'Add a cost price to your products (Products › Edit) to see profit here.'.tr,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _ProfitFigure(
                    label: 'Gross profit'.tr,
                    value: _money(data.grossProfit),
                    color: data.grossProfit >= 0 ? AppColors.success : AppColors.danger,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfitFigure(
                    label: 'Margin'.tr,
                    value: '${data.margin.toStringAsFixed(1)}%',
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _AmountRow('Sales with a cost price', _money(data.costedRevenue)),
            _AmountRow('Cost of goods sold', '- ${_money(data.costOfGoods)}'),
            if (data.uncostedRevenue > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_money(data.uncostedRevenue)} of sales had no cost price and are not counted.',
                  style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
                ),
              ),
          ],
          const Divider(height: 24),
          _AmountRow('Stock value at selling price', _money(data.stockRetailValue)),
          if (data.stockCostValue > 0)
            _AmountRow('Stock value at cost', _money(data.stockCostValue)),
          if (data.uncostedProducts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                data.uncostedProducts == 1
                    ? '1 product in stock has no cost price yet.'
                    : '${data.uncostedProducts} products in stock have no cost price yet.',
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(_ReportsData data) {
    final total = data.categories.fold<double>(0, (running, c) => running + c.amount);
    return _SectionCard(
      title: 'Sales by category'.tr,
      subtitle: 'Which kinds of products bring in the money'.tr,
      child: data.categories.isEmpty
          ? _EmptyState(text: 'No sales in this period yet'.tr)
          : Column(
              children: [
                for (final category in data.categories.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ProgressRow(
                      title: category.name,
                      trailing:
                          '${_money(category.amount)} · ${total == 0 ? 0 : (category.amount / total * 100).toStringAsFixed(0)}%',
                      progress: total == 0 ? 0 : category.amount / total,
                      color: AppColors.primaryDark,
                    ),
                  ),
              ],
            ),
    );
  }

  /// Busiest hours and weekdays, to plan staff and opening times.
  Widget _buildPeakTimesSection(_ReportsData data) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final hourMax = data.hourly.reduce(math.max);
    final dayMax = data.weekday.reduce(math.max);
    if (hourMax <= 0) {
      return _SectionCard(
        title: 'Peak times'.tr,
        subtitle: 'When customers buy the most'.tr,
        child: _EmptyState(text: 'No sales in this period yet'.tr),
      );
    }
    final bestHour = data.hourly.indexOf(hourMax);
    final bestDay = data.weekday.indexOf(dayMax);
    String hourLabel(int h) {
      final hour = h % 12 == 0 ? 12 : h % 12;
      final morning = h < 12;
      if (AppLanguage.isArabic) return '$hour ${morning ? 'ص' : 'م'}';
      return '$hour ${morning ? 'AM' : 'PM'}';
    }

    Widget bars(List<double> values, double max, int best, String Function(int) label, int every) =>
        SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: max <= 0 ? 0 : 64 * values[i] / max,
                          decoration: BoxDecoration(
                            // Other hours stay readable next to the busiest one.
                            color: i == best ? AppColors.primaryDark : AppColors.heroLine,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 16,
                          child: i % every == 0
                              ? FittedBox(
                                  child: Text(
                                    label(i),
                                    style: TextStyle(
                                      fontSize: AppTypography.micro,
                                      color: i == best ? AppColors.primaryDark : AppColors.muted,
                                      fontWeight: i == best ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );

    return _SectionCard(
      title: 'Peak times'.tr,
      subtitle: 'Busiest: {hour} · {day}'.trArgs({
        'hour': hourLabel(bestHour),
        'day': days[bestDay].tr,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By hour'.tr, style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          bars(data.hourly, hourMax, bestHour, (h) => '$h', 3),
          const SizedBox(height: 14),
          Text('By day'.tr, style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          bars(data.weekday, dayMax, bestDay, (d) => days[d].tr, 1),
        ],
      ),
    );
  }

  /// VAT already included in the period's sales (Bahrain standard rate).
  Widget _buildVatSection(_ReportsData data) {
    final excluding = data.netSales - data.vatCollected;
    return _SectionCard(
      title: 'VAT'.tr,
      subtitle: 'Prices include {rate}% VAT · for your NBR return'.trArgs({
        'rate': SaleRecord.bahrainVatRate.toStringAsFixed(0),
      }),
      child: Column(
        children: [
          _AmountRow('Sales including VAT', _money(data.netSales)),
          _AmountRow('Sales excluding VAT', _money(excluding < 0 ? 0 : excluding)),
          const Divider(height: 24),
          _AmountRow('VAT collected', _money(data.vatCollected), highlighted: true),
        ],
      ),
    );
  }

  Widget _buildNetSalesSection(_ReportsData data) {
    return _SectionCard(
      title: 'Net sales'.tr,
      subtitle: 'Gross sales minus discounts and refunds'.tr,
      child: Column(
        children: [
          _AmountRow('Gross sales', _money(data.grossSales)),
          _AmountRow('Discounts', '- ${_money(data.discounts)}'),
          _AmountRow('Refunds', '- ${_money(data.refunds)}'),
          const Divider(height: 24),
          _AmountRow('Net sales', _money(data.netSales), highlighted: true),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsSection(_ReportsData data) {
    final total = data.paymentMethods.fold<double>(
      0,
      (subtotal, method) => subtotal + method.amount,
    );

    return _SectionCard(
      title: 'Payment methods'.tr,
      subtitle: 'Cash, BenefitPay, card, and other payment totals'.tr,
      child: data.paymentMethods.isEmpty
          ? _EmptyState(text: 'No payment data yet'.tr)
          : Column(
              children: data.paymentMethods.map((method) {
                final progress = total == 0 ? 0.0 : method.amount / total;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ProgressRow(
                    title: method.name.tr,
                    trailing: _money(method.amount),
                    progress: progress,
                    color: AppColors.accent,
                  ),
                );
              }).toList(),
            ),
    );
  }

  void _showProductSheet({
    required String title,
    required List<_ProductSales> products,
    required _ProductSheetMode mode,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final list = products.take(10).toList();

        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: AppTypography.title,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: list.isEmpty
                        ? _EmptyState(text: 'No products yet'.tr)
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final product = list[index];
                              final trailing = mode == _ProductSheetMode.revenue
                                  ? _money(product.revenue)
                                  : '{n} sold'.trArgs({'n': product.quantity.toStringAsFixed(0)});

                              return _RankedProductTile(
                                rank: index + 1,
                                title: product.name,
                                subtitle:
                                    '${product.quantity.toStringAsFixed(0)} sold - ${_money(product.revenue)}',
                                trailing: trailing,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _money(double value) {
    return Money.format(value);
  }
}

class _TopStatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;

  const _TopStatCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, color: color),
          const SizedBox(height: 12),
          Text(
            title.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTypography.label,
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: AppTypography.metric,
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback onTap;

  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              _IconBadge(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr,
                      style: const TextStyle(
                        fontSize: AppTypography.label,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.section,
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle.tr,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlighted;

  const _AmountRow(this.label, this.value, {this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.tr,
              style: TextStyle(
                color: highlighted ? AppColors.text : AppColors.muted,
                fontSize: AppTypography.label,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlighted ? AppColors.primaryDark : AppColors.text,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String title;
  final String trailing;
  final double progress;
  final Color color;

  const _ProgressRow({
    required this.title,
    required this.trailing,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailing,
              style: const TextStyle(
                fontSize: AppTypography.label,
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
          child: LinearProgressIndicator(
            value: safeProgress,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _RankedProductTile extends StatelessWidget {
  final int rank;
  final String title;
  final String subtitle;
  final String trailing;

  const _RankedProductTile({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rank == 1 ? AppColors.primary : AppColors.soft,
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? AppColors.onBrand : AppColors.text,
                fontSize: AppTypography.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: AppTypography.label,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: AppTypography.body,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: Text('Try again'.tr)),
          ],
        ),
      ),
    );
  }
}

// Local report presentation models.
class _ReportsData {
  final double grossSales;
  final double netSales;
  final double discounts;
  final double refunds;
  final int ordersCount;
  final double averageOrder;
  final List<String> chartLabels;
  final List<double> chartValues;
  final List<_ProductSales> topSelling;
  final List<_ProductSales> leastSelling;
  final List<_ProductSales> topRevenue;
  final List<_PaymentReport> paymentMethods;

  const _ReportsData({
    required this.grossSales,
    required this.netSales,
    required this.discounts,
    required this.refunds,
    required this.ordersCount,
    required this.averageOrder,
    required this.chartLabels,
    required this.chartValues,
    required this.topSelling,
    required this.leastSelling,
    required this.topRevenue,
    required this.paymentMethods,
    required this.costedRevenue,
    required this.costOfGoods,
    required this.uncostedRevenue,
    required this.vatCollected,
    required this.hourly,
    required this.weekday,
    required this.categories,
    required this.previousNet,
    required this.previousOrders,
    required this.stockRetailValue,
    required this.stockCostValue,
    required this.uncostedProducts,
  });

  /// Revenue (after discounts) from lines that had a cost price recorded.
  final double costedRevenue;
  final double costOfGoods;

  /// Revenue from lines sold before a cost price was set; excluded from profit.
  final double uncostedRevenue;

  /// VAT contained in the period's receipts.
  final double vatCollected;
  final List<double> hourly;
  final List<double> weekday;
  final List<_PaymentReport> categories;
  final double previousNet;
  final int previousOrders;
  final double stockRetailValue;
  final double stockCostValue;
  final int uncostedProducts;

  double get grossProfit => costedRevenue - costOfGoods;
  double get margin => costedRevenue <= 0 ? 0 : grossProfit / costedRevenue * 100;

  /// Percent change of net sales against the previous period; null when there is no base.
  double? get netChange => previousNet <= 0 ? null : (netSales - previousNet) / previousNet * 100;
}

class _ProductSales {
  final String name;
  double quantity;
  double revenue;

  _ProductSales({required this.name}) : quantity = 0, revenue = 0;
}

class _PaymentReport {
  final String name;
  final double amount;

  const _PaymentReport(this.name, this.amount);
}

class _PeriodRange {
  final DateTime start;
  final DateTime end;

  const _PeriodRange({required this.start, required this.end});
}

class _ChartBuckets {
  final List<String> labels;
  final List<double> values;

  const _ChartBuckets({required this.labels, required this.values});
}

enum _ProductSheetMode { quantity, revenue }

// Chart formatting and local date buckets.
BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border: Border.all(color: AppColors.border),
  );
}

_PeriodRange _periodRange(ReportPeriod period) {
  // Use local time, inclusive starts and exclusive ends; weeks begin on Sunday.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (period) {
    case ReportPeriod.today:
      return _PeriodRange(start: today, end: today.add(const Duration(days: 1)));
    case ReportPeriod.week:
      final daysSinceSunday = now.weekday % 7;
      final weekStart = today.subtract(Duration(days: daysSinceSunday));
      return _PeriodRange(start: weekStart, end: weekStart.add(const Duration(days: 7)));
    case ReportPeriod.month:
      return _PeriodRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    case ReportPeriod.year:
      return _PeriodRange(start: DateTime(now.year), end: DateTime(now.year + 1));
  }
}

_ChartBuckets _emptyBuckets(ReportPeriod period) {
  final now = DateTime.now();

  switch (period) {
    case ReportPeriod.today:
      return _ChartBuckets(
        labels: List.generate(24, (index) => index % 3 == 0 ? '$index' : ''),
        values: List<double>.filled(24, 0),
      );
    case ReportPeriod.week:
      return _ChartBuckets(
        labels: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
        values: List<double>.filled(7, 0),
      );
    case ReportPeriod.month:
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      return _ChartBuckets(
        labels: List.generate(daysInMonth, (index) {
          final day = index + 1;
          return day == 1 || day % 5 == 0 ? '$day' : '';
        }),
        values: List<double>.filled(daysInMonth, 0),
      );
    case ReportPeriod.year:
      return _ChartBuckets(
        labels: const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ],
        values: List<double>.filled(12, 0),
      );
  }
}

int _bucketIndex(DateTime date, ReportPeriod period) {
  return switch (period) {
    ReportPeriod.today => date.hour,
    ReportPeriod.week => date.weekday % 7,
    ReportPeriod.month => date.day - 1,
    ReportPeriod.year => date.month - 1,
  };
}

String _periodLabel(ReportPeriod period) {
  return switch (period) {
    ReportPeriod.today => 'Today'.tr,
    ReportPeriod.week => 'This week'.tr,
    ReportPeriod.month => 'This month'.tr,
    ReportPeriod.year => 'This year'.tr,
  };
}

String _periodSubtitle(ReportPeriod period) {
  return switch (period) {
    ReportPeriod.today => 'Sales grouped by hour'.tr,
    ReportPeriod.week => 'Sales grouped by day'.tr,
    ReportPeriod.month => 'Sales grouped by day of month'.tr,
    ReportPeriod.year => 'Sales grouped by month'.tr,
  };
}

double _barWidth(ReportPeriod period) {
  return switch (period) {
    ReportPeriod.today => 7,
    ReportPeriod.week => 26,
    ReportPeriod.month => 6,
    ReportPeriod.year => 18,
  };
}

bool _inRange(DateTime date, DateTime start, DateTime end) {
  return !date.isBefore(start) && date.isBefore(end);
}

FlGridData _gridData(double maxY) {
  return FlGridData(
    show: true,
    drawVerticalLine: true,
    horizontalInterval: maxY / 4,
    verticalInterval: 1,
    getDrawingHorizontalLine: (_) {
      return const FlLine(color: AppColors.border, strokeWidth: 1);
    },
    getDrawingVerticalLine: (_) {
      return const FlLine(color: AppColors.border, strokeWidth: 1);
    },
  );
}

FlBorderData _chartBorder() {
  return FlBorderData(
    show: true,
    border: const Border(
      left: BorderSide(color: AppColors.border),
      bottom: BorderSide(color: AppColors.border),
    ),
  );
}

AxisTitles _leftTitles(double maxY) {
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: maxY / 4,
      reservedSize: 42,
      getTitlesWidget: (value, meta) {
        return Text(
          _compactNumber(value),
          style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
        );
      },
    ),
  );
}

double _niceMax(List<double> values) {
  final value = values.fold<double>(0, (max, item) => math.max(max, item));

  if (value <= 0) return 100;

  // Add headroom above the tallest bar and round the axis limit to an easy-to-read value.
  final padded = value * 1.2;
  final magnitude = math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();

  final normalized = padded / magnitude;

  final double niceNormalized = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 5
      ? 5.0
      : 10.0;

  return niceNormalized * magnitude;
}

String _compactNumber(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}K';
  }

  return value.toInt().toString();
}

class _ProfitFigure extends StatelessWidget {
  const _ProfitFigure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: AppTypography.headline,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashboard topics shown one at a time.
enum _DashboardSection { sales, profit, products }

/// The single most important recommendation, made to stand out on the dashboard.
(String, Color, Color) _priorityStyle(int priority) => switch (priority) {
  0 => ('Urgent', AppColors.danger, AppColors.dangerSoft),
  1 => ('Worth doing', AppColors.warning, AppColors.warningSoft),
  _ => ('Good to know', AppColors.success, AppColors.successSoft),
};

class _TopRecommendationCard extends StatelessWidget {
  const _TopRecommendationCard({required this.rec, required this.onTap});

  final Recommendation rec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color, soft) = _priorityStyle(rec.priority);
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return PressableScale(
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                  child: Icon(Icons.auto_awesome_rounded, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Most important now'.tr,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: soft,
                              borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                            ),
                            child: Text(
                              label.tr,
                              style: TextStyle(
                                color: color,
                                fontSize: AppTypography.caption,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rec.text.trArgs(rec.args),
                        style: const TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
