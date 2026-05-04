import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool isThinking = false;
  String ownerFirstName = 'Store Owner';

  final List<_ChatMessage> messages = [
    const _ChatMessage(
      isUser: false,
      text:
          "Hello! I can analyze your POS data, sales, inventory, payment methods, and product performance. What would you like to know?",
    ),
  ];

  final List<String> suggestions = const [
    "Today's sales summary",
    "Top products this week",
    "Low stock alerts",
    "Restock recommendations",
    "Slow moving products",
    "Payment summary",
    "Store overview",
    "Best sales hour today",
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
      final user = _auth.currentUser;
      if (user == null) return;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final fullName = (userDoc.data()?['fullName'] ?? '').toString().trim();

      if (fullName.isEmpty) return;

      final firstName = fullName.split(' ').first;

      if (!mounted) return;

      setState(() {
        ownerFirstName = firstName;
        messages[0] = _ChatMessage(
          isUser: false,
          text:
              "Hello $ownerFirstName! I can analyze your POS data, sales, inventory, payment methods, and product performance. What would you like to know?",
        );
      });
    } catch (e) {
      debugPrint('Error loading owner name: $e');
    }
  }

  Future<void> _sendMessage([String? preset]) async {
    if (isThinking) return;

    final question = (preset ?? _messageController.text).trim();
    if (question.isEmpty) return;

    _messageController.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      messages.add(_ChatMessage(isUser: true, text: question));
      isThinking = true;
    });

    _scrollToBottom();

    try {
      final answer = await _buildAnswer(question);

      if (!mounted) return;

      setState(() {
        messages.add(_ChatMessage(isUser: false, text: answer));
        isThinking = false;
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('AI assistant error: $e');

      if (!mounted) return;

      setState(() {
        messages.add(
          const _ChatMessage(
            isUser: false,
            text:
                "I couldn't load your store data right now. Please check your connection and try again.",
          ),
        );
        isThinking = false;
      });

      _scrollToBottom();
    }
  }

  Future<String> _buildAnswer(String question) async {
    final data = await _loadStoreData();
    final q = question.toLowerCase();

    if (_containsAny(q, ['low stock', 'stock alert', 'out of stock', 'empty stock'])) {
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

    if (_containsAny(q, ['best hour', 'busy hour', 'peak hour', 'sales hour'])) {
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

    if (_containsAny(q, ['overview', 'analyze', 'store performance', 'status'])) {
      return _storeOverview(data);
    }

    return _storeOverview(data);
  }

  Future<_StoreData> _loadStoreData() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user found');

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final storeCode = (userDoc.data()?['storeCode'] ?? '').toString().trim();

    if (storeCode.isEmpty) throw Exception('Store code not found');

    final productsSnapshot = await _firestore.collection('products').get();

    final productDocs = productsSnapshot.docs.where((doc) {
      final data = doc.data();
      final productStoreCode = (data['storeCode'] ?? '').toString().trim();
      return productStoreCode == storeCode;
    }).toList();

    final salesSnapshot = await _firestore
        .collection('sales')
        .where('storeCode', isEqualTo: storeCode)
        .get();

    final products = productDocs.map((doc) {
      final item = doc.data();
      final name =
          (item['name'] ?? item['productName'] ?? 'Unknown Product').toString();

      final hasMinStock = _hasAnyKey(item, [
        'minStock',
        'minQuantity',
        'minimumStock',
      ]);

      return _ProductInfo(
        key: _productKey(item, name),
        name: name,
        stock: _numFromKeys(item, ['stock', 'quantity']).toInt(),
        minStock: hasMinStock
            ? _numFromKeys(item, [
                'minStock',
                'minQuantity',
                'minimumStock',
              ]).toInt()
            : 5,
        price: _numFromKeys(item, ['price', 'salePrice', 'unitPrice']),
      );
    }).toList();

    final sales = salesSnapshot.docs
        .map((doc) => _SaleInfo.fromMap(doc.data()))
        .where((sale) => sale.createdAt != null)
        .toList();

    return _StoreData(products: products, sales: sales);
  }

  String _todaySalesSummary(_StoreData data) {
    final range = _todayRange();
    final sales = _salesInRange(data.sales, range);
    final validSales = sales.where((sale) => !sale.isRefund).toList();

    final total = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);
    final gross = sales.fold<double>(0, (sum, sale) => sum + sale.grossTotal);
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
    final validSales = sales.where((sale) => !sale.isRefund).toList();

    final total = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);
    final gross = sales.fold<double>(0, (sum, sale) => sum + sale.grossTotal);
    final discounts = sales.fold<double>(0, (sum, sale) => sum + sale.discount);
    final refunds = sales.fold<double>(0, (sum, sale) => sum + sale.refund);
    final orders = validSales.length;
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
    final sales = _salesInRange(data.sales, range)
        .where((sale) => !sale.isRefund)
        .toList();

    final products = _aggregateProducts(sales).values.where((product) {
      return product.quantity > 0;
    }).toList()
      ..sort((a, b) {
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

    return [
      "Top selling products this week:",
      "",
      ...lines,
    ].join('\n');
  }

  String _topRevenueProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range)
        .where((sale) => !sale.isRefund)
        .toList();

    final products = _aggregateProducts(sales).values.where((product) {
      return product.revenue > 0;
    }).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    if (products.isEmpty) {
      return "No product revenue data found this month.";
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return "$index. ${product.name}: ${_money(product.revenue)} (${product.quantity.toStringAsFixed(0)} sold)";
    });

    return [
      "Top revenue products this month:",
      "",
      ...lines,
    ].join('\n');
  }

  String _slowMovingProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range)
        .where((sale) => !sale.isRefund)
        .toList();

    final metrics = _aggregateProducts(sales);

    final products = data.products.map((product) {
      final metric = metrics[product.key];

      return _ProductMetric(
        key: product.key,
        name: product.name,
        quantity: metric?.quantity ?? 0,
        revenue: metric?.revenue ?? 0,
      );
    }).toList()
      ..sort((a, b) {
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

    return [
      "Slow moving products this month:",
      "",
      ...lines,
    ].join('\n');
  }

  String _lowStockAlerts(_StoreData data) {
    if (data.products.isEmpty) {
      return "I couldn't find any products for this store. Please check that products have the correct storeCode.";
    }

    final lowStock = data.products.where((product) {
      return product.stock <= product.minStock;
    }).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    if (lowStock.isEmpty) {
      return "No low stock products were found right now.";
    }

    final lines = lowStock.take(10).map((product) {
      final status = product.stock <= 0 ? "Out of stock" : "Low stock";
      return "- ${product.name}: ${product.stock} left ($status, minimum ${product.minStock})";
    });

    return [
      "Low stock alerts:",
      "",
      ...lines,
    ].join('\n');
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

    return [
      "Restock recommendations:",
      "",
      ...lines,
    ].join('\n');
  }

  String _paymentSummary(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range)
        .where((sale) => !sale.isRefund)
        .toList();

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

    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);

    final lines = entries.map((entry) {
      final percent = total == 0 ? 0 : (entry.value / total) * 100;
      return "- ${entry.key}: ${_money(entry.value)} (${percent.toStringAsFixed(1)}%)";
    });

    return [
      "Payment methods this month:",
      "",
      ...lines,
    ].join('\n');
  }

  String _bestSalesHourToday(_StoreData data) {
    final range = _todayRange();
    final sales = _salesInRange(data.sales, range)
        .where((sale) => !sale.isRefund)
        .toList();

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

    final gross = sales.fold<double>(0, (sum, sale) => sum + sale.grossTotal);
    final discounts = sales.fold<double>(0, (sum, sale) => sum + sale.discount);
    final refunds = sales.fold<double>(0, (sum, sale) => sum + sale.refund);
    final net = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);

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

    final todaySales =
        today.fold<double>(0, (sum, sale) => sum + sale.netTotal);
    final monthSales =
        month.fold<double>(0, (sum, sale) => sum + sale.netTotal);

    final todayOrders = today.where((sale) => !sale.isRefund).length;
    final monthOrders = month.where((sale) => !sale.isRefund).length;

    final lowStockCount = data.products.where((product) {
      return product.stock <= product.minStock;
    }).length;

    final topProducts = _aggregateProducts(
      month.where((sale) => !sale.isRefund).toList(),
    ).values.toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));

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
        final metric = metrics[item.key] ??
            _ProductMetric(
              key: item.key,
              name: item.name,
            );

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

    return _DateRange(
      start: today,
      end: today.add(const Duration(days: 1)),
    );
  }

  _DateRange _currentWeekRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceSunday = now.weekday % 7;
    final start = today.subtract(Duration(days: daysSinceSunday));

    return _DateRange(
      start: start,
      end: start.add(const Duration(days: 7)),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSuggestions(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                itemCount: messages.length + (isThinking ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return const _TypingBubble();
                  }

                  return _MessageBubble(message: messages[index]);
                },
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 25, 24, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.fromARGB(255, 164, 235, 213),
            Color.fromARGB(255, 5, 197, 245),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white24,
            child: Icon(Icons.smart_toy, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI Assistant",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 21,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Store insights from your POS data",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: suggestions.map((text) {
          return ActionChip(
            onPressed: isThinking ? null : () => _sendMessage(text),
            label: Text(text),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.grey.shade300),
            labelStyle: const TextStyle(
              color: Color(0xFF4B5565),
              fontWeight: FontWeight.w600,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2940).withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _messageController,
                enabled: !isThinking,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: "Ask about your sales or inventory...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(255, 164, 235, 213),
                  Color.fromARGB(255, 5, 197, 245),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: isThinking ? null : () => _sendMessage(),
              icon: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 20,
              backgroundColor: Color.fromARGB(255, 5, 197, 245),
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color.fromARGB(255, 5, 197, 245)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B2940).withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF2D313A),
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFFE6F8FF),
              child: Icon(
                Icons.person,
                color: Color.fromARGB(255, 5, 197, 245),
                size: 20,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Color.fromARGB(255, 5, 197, 245),
            child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
          SizedBox(width: 10),
          Text(
            "Analyzing store data...",
            style: TextStyle(
              color: Color(0xFF98A2B3),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final bool isUser;
  final String text;

  const _ChatMessage({
    required this.isUser,
    required this.text,
  });
}

class _StoreData {
  final List<_ProductInfo> products;
  final List<_SaleInfo> sales;

  const _StoreData({
    required this.products,
    required this.sales,
  });
}

class _ProductInfo {
  final String key;
  final String name;
  final int stock;
  final int minStock;
  final double price;

  const _ProductInfo({
    required this.key,
    required this.name,
    required this.stock,
    required this.minStock,
    required this.price,
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
    final status = (data['status'] ?? data['type'] ?? '')
        .toString()
        .toLowerCase();

    final isRefund = status.contains('refund') ||
        status.contains('return') ||
        status.contains('cancel');

    final total = _numFromKeys(data, [
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

    final refundAmount = _numFromKeys(data, [
      'refund',
      'refundAmount',
      'totalRefund',
      'returnedAmount',
    ]).abs();

    final refund = refundAmount > 0
        ? refundAmount
        : isRefund
            ? total.abs()
            : 0.0;

    final explicitGross = _numFromKeys(data, [
      'grossTotal',
      'subtotal',
      'subTotal',
      'totalBeforeDiscount',
      'beforeDiscount',
    ]);

    final grossTotal = isRefund
        ? 0.0
        : explicitGross > 0
            ? explicitGross
            : total + discount;

    final netTotal = isRefund ? -refund : math.max(0.0, total - refund);

    final rawItems = data['items'] ?? data['cartItems'] ?? data['products'];
    final items = <_SaleItem>[];

    if (rawItems is List) {
      for (final rawItem in rawItems) {
        final item = _asMap(rawItem);
        if (item.isEmpty) continue;

        final name = (item['name'] ??
                item['productName'] ??
                item['title'] ??
                'Unknown Product')
            .toString();

        final quantity = _numFromKeys(item, ['quantity', 'qty', 'count']);
        final price = _numFromKeys(item, ['price', 'unitPrice', 'salePrice']);
        final subtotal = _numFromKeys(item, [
          'subtotal',
          'total',
          'lineTotal',
        ]);

        final safeQuantity = quantity <= 0 ? 1.0 : quantity;

        items.add(
          _SaleItem(
            key: _productKey(item, name),
            name: name,
            quantity: safeQuantity,
            subtotal: subtotal > 0 ? subtotal : price * safeQuantity,
          ),
        );
      }
    }

    return _SaleInfo(
      createdAt: _dateFromValue(data['createdAt']),
      grossTotal: grossTotal,
      netTotal: netTotal,
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
  final String key;
  final String name;
  double quantity;
  double revenue;

  _ProductMetric({
    required this.key,
    required this.name,
    this.quantity = 0,
    this.revenue = 0,
  });
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

  const _DateRange({
    required this.start,
    required this.end,
  });
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

bool _hasAnyKey(Map<String, dynamic> data, List<String> keys) {
  return keys.any(data.containsKey);
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
