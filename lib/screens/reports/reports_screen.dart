import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

enum ReportPeriod { today, week, month, year }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ReportPeriod selectedPeriod = ReportPeriod.week;

  bool isLoading = true;
  String? errorMessage;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> salesDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocs = [];

  static const String currency = 'BD';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final user = _auth.currentUser;
      if (user == null) throw Exception('No user');

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final storeCode = (userDoc.data()?['storeCode'] ?? '').toString().trim();

      if (storeCode.isEmpty) throw Exception('Store code not found');

      final salesSnapshot = await _firestore
          .collection('sales')
          .where('storeCode', isEqualTo: storeCode)
          .get();

      final productsSnapshot = await _firestore.collection('products').get();

      final storeProducts = productsSnapshot.docs.where((doc) {
        final productStoreCode =
            (doc.data()['storeCode'] ?? '').toString().trim();
        return productStoreCode == storeCode;
      }).toList();

      if (!mounted) return;

      setState(() {
        salesDocs = salesSnapshot.docs;
        productDocs = storeProducts;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Reports error: $e');

      if (!mounted) return;

      setState(() {
        errorMessage = 'Failed to load reports';
        isLoading = false;
      });
    }
  }

  _ReportsData _calculateReports() {
    final range = _periodRange(selectedPeriod);
    final buckets = _emptyBuckets(selectedPeriod);

    double grossSales = 0;
    double netSales = 0;
    double discounts = 0;
    double refunds = 0;
    int ordersCount = 0;

    final paymentMethods = <String, double>{};
    final productSales = <String, _ProductSales>{};

    for (final doc in productDocs) {
      final data = doc.data();
      final name =
          (data['name'] ?? data['productName'] ?? 'Unknown Product').toString();

      final key = _productKey(data, name);
      productSales[key] = _ProductSales(
        key: key,
        name: name,
      );
    }

    for (final doc in salesDocs) {
      final saleData = doc.data();
      final createdAt = _dateFromValue(saleData['createdAt']);

      if (createdAt == null) continue;
      if (!_inRange(createdAt, range.start, range.end)) continue;

      final sale = _SaleRecord.fromMap(saleData);

      grossSales += sale.grossSales;
      netSales += sale.netSales;
      discounts += sale.discount;
      refunds += sale.refund;

      if (!sale.isRefund) ordersCount++;

      final bucketIndex = _bucketIndex(createdAt, selectedPeriod);
      if (bucketIndex >= 0 && bucketIndex < buckets.values.length) {
        buckets.values[bucketIndex] += sale.netSales;
      }

      if (!sale.isRefund) {
        paymentMethods[sale.paymentMethod] =
            (paymentMethods[sale.paymentMethod] ?? 0) + sale.netSales;

        for (final item in sale.items) {
          final name = (item['name'] ??
                  item['productName'] ??
                  item['title'] ??
                  'Unknown Product')
              .toString();

          final key = _productKey(item, name);
          final quantity = _numFromKeys(item, ['quantity', 'qty', 'count']);
          final price = _numFromKeys(item, ['price', 'unitPrice', 'salePrice']);
          final itemTotal = _numFromKeys(item, [
            'subtotal',
            'total',
            'lineTotal',
          ]);

          final safeQuantity = quantity <= 0 ? 1.0 : quantity;
          final revenue = itemTotal > 0 ? itemTotal : price * safeQuantity;

          final product = productSales[key] ??
              _ProductSales(
                key: key,
                name: name,
              );

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

    final paymentReports = paymentMethods.entries
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
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? _ErrorState(message: errorMessage!, onRetry: _loadReports)
                : RefreshIndicator(
                    onRefresh: _loadReports,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
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
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2A44),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Sales, payments, and product performance',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF98A2B3),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadReports,
          icon: const Icon(Icons.refresh_rounded),
          color: Color(0xFF2F80FF),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF7),
        borderRadius: BorderRadius.circular(18),
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
    final isSelected = selectedPeriod == period;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedPeriod = period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1B2940).withOpacity(0.08),
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
              color: isSelected
                  ? const Color(0xFF2F80FF)
                  : const Color(0xFF667085),
              fontWeight: FontWeight.w800,
              fontSize: 13,
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
      subtitle: _periodSubtitle(selectedPeriod),
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
                          color: Color(0xFF98A2B3),
                          fontSize: 10,
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
                    width: _barWidth(selectedPeriod),
                    borderRadius: BorderRadius.circular(7),
                    color: const Color(0xFF5AC8B5),
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.42,
      children: [
        _TopStatCard(
          icon: Icons.payments_rounded,
          color: const Color(0xFF4FD1A5),
          title: 'Sales',
          value: _money(data.grossSales),
          subtitle: _periodLabel(selectedPeriod),
        ),
        _TopStatCard(
          icon: Icons.account_balance_wallet_rounded,
          color: const Color(0xFF2F80FF),
          title: 'Net Sales',
          value: _money(data.netSales),
          subtitle: 'After discounts/refunds',
        ),
        _TopStatCard(
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFFFFA726),
          title: 'Orders',
          value: '${data.ordersCount}',
          subtitle: 'Invoices count',
        ),
        _TopStatCard(
          icon: Icons.calculate_rounded,
          color: const Color(0xFF00A6A6),
          title: 'Avg Order',
          value: _money(data.averageOrder),
          subtitle: 'Sales / orders',
        ),
        _TopStatCard(
          icon: Icons.local_offer_rounded,
          color: const Color(0xFFFF9800),
          title: 'Discounts',
          value: _money(data.discounts),
          subtitle: _periodLabel(selectedPeriod),
        ),
        _TopStatCard(
          icon: Icons.undo_rounded,
          color: const Color(0xFFFF5252),
          title: 'Refunds',
          value: _money(data.refunds),
          subtitle: _periodLabel(selectedPeriod),
        ),
      ],
    );
  }

  Widget _buildProductCards(_ReportsData data) {
    final topSeller = data.topSelling.isEmpty ? null : data.topSelling.first;
    final leastSeller =
        data.leastSelling.isEmpty ? null : data.leastSelling.first;
    final topRevenue = data.topRevenue.isEmpty ? null : data.topRevenue.first;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _InsightCard(
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF49C59D),
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
                color: const Color(0xFFFF9800),
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
          color: const Color(0xFF2F80FF),
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
          _AmountRow(
            'Net Sales',
            _money(data.netSales),
            highlighted: true,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsSection(_ReportsData data) {
    final total = data.paymentMethods.fold<double>(
      0,
      (sum, method) => sum + method.amount,
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
                    color: const Color(0xFF4C6FFF),
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
                color: Color(0xFFF5F7FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
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
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2A44),
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
                            separatorBuilder: (_, __) =>
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBadge(icon: icon, color: color),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF98A2B3),
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
                fontSize: 21,
                color: Color(0xFF1F2A44),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
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
      color: Colors.white,
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
                        fontSize: 13,
                        color: Color(0xFF98A2B3),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1F2A44),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A2B3),
              ),
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
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2A44),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF98A2B3),
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

  const _IconBadge({
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlighted;

  const _AmountRow(
    this.label,
    this.value, {
    this.highlighted = false,
  });

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
                color: highlighted
                    ? const Color(0xFF1F2A44)
                    : const Color(0xFF667085),
                fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlighted
                  ? const Color(0xFF2F80FF)
                  : const Color(0xFF1F2A44),
              fontWeight: FontWeight.w800,
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
                  fontSize: 14,
                  color: Color(0xFF4B5565),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailing,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF98A2B3),
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
            backgroundColor: const Color(0xFFE9EEF5),
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
              color: const Color(0xFF2F80FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Color(0xFF2F80FF),
                fontWeight: FontWeight.w900,
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
                    color: Color(0xFF1F2A44),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
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
              color: Color(0xFF2F80FF),
              fontWeight: FontWeight.w800,
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
            color: Color(0xFF98A2B3),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
              color: Colors.red,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFF1F2A44),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _SaleRecord {
  final double grossSales;
  final double netSales;
  final double discount;
  final double refund;
  final bool isRefund;
  final String paymentMethod;
  final List<Map<String, dynamic>> items;

  const _SaleRecord({
    required this.grossSales,
    required this.netSales,
    required this.discount,
    required this.refund,
    required this.isRefund,
    required this.paymentMethod,
    required this.items,
  });

  factory _SaleRecord.fromMap(Map<String, dynamic> data) {
    final explicitTotal = _numFromKeys(data, [
      'netTotal',
      'grandTotal',
      'total',
      'totalAmount',
      'amount',
    ]);

    final discount = _numFromKeys(data, [
      'discount',
      'discountAmount',
      'totalDiscount',
    ]).abs();

    final status =
        (data['status'] ?? data['type'] ?? '').toString().toLowerCase();

    final isRefund = status.contains('refund') ||
        status.contains('return') ||
        status.contains('cancel');

    final refundAmount = _numFromKeys(data, [
      'refund',
      'refundAmount',
      'totalRefund',
      'returnedAmount',
    ]).abs();

    final refund = refundAmount > 0
        ? refundAmount
        : isRefund
            ? explicitTotal.abs()
            : 0.0;

    final explicitGross = _numFromKeys(data, [
      'grossTotal',
      'subtotal',
      'subTotal',
      'totalBeforeDiscount',
      'beforeDiscount',
    ]);

    final grossSales = isRefund
        ? 0.0
        : explicitGross > 0
            ? explicitGross
            : explicitTotal + discount;

    final double netSales =
        isRefund ? -refund : math.max(0.0, explicitTotal - refund);

    final rawItems = data['items'] ?? data['cartItems'] ?? data['products'];
    final items = <Map<String, dynamic>>[];

    if (rawItems is List) {
      for (final item in rawItems) {
        final itemMap = _asMap(item);
        if (itemMap.isNotEmpty) items.add(itemMap);
      }
    }

    return _SaleRecord(
      grossSales: grossSales,
      netSales: netSales,
      discount: discount,
      refund: refund,
      isRefund: isRefund,
      paymentMethod: _paymentLabel(
        data['paymentMethod'] ?? data['paymentType'] ?? data['payment'],
      ),
      items: items,
    );
  }
}

class _ProductSales {
  final String key;
  final String name;
  double quantity;
  double revenue;

  _ProductSales({
    required this.key,
    required this.name,
    this.quantity = 0,
    this.revenue = 0,
  });
}

class _PaymentReport {
  final String name;
  final double amount;

  const _PaymentReport(this.name, this.amount);
}

class _PeriodRange {
  final DateTime start;
  final DateTime end;

  const _PeriodRange({
    required this.start,
    required this.end,
  });
}

class _ChartBuckets {
  final List<String> labels;
  final List<double> values;

  const _ChartBuckets({
    required this.labels,
    required this.values,
  });
}

enum _ProductSheetMode { quantity, revenue }

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFEFF3F8)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF1B2940).withOpacity(0.06),
        blurRadius: 16,
        offset: const Offset(0, 9),
      ),
    ],
  );
}

