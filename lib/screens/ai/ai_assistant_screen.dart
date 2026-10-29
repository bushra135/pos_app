import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../models/report_sale.dart';
import '../reports/reports_screen.dart';

/// Calculates store insights locally using keyword rules and store records.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.firestore, this.currentUserId});
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  String? get _uid => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;
  static const _requestTimeout = Duration(seconds: 10);
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isThinking = false;

  final List<_ChatMessage> messages = [
    const _ChatMessage(
      isUser: false,
      text:
          "Hello! I can analyze your POS data, sales, inventory, payment methods, and product performance. What would you like to know?",
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadOwnerName();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOwnerName() async {
    try {
      final uid = _uid;
      if (uid == null) return;

      final userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_requestTimeout);
      final fullName = (userDoc.data()?['fullName'] ?? '').toString().trim();

      if (fullName.isEmpty) return;

      final firstName = fullName.split(' ').first;

      if (!mounted) return;

      setState(() {
        messages[0] = _ChatMessage(
          isUser: false,
          text:
              "Hello $firstName! I can analyze your POS data, sales, inventory, payment methods, and product performance. What would you like to know?",
        );
      });
    } catch (e) {
      debugPrint('Error loading owner name: $e');
    }
  }

  Future<void> _sendMessage([String? preset]) async {
    if (_isThinking) return;

    final question = (preset ?? _messageController.text).trim();
    if (question.isEmpty) return;

    _messageController.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      messages.add(_ChatMessage(isUser: true, text: question));
      _isThinking = true;
    });

    _scrollToBottom();

    try {
      final answer = await _buildAnswer(
        question,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        messages.add(
          _ChatMessage(isUser: false, text: answer, hasReport: true),
        );
        _isThinking = false;
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('AI assistant error: $e');

      if (!mounted) return;

      setState(() {
        messages.add(
          _ChatMessage(
            isUser: false,
            text:
                'Local analysis could not load store data. Check your connection and try again.',
          ),
        );
        _isThinking = false;
      });

      _scrollToBottom();
    }
  }

  // Analyze locally: match ordered keyword rules and calculate answers from store data.
  // Route a question to deterministic local calculations.
  Future<String> _buildAnswer(String question) async {
    final data = await _loadStoreData();
    final q = question.toLowerCase();

    if (_containsAny(q, [
      'low stock',
      'stock alert',
      'out of stock',
      'empty stock',
    ])) {
      return _lowStockAlerts(data);
    }

    if (_containsAny(q, ['restock', 'reorder', 'recommend', 'order stock'])) {
      return _restockRecommendations(data);
    }

    if (_containsAny(q, ['slow', 'least', 'not selling', 'lowest selling'])) {
      return _slowMovingProducts(data);
    }

    if (_containsAny(q, ['top revenue', 'highest revenue', 'most money'])) {
      return _topRevenueProducts(data);
    }

    if (_containsAny(q, ['top', 'best', 'seller', 'selling product'])) {
      return _topProductsThisWeek(data);
    }

    if (_containsAny(q, ['payment', 'cash', 'benefit', 'card'])) {
      return _paymentSummary(data);
    }

    if (_containsAny(q, [
      'best hour',
      'busy hour',
      'peak hour',
      'sales hour',
    ])) {
      return _bestSalesHourToday(data);
    }

    if (_containsAny(q, ['discount', 'refund', 'net sales'])) {
      return _netSalesSummary(data);
    }

    if (_containsAny(q, ['week sales', 'this week'])) {
      return _periodSalesSummary(
        data: data,
        title: 'This week sales summary',
        range: _currentWeekRange(),
      );
    }

    if (_containsAny(q, ['month sales', 'this month'])) {
      return _periodSalesSummary(
        data: data,
        title: 'This month sales summary',
        range: _currentMonthRange(),
      );
    }

    if (_containsAny(q, ['today', 'sales summary', 'daily summary'])) {
      return _todaySalesSummary(data);
    }

    return _storeOverview(data);
  }

  // Load store-scoped records; no paid AI service is called.
  Future<_StoreData> _loadStoreData() async {
    final uid = _uid;
    if (uid == null) throw Exception('No user found');

    final userDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(_requestTimeout);
    final storeCode = (userDoc.data()?['storeCode'] ?? '').toString().trim();

    if (storeCode.isEmpty) throw Exception('Store code not found');

    final productsSnapshot = await _firestore
        .collection('products')
        .where('storeCode', isEqualTo: storeCode)
        .get()
        .timeout(_requestTimeout);

    final productDocs = productsSnapshot.docs.where((doc) {
      final data = doc.data();
      final productStoreCode = (data['storeCode'] ?? '').toString().trim();
      return productStoreCode == storeCode;
    }).toList();

    final salesSnapshot = await _firestore
        .collection('sales')
        .where('storeCode', isEqualTo: storeCode)
        .get()
        .timeout(_requestTimeout);

    final products = productDocs.map((doc) {
      final item = doc.data();
      final name = (item['name'] ?? item['productName'] ?? 'Unknown Product')
          .toString();

      const minStockKeys = ['minStock', 'minQuantity', 'minimumStock'];

      return _ProductInfo(
        key: reportProductKey(item, name),
        name: name,
        stock: reportNumber(item, ['stock', 'quantity']).toInt(),
        minStock: minStockKeys.any(item.containsKey)
            ? reportNumber(item, minStockKeys).toInt()
            : 5,
      );
    }).toList();

    // Later calculations require valid dates, so skip records with missing timestamps.
    final sales = salesSnapshot.docs
        .map((doc) => _SaleInfo.fromMap(doc.data()))
        .where((sale) => sale.createdAt != null)
        .toList();

    return _StoreData(products: products, sales: sales);
  }

  // Build readable answers from store records.
  String _todaySalesSummary(_StoreData data) {
    final range = _todayRange();
    final sales = _salesInRange(data.sales, range);
    final validSales = sales.where((sale) => !sale.isRefund).toList();

    final total = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.netTotal,
    );
    final gross = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.grossTotal,
    );
    final orders = validSales.length;
    final averageOrder = orders == 0 ? 0.0 : total / orders;

    final topProducts = _aggregateProducts(validSales).values.toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

    final topProduct = topProducts.isEmpty ? null : topProducts.first;

    return [
      "Today's sales summary:",
      "",
      "- Gross sales: ${_money(gross)}",
      "- Net sales: ${_money(total)}",
      "- Orders: $orders",
      "- Average order value: ${_money(averageOrder)}",
      if (topProduct != null)
        "- Top product: ${topProduct.name} (${topProduct.quantity.toStringAsFixed(0)} sold)",
      if (orders == 0) "- No sales have been recorded today yet.",
    ].join('\n');
  }

  String _periodSalesSummary({
    required _StoreData data,
    required String title,
    required _DateRange range,
  }) {
    final sales = _salesInRange(data.sales, range);

    final total = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.netTotal,
    );
    final gross = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.grossTotal,
    );
    final discounts = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.discount,
    );
    final refunds = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.refund,
    );
    final orders = sales.where((sale) => !sale.isRefund).length;
    final averageOrder = orders == 0 ? 0.0 : total / orders;

    return [
      "$title:",
      "",
      "- Gross sales: ${_money(gross)}",
      "- Net sales: ${_money(total)}",
      "- Orders: $orders",
      "- Average order value: ${_money(averageOrder)}",
      "- Discounts: ${_money(discounts)}",
      "- Refunds: ${_money(refunds)}",
    ].join('\n');
  }

  String _topProductsThisWeek(_StoreData data) {
    final range = _currentWeekRange();
    final sales = _salesInRange(
      data.sales,
      range,
    ).where((sale) => !sale.isRefund).toList();

    final products =
        _aggregateProducts(sales).values.where((product) {
          return product.quantity > 0;
        }).toList()..sort((a, b) {
          final quantityCompare = b.quantity.compareTo(a.quantity);
          if (quantityCompare != 0) return quantityCompare;
          return b.revenue.compareTo(a.revenue);
        });

    if (products.isEmpty) {
      return "No products have been sold this week yet.";
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return "$index. ${product.name}: ${product.quantity.toStringAsFixed(0)} sold (${_money(product.revenue)})";
    });

    return ["Top selling products this week:", "", ...lines].join('\n');
  }

  String _topRevenueProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(
      data.sales,
      range,
    ).where((sale) => !sale.isRefund).toList();

    final products = _aggregateProducts(sales).values.where((product) {
      return product.revenue > 0;
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    if (products.isEmpty) {
      return "No product revenue data found this month.";
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return "$index. ${product.name}: ${_money(product.revenue)} (${product.quantity.toStringAsFixed(0)} sold)";
    });

    return ["Top revenue products this month:", "", ...lines].join('\n');
  }

  String _slowMovingProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(
      data.sales,
      range,
    ).where((sale) => !sale.isRefund).toList();

    final metrics = _aggregateProducts(sales);

    final products =
        data.products.map((product) {
          final metric = metrics[product.key];

          return _ProductMetric(
            name: product.name,
            quantity: metric?.quantity ?? 0,
            revenue: metric?.revenue ?? 0,
          );
        }).toList()..sort((a, b) {
          final quantityCompare = a.quantity.compareTo(b.quantity);
          if (quantityCompare != 0) return quantityCompare;
          return a.revenue.compareTo(b.revenue);
        });

    if (products.isEmpty) {
      return "No products found in your inventory.";
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return "$index. ${product.name}: ${product.quantity.toStringAsFixed(0)} sold";
    });

    return ["Slow moving products this month:", "", ...lines].join('\n');
  }

  String _lowStockAlerts(_StoreData data) {
    if (data.products.isEmpty) {
      return "I couldn't find any products for this store. Please check that products have the correct storeCode.";
    }

    final lowStock = data.products.where((product) {
      return product.stock <= product.minStock;
    }).toList()..sort((a, b) => a.stock.compareTo(b.stock));

    if (lowStock.isEmpty) {
      return "No low stock products were found right now.";
    }

    final lines = lowStock.take(10).map((product) {
      final status = product.stock <= 0 ? "Out of stock" : "Low stock";
      return "- ${product.name}: ${product.stock} left ($status, minimum ${product.minStock})";
    });

    return ["Low stock alerts:", "", ...lines].join('\n');
  }

  String _restockRecommendations(_StoreData data) {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));

    final recentSales = data.sales.where((sale) {
      final date = sale.createdAt!;
      return !sale.isRefund && !date.isBefore(from);
    }).toList();

    final metrics = _aggregateProducts(recentSales);
    final recommendations = <_RestockRecommendation>[];

    for (final product in data.products) {
      final monthlySold = metrics[product.key]?.quantity ?? 0;
      // Target the greater of the last 30 days' sales or twice the minimum stock.
      final targetStock = math.max(product.minStock * 2, monthlySold.ceil());
      final reorderQty = math.max(0, targetStock - product.stock);

      if (product.stock <= product.minStock || reorderQty > 0) {
        recommendations.add(
          _RestockRecommendation(
            name: product.name,
            currentStock: product.stock,
            recommendedQty: reorderQty,
          ),
        );
      }
    }

    recommendations.sort(
      (a, b) => b.recommendedQty.compareTo(a.recommendedQty),
    );

    if (recommendations.isEmpty) {
      return "No restock needed right now. Your inventory looks healthy.";
    }

    final lines = recommendations.take(10).map((item) {
      return "- ${item.name}: current ${item.currentStock}, recommended reorder ${item.recommendedQty}";
    });

    return ["Restock recommendations:", "", ...lines].join('\n');
  }

  String _paymentSummary(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(
      data.sales,
      range,
    ).where((sale) => !sale.isRefund).toList();

    final payments = <String, double>{};

    for (final sale in sales) {
      payments[sale.paymentMethod] =
          (payments[sale.paymentMethod] ?? 0) + sale.netTotal;
    }

    if (payments.isEmpty) {
      return "No payment data found for this month yet.";
    }

    final entries = payments.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(
      0,
      (subtotal, entry) => subtotal + entry.value,
    );

    final lines = entries.map((entry) {
      final percent = total == 0 ? 0 : (entry.value / total) * 100;
      return "- ${entry.key}: ${_money(entry.value)} (${percent.toStringAsFixed(1)}%)";
    });

    return ["Payment methods this month:", "", ...lines].join('\n');
  }

  String _bestSalesHourToday(_StoreData data) {
    final range = _todayRange();
    final sales = _salesInRange(
      data.sales,
      range,
    ).where((sale) => !sale.isRefund).toList();

    final hourlySales = List<double>.filled(24, 0);
    final hourlyOrders = List<int>.filled(24, 0);

    for (final sale in sales) {
      final hour = sale.createdAt!.hour;
      hourlySales[hour] += sale.netTotal;
      hourlyOrders[hour]++;
    }

    double bestAmount = 0;
    int bestHour = 0;

    for (int i = 0; i < hourlySales.length; i++) {
      if (hourlySales[i] > bestAmount) {
        bestAmount = hourlySales[i];
        bestHour = i;
      }
    }

    if (bestAmount == 0) {
      return "No sales have been recorded today yet.";
    }

    return [
      "Best sales hour today:",
      "",
      "- Hour: ${bestHour.toString().padLeft(2, '0')}:00",
      "- Sales: ${_money(bestAmount)}",
      "- Orders: ${hourlyOrders[bestHour]}",
    ].join('\n');
  }

  String _netSalesSummary(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range);

    final gross = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.grossTotal,
    );
    final discounts = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.discount,
    );
    final refunds = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.refund,
    );
    final net = sales.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.netTotal,
    );

    return [
      "Net sales summary this month:",
      "",
      "- Gross sales: ${_money(gross)}",
      "- Discounts: ${_money(discounts)}",
      "- Refunds: ${_money(refunds)}",
      "- Net sales: ${_money(net)}",
    ].join('\n');
  }

  String _storeOverview(_StoreData data) {
    final today = _salesInRange(data.sales, _todayRange());
    final month = _salesInRange(data.sales, _currentMonthRange());

    final todaySales = today.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.netTotal,
    );
    final monthSales = month.fold<double>(
      0,
      (subtotal, sale) => subtotal + sale.netTotal,
    );

    final todayOrders = today.where((sale) => !sale.isRefund).length;
    final monthOrders = month.where((sale) => !sale.isRefund).length;

    final lowStockCount = data.products.where((product) {
      return product.stock <= product.minStock;
    }).length;

    final topProducts = _aggregateProducts(
      month.where((sale) => !sale.isRefund).toList(),
    ).values.toList()..sort((a, b) => b.quantity.compareTo(a.quantity));

    final topProduct = topProducts.isEmpty ? null : topProducts.first;

    return [
      "Store overview:",
      "",
      "- Today sales: ${_money(todaySales)}",
      "- Today orders: $todayOrders",
      "- This month sales: ${_money(monthSales)}",
      "- This month orders: $monthOrders",
      "- Products in inventory: ${data.products.length}",
      "- Low stock products: $lowStockCount",
      if (topProduct != null)
        "- Top product this month: ${topProduct.name} (${topProduct.quantity.toStringAsFixed(0)} sold)",
    ].join('\n');
  }

  List<_SaleInfo> _salesInRange(List<_SaleInfo> sales, _DateRange range) {
    return sales.where((sale) {
      final date = sale.createdAt!;
      return !date.isBefore(range.start) && date.isBefore(range.end);
    }).toList();
  }

  Map<String, _ProductMetric> _aggregateProducts(List<_SaleInfo> sales) {
    final metrics = <String, _ProductMetric>{};

    for (final sale in sales) {
      for (final item in sale.items) {
        final metric = metrics[item.key] ?? _ProductMetric(name: item.name);

        metric.quantity += item.quantity;
        metric.revenue += item.subtotal;
        metrics[item.key] = metric;
      }
    }

    return metrics;
  }

  _DateRange _todayRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _DateRange(start: today, end: today.add(const Duration(days: 1)));
  }

  _DateRange _currentWeekRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Begin the week on Sunday to match the reports screen.
    final daysSinceSunday = now.weekday % 7;
    final start = today.subtract(Duration(days: daysSinceSunday));

    return _DateRange(start: start, end: start.add(const Duration(days: 7)));
  }

  _DateRange _currentMonthRange() {
    final now = DateTime.now();

    return _DateRange(
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1),
    );
  }

  bool _containsAny(String value, List<String> keywords) {
    return keywords.any(value.contains);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  String _money(double value) {
    return 'BD ${value.toStringAsFixed(3)}';
  }

  void _startNewConversation() {
    if (_isThinking) return;
    setState(() {
      messages.removeRange(1, messages.length);
      _messageController.clear();
    });
  }

  @override
  // Chat presentation and navigation.
  Widget build(BuildContext context) {
    final isNewConversation = messages.length == 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    children: [
                      if (isNewConversation) ...[
                        _buildWelcomeCard(),
                        const SizedBox(height: 24),
                        _buildSuggestions(),
                      ] else ...[
                        for (final message in messages.skip(1))
                          _MessageBubble(
                            message: message,
                            onOpenReports: _openReports,
                          ),
                      ],
                      if (_isThinking) const _TypingBubble(),
                    ],
                  ),
                ),
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  void _openReports() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportsScreen(
          returnToAssistant: true,
          firestore: _firestore,
          currentUserId: () => _uid,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ShopPad Assistant',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  'Sales insights, made simple',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isThinking || messages.length == 1
                ? null
                : _startNewConversation,
            tooltip: 'New conversation',
            icon: const Icon(Icons.edit_square, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE1EEFF), Color(0xFFF8FBFF)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.primaryDark,
              size: 28,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your store.\nA clearer picture.',
            style: TextStyle(
              fontSize: 29,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: AppColors.onBrand,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose a question below to explore your sales and stock. Local analysis supports the suggested topics and similar English questions.',
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoPill(Icons.lock_outline, 'Your store data'),
              _buildInfoPill(Icons.visibility_outlined, 'Read-only insights'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primaryDark),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.primaryDark),
        ),
      ],
    ),
  );

  Widget _buildSuggestions() {
    const prompts = [
      (
        Icons.trending_up_rounded,
        'Sales snapshot',
        "Today's sales summary",
        'How is today going?',
      ),
      (
        Icons.inventory_2_outlined,
        'Stock check',
        'Low stock alerts',
        'See what is running low',
      ),
      (
        Icons.star_outline_rounded,
        'Best sellers',
        'Top products this week',
        'Find your top products',
      ),
      (
        Icons.add_shopping_cart_rounded,
        'Restock suggestions',
        'Restock recommendations',
        'Plan your next stock order',
      ),
      (
        Icons.hourglass_bottom_rounded,
        'Slow-moving items',
        'Slow moving products',
        'Find items with fewer sales',
      ),
      (
        Icons.payments_outlined,
        'Payment summary',
        'Payment summary',
        'See cash and BenefitPay sales',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'A good place to start',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 480 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final prompt in prompts)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _isThinking
                            ? null
                            : () => _sendMessage(prompt.$3),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  prompt.$1,
                                  color: AppColors.primaryDark,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prompt.$2,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      prompt.$4,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.north_east_rounded,
                                size: 17,
                                color: AppColors.primaryDark,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: AppColors.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 828),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 14,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Local analysis',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'English prompts',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'About this analysis mode',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.info_outline, size: 17),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Local analysis'),
                        content: Text(
                          'Answers are calculated on your device using English keyword rules and your store records. No paid AI service or API key is used. Loading store records may require a connection.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Got it'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        enabled: !_isThinking,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 600,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Ask about your store…',
                          counterText: '',
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: IconButton.filled(
                        onPressed: _isThinking ? null : () => _sendMessage(),
                        tooltip: 'Send message',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(44, 44),
                        ),
                        icon: _isThinking
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback onOpenReports;
  const _MessageBubble({required this.message, required this.onOpenReports});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final explanation = message.text;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: isUser ? .88 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isUser ? AppColors.accentSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUser
                        ? Icons.person_outline_rounded
                        : Icons.auto_awesome_rounded,
                    size: 17,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isUser ? 'You' : 'Local analysis',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  if (!isUser)
                    IconButton(
                      tooltip: 'Copy answer',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.text),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Answer copied')),
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                explanation,
                textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(explanation)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
              if (message.hasReport)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.bar_chart_rounded, size: 18),
                    label: const Text('Open reports'),
                    onPressed: onOpenReports,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Looking at your store data…',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final bool hasReport;

  const _ChatMessage({
    required this.isUser,
    required this.text,
    this.hasReport = false,
  });
}

