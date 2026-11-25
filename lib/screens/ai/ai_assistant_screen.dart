import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/sales_query.dart';
import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/report_sale.dart';
import '../../utils/bundle_offer_planner.dart';
import '../reports/reports_screen.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';

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
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  static const _requestTimeout = Duration(seconds: 10);
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isThinking = false;

  final List<_ChatMessage> messages = [
    _ChatMessage(
      isUser: false,
      text:
          "Hello! I can analyze your POS data, sales, inventory, payment methods, and product performance. What would you like to know?"
              .tr,
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

      final userDoc = await _firestore.collection('users').doc(uid).get().timeout(_requestTimeout);
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
      final answer = await _buildAnswer(question).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        messages.add(_ChatMessage(isUser: false, text: answer, hasReport: true));
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
                'Local analysis could not load store data. Check your connection and try again.'.tr,
          ),
        );
        _isThinking = false;
      });

      _scrollToBottom();
    }
  }

  // Match ordered keyword rules, then calculate a deterministic answer from store data.
  Future<String> _buildAnswer(String question) async {
    final data = await _loadStoreData();
    final q = question.toLowerCase();

    if (_containsAny(q, [
      'bundle',
      'offer',
      'promotion',
      'promo',
      'combo',
      'deal',
      'عرض',
      'عروض',
      'باقة',
      'تخفيض',
    ])) {
      return _bundleOffers(data);
    }

    if (_containsAny(q, [
      'low stock',
      'stock alert',
      'out of stock',
      'empty stock',
      'نقص',
      'منخفض',
      'نفد',
      'نفاد',
    ])) {
      return _lowStockAlerts(data);
    }

    if (_containsAny(q, [
      'restock',
      'reorder',
      'recommend',
      'order stock',
      'إعادة تعبئة',
      'اطلب',
      'توصي',
      'أطلب',
    ])) {
      return _restockRecommendations(data);
    }

    if (_containsAny(q, [
      'slow',
      'least',
      'not selling',
      'lowest selling',
      'بطيء',
      'بطيئة',
      'الأقل',
      'راكد',
    ])) {
      return _slowMovingProducts(data);
    }

    if (_containsAny(q, ['top revenue', 'highest revenue', 'most money', 'إيراد', 'دخل'])) {
      return _topRevenueProducts(data);
    }

    if (_containsAny(q, ['top', 'best', 'seller', 'selling product', 'الأكثر', 'الاكثر', 'أفضل'])) {
      return _topProductsThisWeek(data);
    }

    if (_containsAny(q, ['payment', 'cash', 'benefit', 'card', 'دفع', 'نقد', 'كاش', 'بنفت'])) {
      return _paymentSummary(data);
    }

    if (_containsAny(q, ['best hour', 'busy hour', 'peak hour', 'sales hour', 'ساعة'])) {
      return _bestSalesHourToday(data);
    }

    if (_containsAny(q, ['discount', 'refund', 'net sales', 'خصومات', 'استرجاع', 'صافي'])) {
      return _netSalesSummary(data);
    }

    if (_containsAny(q, ['week sales', 'this week', 'الأسبوع', 'اسبوع'])) {
      return _periodSalesSummary(
        data: data,
        title: 'This week sales summary'.tr,
        range: _currentWeekRange(),
      );
    }

    if (_containsAny(q, ['month sales', 'this month', 'الشهر', 'شهر'])) {
      return _periodSalesSummary(
        data: data,
        title: 'This month sales summary'.tr,
        range: _currentMonthRange(),
      );
    }

    if (_containsAny(q, ['today', 'sales summary', 'daily summary', 'اليوم', 'ملخص'])) {
      return _todaySalesSummary(data);
    }

    return _storeOverview(data);
  }

  // Load store-scoped records; no paid AI service is called.
  Future<_StoreData> _loadStoreData() async {
    final uid = _uid;
    if (uid == null) throw Exception('No user found');

    final userDoc = await _firestore.collection('users').doc(uid).get().timeout(_requestTimeout);
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

    // Answers cover at most this month, this week or the last 30 days.
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final thirtyDays = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 31));
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday % 7));
    final from = [monthStart, thirtyDays, weekStart].reduce((a, b) => a.isBefore(b) ? a : b);
    final salesDocs = await SalesQuery.since(
      _firestore,
      storeCode: storeCode,
      from: from,
      timeout: _requestTimeout,
    );

    final products = productDocs.map((doc) {
      final item = doc.data();
      final name = (item['name'] ?? item['productName'] ?? 'Unknown Product').toString();

      const minStockKeys = ['minStock', 'minQuantity', 'minimumStock'];

      return _ProductInfo(
        key: reportProductKey(item, name),
        name: name,
        stock: reportNumber(item, ['stock', 'quantity']).toInt(),
        minStock: minStockKeys.any(item.containsKey) ? reportNumber(item, minStockKeys).toInt() : 5,
        category: (item['category'] ?? '').toString(),
        price: reportNumber(item, ['price']),
      );
    }).toList();

    // Later calculations require valid dates, so skip records with missing timestamps.
    final sales = salesDocs
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

    final total = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.netTotal);
    final gross = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.grossTotal);
    final orders = validSales.length;
    final averageOrder = orders == 0 ? 0.0 : total / orders;

    // Same order as the dashboard and owner home: units, then revenue, then name.
    final topProducts = _aggregateProducts(validSales).values.toList()
      ..sort((a, b) {
        final byUnits = b.quantity.compareTo(a.quantity);
        if (byUnits != 0) return byUnits;
        final byRevenue = b.revenue.compareTo(a.revenue);
        return byRevenue != 0 ? byRevenue : a.name.compareTo(b.name);
      });

    final topProduct = topProducts.isEmpty ? null : topProducts.first;

    return [
      'Today\'s sales summary:'.tr,
      "",
      '- Gross sales: {amount}'.trArgs({'amount': _money(gross)}),
      '- Net sales: {amount}'.trArgs({'amount': _money(total)}),
      '- Orders: {n}'.trArgs({'n': orders}),
      '- Average order value: {amount}'.trArgs({'amount': _money(averageOrder)}),
      if (topProduct != null)
        '- Top product: {name} ({n} sold)'.trArgs({
          'name': topProduct.name,
          'n': topProduct.quantity.toStringAsFixed(0),
        }),
      if (orders == 0) '- No sales have been recorded today yet.'.tr,
    ].join('\n');
  }

  String _periodSalesSummary({
    required _StoreData data,
    required String title,
    required _DateRange range,
  }) {
    final sales = _salesInRange(data.sales, range);

    final total = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.netTotal);
    final gross = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.grossTotal);
    final discounts = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.discount);
    final refunds = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.refund);
    final orders = sales.where((sale) => !sale.isRefund).length;
    final averageOrder = orders == 0 ? 0.0 : total / orders;

    return [
      '$title:',
      "",
      '- Gross sales: {amount}'.trArgs({'amount': _money(gross)}),
      '- Net sales: {amount}'.trArgs({'amount': _money(total)}),
      '- Orders: {n}'.trArgs({'n': orders}),
      '- Average order value: {amount}'.trArgs({'amount': _money(averageOrder)}),
      '- Discounts: {amount}'.trArgs({'amount': _money(discounts)}),
      '- Refunds: {amount}'.trArgs({'amount': _money(refunds)}),
    ].join('\n');
  }

  String _topProductsThisWeek(_StoreData data) {
    final range = _currentWeekRange();
    final sales = _salesInRange(data.sales, range).where((sale) => !sale.isRefund).toList();

    final products =
        _aggregateProducts(sales).values.where((product) {
          return product.quantity > 0;
        }).toList()..sort((a, b) {
          final quantityCompare = b.quantity.compareTo(a.quantity);
          if (quantityCompare != 0) return quantityCompare;
          return b.revenue.compareTo(a.revenue);
        });

    if (products.isEmpty) {
      return 'No products have been sold this week yet.'.tr;
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return '{i}. {name}: {n} sold ({amount})'.trArgs({
        'i': index,
        'name': product.name,
        'n': product.quantity.toStringAsFixed(0),
        'amount': _money(product.revenue),
      });
    });

    return ['Top selling products this week:'.tr, '', ...lines].join('\n');
  }

  String _topRevenueProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range).where((sale) => !sale.isRefund).toList();

    final products = _aggregateProducts(sales).values.where((product) {
      return product.revenue > 0;
    }).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));

    if (products.isEmpty) {
      return 'No product revenue data found this month.'.tr;
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return '{i}. {name}: {amount} ({n} sold)'.trArgs({
        'i': index,
        'name': product.name,
        'amount': _money(product.revenue),
        'n': product.quantity.toStringAsFixed(0),
      });
    });

    return ['Top revenue products this month:'.tr, '', ...lines].join('\n');
  }

  String _slowMovingProducts(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range).where((sale) => !sale.isRefund).toList();

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
      return 'No products found in your inventory.'.tr;
    }

    final lines = products.take(10).toList().asMap().entries.map((entry) {
      final index = entry.key + 1;
      final product = entry.value;

      return '{i}. {name}: {n} sold'.trArgs({
        'i': index,
        'name': product.name,
        'n': product.quantity.toStringAsFixed(0),
      });
    });

    return ['Slow moving products this month:'.tr, '', ...lines].join('\n');
  }

  // Pair best sellers with slow-moving stock over the last 30 days.
  String _bundleOffers(_StoreData data) {
    if (data.products.isEmpty) {
      return 'No products found in your inventory.'.tr;
    }

    final from = DateTime.now().subtract(const Duration(days: 30));
    final recentSales = data.sales
        .where((sale) => !sale.isRefund && !sale.createdAt!.isBefore(from))
        .toList();
    final metrics = _aggregateProducts(recentSales);

    final offers = BundleOfferPlanner.plan([
      for (final product in data.products)
        BundleCandidate(
          key: product.key,
          name: product.name,
          stock: product.stock,
          soldRecently: metrics[product.key]?.quantity ?? 0,
          category: product.category,
          price: product.price,
        ),
    ]);

    if (offers.isEmpty) {
      return [
        'No bundle offers to suggest right now.'.tr,
        "",
        'Offers need at least one product that sells well and another product with stock that sells much less. Record more sales and try again.'
            .tr,
      ].join('\n');
    }

    final lines = <String>[];
    for (var i = 0; i < offers.length; i++) {
      final offer = offers[i];
      final slow = offer.slowMover;
      lines
        ..add(
          '{i}. Buy {anchor}, get {slow} {percent}% off'.trArgs({
            'i': i + 1,
            'anchor': offer.anchor.name,
            'slow': slow.name,
            'percent': offer.discountPercent,
          }),
        )
        ..add(
          '   - {name}: {n} sold (best seller)'.trArgs({
            'name': offer.anchor.name,
            'n': offer.anchor.soldRecently.toStringAsFixed(0),
          }),
        )
        ..add(
          '   - {name}: {n} sold, {stock} in stock'.trArgs({
            'name': slow.name,
            'n': slow.soldRecently.toStringAsFixed(0),
            'stock': slow.stock,
          }),
        );
      if (slow.price > 0) {
        lines.add(
          '   - Offer price: {from} → {to}'.trArgs({
            'from': _money(slow.price),
            'to': _money(offer.discountedPrice),
          }),
        );
      }
      if (offer.sameCategory) {
        lines.add(
          '   - {text}'.trArgs({'text': 'Same category, so customers are likely to want both'.tr}),
        );
      }
      lines.add("");
    }

    return [
      'Bundle offer ideas (last 30 days):'.tr,
      "",
      ...lines,
      'Each offer uses a popular product to help sell items that are not moving.'.tr,
      'Start an offer from Home → Offers & tips; cashiers get it automatically.'.tr,
    ].join('\n');
  }

  String _lowStockAlerts(_StoreData data) {
    if (data.products.isEmpty) {
      return 'No products found in your inventory.'.tr;
    }

    final lowStock = data.products.where((product) {
      return product.stock <= product.minStock;
    }).toList()..sort((a, b) => a.stock.compareTo(b.stock));

    if (lowStock.isEmpty) {
      return 'No low stock products were found right now.'.tr;
    }

    final lines = lowStock.take(10).map((product) {
      final status = (product.stock <= 0 ? 'Out of stock' : 'Low stock').tr;
      return '- {name}: {n} left ({status}, minimum {min})'.trArgs({
        'name': product.name,
        'n': product.stock,
        'status': status,
        'min': product.minStock,
      });
    });

    return ['Low stock alerts:'.tr, '', ...lines].join('\n');
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

    recommendations.sort((a, b) => b.recommendedQty.compareTo(a.recommendedQty));

    if (recommendations.isEmpty) {
      return 'No restock needed right now. Your inventory looks healthy.'.tr;
    }

    final lines = recommendations.take(10).map((item) {
      return '- {name}: current {n}, recommended reorder {qty}'.trArgs({
        'name': item.name,
        'n': item.currentStock,
        'qty': item.recommendedQty,
      });
    });

    return ['Restock recommendations:'.tr, '', ...lines].join('\n');
  }

  String _paymentSummary(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range).where((sale) => !sale.isRefund).toList();

    final payments = <String, double>{};

    for (final sale in sales) {
      payments[sale.paymentMethod] = (payments[sale.paymentMethod] ?? 0) + sale.netTotal;
    }

    if (payments.isEmpty) {
      return 'No payment data found for this month yet.'.tr;
    }

    final entries = payments.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final total = entries.fold<double>(0, (subtotal, entry) => subtotal + entry.value);

    final lines = entries.map((entry) {
      final percent = total == 0 ? 0 : (entry.value / total) * 100;
      return '- {method}: {amount} ({percent}%)'.trArgs({
        'method': entry.key.tr,
        'amount': _money(entry.value),
        'percent': percent.toStringAsFixed(1),
      });
    });

    return ['Payment methods this month:'.tr, '', ...lines].join('\n');
  }

  String _bestSalesHourToday(_StoreData data) {
    final range = _todayRange();
    final sales = _salesInRange(data.sales, range).where((sale) => !sale.isRefund).toList();

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
      return 'No sales have been recorded today yet.'.tr;
    }

    return [
      'Best sales hour today:'.tr,
      "",
      '- Hour: {hour}:00'.trArgs({'hour': bestHour.toString().padLeft(2, '0')}),
      '- Sales: {amount}'.trArgs({'amount': _money(bestAmount)}),
      '- Orders: {n}'.trArgs({'n': hourlyOrders[bestHour]}),
    ].join('\n');
  }

  String _netSalesSummary(_StoreData data) {
    final range = _currentMonthRange();
    final sales = _salesInRange(data.sales, range);

    final gross = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.grossTotal);
    final discounts = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.discount);
    final refunds = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.refund);
    final net = sales.fold<double>(0, (subtotal, sale) => subtotal + sale.netTotal);

    return [
      'Net sales summary this month:'.tr,
      "",
      '- Gross sales: {amount}'.trArgs({'amount': _money(gross)}),
      '- Discounts: {amount}'.trArgs({'amount': _money(discounts)}),
      '- Refunds: {amount}'.trArgs({'amount': _money(refunds)}),
      '- Net sales: {amount}'.trArgs({'amount': _money(net)}),
    ].join('\n');
  }

  String _storeOverview(_StoreData data) {
    final today = _salesInRange(data.sales, _todayRange());
    final month = _salesInRange(data.sales, _currentMonthRange());

    final todaySales = today.fold<double>(0, (subtotal, sale) => subtotal + sale.netTotal);
    final monthSales = month.fold<double>(0, (subtotal, sale) => subtotal + sale.netTotal);

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
      'Store overview:'.tr,
      "",
      '- Today sales: {amount}'.trArgs({'amount': _money(todaySales)}),
      '- Today orders: {n}'.trArgs({'n': todayOrders}),
      '- This month sales: {amount}'.trArgs({'amount': _money(monthSales)}),
      '- This month orders: {n}'.trArgs({'n': monthOrders}),
      '- Products in inventory: {n}'.trArgs({'n': data.products.length}),
      '- Low stock products: {n}'.trArgs({'n': lowStockCount}),
      if (topProduct != null)
        '- Top product this month: {name} ({n} sold)'.trArgs({
          'name': topProduct.name,
          'n': topProduct.quantity.toStringAsFixed(0),
        }),
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

    return _DateRange(start: DateTime(now.year, now.month), end: DateTime(now.year, now.month + 1));
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
    return Money.format(value);
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
                        _buildWelcome(),
                        _buildSuggestions(),
                      ] else ...[
                        for (final message in messages.skip(1))
                          _MessageBubble(message: message, onOpenReports: _openReports),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
      child: Row(
        children: [
          // The one AI mark on this screen.
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ShopPad Assistant'.tr,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.headline,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Local analysis'.tr,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'About this analysis mode'.tr,
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.muted),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Local analysis'.tr),
                content: Text(
                  'Answers are calculated on your device using English keyword rules and your store records. No paid AI service or API key is used. Loading store records may require a connection.'
                      .tr,
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('Got it'.tr)),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _isThinking || messages.length == 1 ? null : _startNewConversation,
            tooltip: 'New conversation'.tr,
            icon: const Icon(Icons.add_comment_outlined, color: AppColors.text),
          ),
        ],
      ),
    );
  }

  /// Opening card: what the assistant does, with no second AI icon.
  Widget _buildWelcome() {
    Widget pill(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.onHero),
          const SizedBox(width: 6),
          Text(
            label.tr,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.onHero,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your store.\nA clearer picture.'.tr,
            style: const TextStyle(
              fontSize: AppTypography.display,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: AppColors.onHero,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap a question, or ask about sales, stock and offers.'.tr,
            style: const TextStyle(
              fontSize: AppTypography.body,
              height: 1.5,
              color: AppColors.onHeroMuted,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(Icons.lock_outline, 'Your store data'),
              pill(Icons.visibility_outlined, 'Read-only insights'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    const prompts = [
      (Icons.trending_up_rounded, 'Sales snapshot', "Today's sales summary", 'How is today going?'),
      (Icons.inventory_2_outlined, 'Stock check', 'Low stock alerts', 'See what is running low'),
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
        Icons.local_offer_outlined,
        'Bundle offers',
        'Suggest bundle offers',
        'Pair best sellers with slow items',
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
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'A good place to start'.tr,
            style: TextStyle(fontSize: AppTypography.button, fontWeight: FontWeight.w700),
          ),
        ),
        // One light list instead of seven separate cards.
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (var i = 0; i < prompts.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 64),
                    InkWell(
                      onTap: _isThinking ? null : () => _sendMessage(prompts[i].$3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(AppSpacing.controlRadius - 2),
                              ),
                              child: Icon(prompts[i].$1, color: AppColors.primaryDark, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    prompts[i].$2.tr,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppTypography.body,
                                    ),
                                  ),
                                  Text(
                                    prompts[i].$4.tr,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: AppTypography.caption,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Points forward in both reading directions.
                            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 828),
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
                  decoration: InputDecoration(
                    hintText: 'Ask about your store…'.tr,
                    counterText: '',
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      borderSide: const BorderSide(color: AppColors.fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isThinking ? null : () => _sendMessage(),
                tooltip: 'Send message'.tr,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(50, 50),
                ),
                icon: _isThinking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 22),
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
            color: isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: isUser ? AppColors.primary : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUser ? Icons.person_outline_rounded : Icons.auto_awesome_rounded,
                    size: 17,
                    color: isUser ? AppColors.onBrandMuted : AppColors.primaryDark,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      isUser ? 'You' : 'Local analysis',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w700,
                        color: isUser ? AppColors.onBrandMuted : AppColors.primaryDark,
                      ),
                    ),
                  ),
                  if (!isUser)
                    IconButton(
                      tooltip: 'Copy answer'.tr,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: message.text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Answer copied'.tr)));
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
                style: TextStyle(
                  color: isUser ? AppColors.onBrand : AppColors.text,
                  fontSize: AppTypography.body,
                  height: 1.65,
                ),
              ),
              if (message.hasReport)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.bar_chart_rounded, size: 18),
                    label: Text('Open dashboard'.tr),
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
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(16),
    child: Row(
      children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Looking at your store data…'.tr,
            style: TextStyle(color: AppColors.muted, fontSize: AppTypography.body),
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

  const _ChatMessage({required this.isUser, required this.text, this.hasReport = false});
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
  final String category;
  final double price;

  const _ProductInfo({
    required this.key,
    required this.name,
    required this.stock,
    required this.minStock,
    this.category = '',
    this.price = 0,
  });
}

// Reuse the shared financial view instead of copying its computed fields.
class _SaleInfo {
  final DateTime? createdAt;
  final ReportSale _summary;
  final List<ReportSaleItem> items;

  _SaleInfo._(this.createdAt, this._summary)
    : items = _summary.items.map(ReportSaleItem.fromMap).toList();

  factory _SaleInfo.fromMap(Map<String, dynamic> data) =>
      _SaleInfo._(reportDate(data['createdAt']), ReportSale.fromMap(data));

  double get grossTotal => _summary.grossSales;
  double get netTotal => _summary.netSales;
  double get discount => _summary.discount;
  double get refund => _summary.refund;
  bool get isRefund => _summary.isRefund;
  String get paymentMethod => _summary.paymentMethod;
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