_PeriodRange _periodRange(ReportPeriod period) {
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
  switch (period) {
    case ReportPeriod.today:
      return date.hour;
    case ReportPeriod.week:
      return date.weekday % 7;
    case ReportPeriod.month:
      return date.day - 1;
    case ReportPeriod.year:
      return date.month - 1;
  }
}

String _periodLabel(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.today:
      return 'Today';
    case ReportPeriod.week:
      return 'This week';
    case ReportPeriod.month:
      return 'This month';
    case ReportPeriod.year:
      return 'This year';
  }
}

String _periodSubtitle(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.today:
      return 'Sales grouped by hour';
    case ReportPeriod.week:
      return 'Sales grouped by day';
    case ReportPeriod.month:
      return 'Sales grouped by day of month';
    case ReportPeriod.year:
      return 'Sales grouped by month';
  }
}

double _barWidth(ReportPeriod period) {
  switch (period) {
    case ReportPeriod.today:
      return 7;
    case ReportPeriod.week:
      return 26;
    case ReportPeriod.month:
      return 6;
    case ReportPeriod.year:
      return 18;
  }
}

bool _inRange(DateTime date, DateTime start, DateTime end) {
  return !date.isBefore(start) && date.isBefore(end);
}

DateTime? _dateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return {};
}

String _productKey(Map<String, dynamic> data, String fallbackName) {
  final barcode = (data['barcode'] ?? '').toString().trim();
  final productId = (data['productId'] ?? data['id'] ?? '').toString().trim();

  if (barcode.isNotEmpty) return barcode;
  if (productId.isNotEmpty) return productId;

  return fallbackName.trim().toLowerCase();
}