// Local insight models.
class _StoreData {
  final List<_ProductInfo> products;
  final List<_SaleInfo> sales;

  const _StoreData({required this.products, required this.sales});
}

class _ProductInfo {
  final String key;
  final String name;
  final int stock;
  final int minStock;

  const _ProductInfo({
    required this.key,
    required this.name,
    required this.stock,
    required this.minStock,
  });
}

class _SaleInfo {
  final DateTime? createdAt;
  final double grossTotal;
  final double netTotal;
  final double discount;
  final double refund;
  final bool isRefund;
  final String paymentMethod;
  final List<_SaleItem> items;

  const _SaleInfo({
    required this.createdAt,
    required this.grossTotal,
    required this.netTotal,
    required this.discount,
    required this.refund,
    required this.isRefund,
    required this.paymentMethod,
    required this.items,
  });

  factory _SaleInfo.fromMap(Map<String, dynamic> data) {
    final summary = ReportSale.fromMap(data);
    final rawItems = data['items'] ?? data['cartItems'] ?? data['products'];
    final items = <_SaleItem>[];

    if (rawItems is List) {
      for (final rawItem in rawItems) {
        final item = reportMap(rawItem);
        if (item.isEmpty) continue;

        final name =
            (item['name'] ??
                    item['productName'] ??
                    item['title'] ??
                    'Unknown Product')
                .toString();

        final quantity = reportNumber(item, ['quantity', 'qty', 'count']);
        final price = reportNumber(item, ['price', 'unitPrice', 'salePrice']);
        final subtotal = reportNumber(item, ['subtotal', 'total', 'lineTotal']);

        // For missing values, assume one unit and calculate the subtotal from its price.
        final safeQuantity = quantity <= 0 ? 1.0 : quantity;

        items.add(
          _SaleItem(
            key: reportProductKey(item, name),
            name: name,
            quantity: safeQuantity,
            subtotal: subtotal > 0 ? subtotal : price * safeQuantity,
          ),
        );
      }
    }

    return _SaleInfo(
      createdAt: reportDate(data['createdAt']),
      grossTotal: summary.grossSales,
      netTotal: summary.netSales,
      discount: summary.discount,
      refund: summary.refund,
      isRefund: summary.isRefund,
      paymentMethod: summary.paymentMethod,
      items: items,
    );
  }
}

class _SaleItem {
  final String key;
  final String name;
  final double quantity;
  final double subtotal;

  const _SaleItem({
    required this.key,
    required this.name,
    required this.quantity,
    required this.subtotal,
  });
}

class _ProductMetric {
  final String name;
  double quantity;
  double revenue;

  _ProductMetric({required this.name, this.quantity = 0, this.revenue = 0});
}

class _RestockRecommendation {
  final String name;
  final int currentStock;
  final int recommendedQty;

  const _RestockRecommendation({
    required this.name,
    required this.currentStock,
    required this.recommendedQty,
  });
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}
