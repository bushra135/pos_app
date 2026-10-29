import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/report_sale.dart';
import 'sales_history_screen.dart';

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
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;
  static const _requestTimeout = Duration(seconds: 10);

  ReportPeriod _selectedPeriod = ReportPeriod.week;

  bool _isLoading = true;
  bool _canOpenSalesHistory = false;
  String? _errorMessage;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _salesDocuments = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _productDocuments = [];

  static const String currency = 'BD';

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

      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_requestTimeout);
      final storeCode = (userDoc.data()?['storeCode'] ?? '').toString().trim();

      if (storeCode.isEmpty) throw Exception('Store code not found');

      final salesSnapshot = await _firestore
          .collection('sales')
          .where('storeCode', isEqualTo: storeCode)
          .get()
          .timeout(_requestTimeout);

      final productsSnapshot = await _firestore
          .collection('products')
          .where('storeCode', isEqualTo: storeCode)
          .get()
          .timeout(_requestTimeout);

      final storeProducts = productsSnapshot.docs.where((doc) {
        final productStoreCode = (doc.data()['storeCode'] ?? '')
            .toString()
            .trim();
        return productStoreCode == storeCode;
      }).toList();

      if (!mounted) return;

      setState(() {
        _canOpenSalesHistory = userDoc.data()?['role'] == 'owner';
        _salesDocuments = salesSnapshot.docs;
        _productDocuments = storeProducts;
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

    // Seed inventory first so unsold products appear among the least-selling items.
    for (final doc in _productDocuments) {
      final data = doc.data();
      final name = (data['name'] ?? data['productName'] ?? 'Unknown Product')
          .toString();

      final key = reportProductKey(data, name);
      productSales[key] = _ProductSales(name: name);
    }

    for (final doc in _salesDocuments) {
      final saleData = doc.data();
      final createdAt = reportDate(saleData['createdAt']);

      if (createdAt == null) continue;
      if (!_inRange(createdAt, range.start, range.end)) continue;

      final sale = ReportSale.fromMap(saleData);

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

        for (final item in sale.items) {
          final name =
              (item['name'] ??
                      item['productName'] ??
                      item['title'] ??
                      'Unknown Product')
                  .toString();

          final key = reportProductKey(item, name);
          final quantity = reportNumber(item, ['quantity', 'qty', 'count']);
          final price = reportNumber(item, ['price', 'unitPrice', 'salePrice']);
          final itemTotal = reportNumber(item, [
            'subtotal',
            'total',
            'lineTotal',
          ]);

          final safeQuantity = quantity <= 0 ? 1.0 : quantity;
          final revenue = itemTotal > 0 ? itemTotal : price * safeQuantity;

          final product = productSales[key] ?? _ProductSales(name: name);

          product.quantity += safeQuantity;
          product.revenue += revenue;
          productSales[key] = product;
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

    final topRevenue = productSales.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    final paymentReports =
        paymentMethods.entries
            .map((entry) => _PaymentReport(entry.key, entry.value))
            .toList()
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
                tooltip: 'Back to assistant',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text('Back to assistant'),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    16,
                    AppSpacing.page,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      if (_canOpenSalesHistory)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SalesHistoryScreen(
                                  firestore: _firestore,
                                  currentUserId: widget.currentUserId,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.history),
                            label: const Text('Sales history'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _buildPeriodSelector(),
                      const SizedBox(height: 16),
                      _buildTrendChart(data),
                      const SizedBox(height: 16),
                      _buildSummaryCards(data),
                      const SizedBox(height: 16),
                      _buildProductCards(data),
                      const SizedBox(height: 16),
                      _buildNetSalesSection(data),
                      const SizedBox(height: 16),
                      _buildPaymentMethodsSection(data),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // Report presentation.
  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POS Reports',
                style: TextStyle(
                  fontSize: AppTypography.title,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Sales, payments, and product performance',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadReports,
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.primaryDark,
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.text.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.primaryDark : AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: AppTypography.label,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendChart(_ReportsData data) {
    final maxY = _niceMax(data.chartValues);

    return _SectionCard(
      title: 'Sales Trend',
      subtitle: _periodSubtitle(_selectedPeriod),
      child: SizedBox(
        height: 250,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            gridData: _gridData(maxY),
            borderData: _chartBorder(),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
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
                      child: Text(
                        data.chartLabels[index],
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w600,
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
                    toY: math.max(0.0, data.chartValues[index]),
                    width: _barWidth(_selectedPeriod),
                    borderRadius: BorderRadius.circular(7),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(_ReportsData data) {
    final cards = <Widget>[
      _TopStatCard(
        icon: Icons.payments_rounded,
        color: AppColors.success,
        title: 'Sales',
        value: _money(data.grossSales),
        subtitle: _periodLabel(_selectedPeriod),
      ),
      _TopStatCard(
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.primaryDark,
        title: 'Net Sales',
        value: _money(data.netSales),
        subtitle: 'After discounts/refunds',
      ),
      _TopStatCard(
        icon: Icons.receipt_long_rounded,
        color: AppColors.warning,
        title: 'Orders',
        value: '${data.ordersCount}',
        subtitle: 'Invoices count',
      ),
      _TopStatCard(
        icon: Icons.calculate_rounded,
        color: AppColors.primaryDark,
        title: 'Avg Order',
        value: _money(data.averageOrder),
        subtitle: 'Sales / orders',
      ),
      _TopStatCard(
        icon: Icons.local_offer_rounded,
        color: AppColors.warning,
        title: 'Discounts',
        value: _money(data.discounts),
        subtitle: _periodLabel(_selectedPeriod),
      ),
      _TopStatCard(
        icon: Icons.undo_rounded,
        color: AppColors.danger,
        title: 'Refunds',
        value: _money(data.refunds),
        subtitle: _periodLabel(_selectedPeriod),
      ),
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
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _buildProductCards(_ReportsData data) {
    final topSeller = data.topSelling.isEmpty ? null : data.topSelling.first;
    final leastSeller = data.leastSelling.isEmpty
        ? null
        : data.leastSelling.first;
    final topRevenue = data.topRevenue.isEmpty ? null : data.topRevenue.first;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _InsightCard(
                icon: Icons.trending_up_rounded,
                color: AppColors.primaryDark,
                title: 'Top Sellers',
                value: topSeller?.name ?? 'No data',
                subtitle: topSeller == null
                    ? 'Tap to view top 10'
                    : '${topSeller.quantity.toStringAsFixed(0)} sold',
                onTap: () {
                  _showProductSheet(
                    title: 'Top 10 Sellers',
                    products: data.topSelling,
                    mode: _ProductSheetMode.quantity,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InsightCard(
                icon: Icons.south_rounded,
                color: AppColors.warning,
                title: 'Least Selling',
                value: leastSeller?.name ?? 'No data',
                subtitle: leastSeller == null
                    ? 'Tap to view lowest 10'
                    : '${leastSeller.quantity.toStringAsFixed(0)} sold',
                onTap: () {
                  _showProductSheet(
                    title: 'Least 10 Selling',
                    products: data.leastSelling,
                    mode: _ProductSheetMode.quantity,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InsightCard(
          icon: Icons.workspace_premium_rounded,
          color: AppColors.primaryDark,
          title: 'Top Revenue Products',
          value: topRevenue?.name ?? 'No data',
          subtitle: topRevenue == null
              ? 'Tap to view top 10'
              : _money(topRevenue.revenue),
          onTap: () {
            _showProductSheet(
              title: 'Top 10 Revenue Products',
              products: data.topRevenue,
              mode: _ProductSheetMode.revenue,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNetSalesSection(_ReportsData data) {
    return _SectionCard(
      title: 'Net Sales',
      subtitle: 'Gross sales minus discounts and refunds',
      child: Column(
        children: [
          _AmountRow('Gross Sales', _money(data.grossSales)),
          _AmountRow('Discounts', '- ${_money(data.discounts)}'),
          _AmountRow('Refunds', '- ${_money(data.refunds)}'),
          const Divider(height: 24),
          _AmountRow('Net Sales', _money(data.netSales), highlighted: true),
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
      title: 'Payment Methods',
      subtitle: 'Cash, BenefitPay, card, and other payment totals',
      child: data.paymentMethods.isEmpty
          ? const _EmptyState(text: 'No payment data yet')
          : Column(
              children: data.paymentMethods.map((method) {
                final progress = total == 0 ? 0.0 : method.amount / total;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ProgressRow(
                    title: method.name,
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
                      borderRadius: BorderRadius.circular(99),
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
                        ? const _EmptyState(text: 'No products yet')
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final product = list[index];
                              final trailing = mode == _ProductSheetMode.revenue
                                  ? _money(product.revenue)
                                  : '${product.quantity.toStringAsFixed(0)} sold';

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
    return '$currency ${value.toStringAsFixed(3)}';
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
            title,
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
            subtitle,
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
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
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
                      title,
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
                      subtitle,
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

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

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
            subtitle,
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
              label,
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
          borderRadius: BorderRadius.circular(8),
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
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: AppColors.primaryDark,
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
                  subtitle,
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
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 42,
            ),
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
            ElevatedButton(onPressed: onRetry, child: const Text('Try Again')),
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
  });
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
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: AppColors.text.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 9),
      ),
    ],
  );
}

_PeriodRange _periodRange(ReportPeriod period) {
  // Use local time, inclusive starts and exclusive ends; weeks begin on Sunday.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (period) {
    case ReportPeriod.today:
      return _PeriodRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      );
    case ReportPeriod.week:
      final daysSinceSunday = now.weekday % 7;
      final weekStart = today.subtract(Duration(days: daysSinceSunday));
      return _PeriodRange(
        start: weekStart,
        end: weekStart.add(const Duration(days: 7)),
      );
    case ReportPeriod.month:
      return _PeriodRange(
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      );
    case ReportPeriod.year:
      return _PeriodRange(
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
      );
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
    ReportPeriod.today => 'Today',
    ReportPeriod.week => 'This week',
    ReportPeriod.month => 'This month',
    ReportPeriod.year => 'This year',
  };
}

String _periodSubtitle(ReportPeriod period) {
  return switch (period) {
    ReportPeriod.today => 'Sales grouped by hour',
    ReportPeriod.week => 'Sales grouped by day',
    ReportPeriod.month => 'Sales grouped by day of month',
    ReportPeriod.year => 'Sales grouped by month',
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
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: AppTypography.caption,
          ),
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
  final magnitude = math
      .pow(10, (math.log(padded) / math.ln10).floor())
      .toDouble();

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