double _numFromKeys(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];

    if (value is num) return value.toDouble();

    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }

  return 0;
}

String _paymentLabel(dynamic value) {
  final raw = (value ?? 'Unknown').toString().trim().toLowerCase();

  if (raw.isEmpty) return 'Unknown';
  if (raw.contains('cash')) return 'Cash';
  if (raw.contains('benefit')) return 'BenefitPay';
  if (raw.contains('card') ||
      raw.contains('visa') ||
      raw.contains('mada')) {
    return 'Card';
  }
  if (raw.contains('apple')) return 'Apple Pay';
  if (raw.contains('transfer') || raw.contains('bank')) {
    return 'Bank Transfer';
  }

  return raw[0].toUpperCase() + raw.substring(1);
}

FlGridData _gridData(double maxY) {
  return FlGridData(
    show: true,
    drawVerticalLine: true,
    horizontalInterval: maxY / 4,
    verticalInterval: 1,
    getDrawingHorizontalLine: (_) {
      return const FlLine(color: Color(0xFFE8EDF5), strokeWidth: 1);
    },
    getDrawingVerticalLine: (_) {
      return const FlLine(color: Color(0xFFE8EDF5), strokeWidth: 1);
    },
  );
}

FlBorderData _chartBorder() {
  return FlBorderData(
    show: true,
    border: const Border(
      left: BorderSide(color: Color(0xFFD9E2EF)),
      bottom: BorderSide(color: Color(0xFFD9E2EF)),
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
            color: Color(0xFF98A2B3),
            fontSize: 11,
          ),
        );
      },
    ),
  );
}

double _niceMax(List<double> values) {
  final value = values.fold<double>(
    0,
    (max, item) => math.max(max, item),
  );

  if (value <= 0) return 100;

  final padded = value * 1.2;
  final magnitude =
      math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();

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
