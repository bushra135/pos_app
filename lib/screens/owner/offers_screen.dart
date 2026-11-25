import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_language.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../app/money.dart';
import '../../models/report_sale.dart';
import '../../services/product_costs.dart';
import '../../services/sales_query.dart';
import '../../utils/active_offers.dart';
import '../../utils/bundle_offer_planner.dart';
import '../../utils/offer_tips.dart';
import '../../widgets/adaptive_layout.dart';

/// Owner only: bundle offers that pair best sellers with slow stock, and practical
/// promotion tips from the last 30 days of this store's sales.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key, this.firestore, this.currentUserId});

  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _Product {
  _Product(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get name => (data['name'] ?? '').toString();
  String get category => (data['category'] ?? '').toString();
  int get stock => (data['stock'] as num?)?.toInt() ?? 0;
  int get minStock => (data['minStock'] as num?)?.toInt() ?? 0;
  double get price => (data['price'] as num?)?.toDouble() ?? 0;
}

class _OffersScreenState extends State<OffersScreen> {
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  String? get _uid => (widget.currentUserId ?? () => FirebaseAuth.instance.currentUser?.uid)();

  bool _loading = true;
  String? _error;
  List<_Product> _products = const [];
  Map<String, double> _sold = const {};
  Map<String, double> _costs = const {};
  List<TipSale> _sales = const [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _uid;
      if (uid == null) throw StateError('signed out');
      final profile = (await _db.collection('users').doc(uid).get()).data() ?? const {};
      final code = (profile['storeCode'] ?? '').toString();
      if (code.isEmpty || profile['role'] != 'owner') throw StateError('owner only');
      final from = DateTime.now().subtract(const Duration(days: 30));
      final results = await Future.wait([
        _db.collection('products').where('storeCode', isEqualTo: code).get(),
        SalesQuery.since(_db, storeCode: code, from: from),
        ProductCosts.load(_db, code),
      ]);
      final productDocs = (results[0] as QuerySnapshot<Map<String, dynamic>>).docs;
      final saleDocs = results[1] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      final sold = <String, double>{};
      final sales = <TipSale>[];
      for (final doc in saleDocs) {
        final data = doc.data();
        if (data['type'] == 'refund') continue;
        final created = reportDate(data['createdAt']);
        if (created == null || created.isBefore(from)) continue;
        sales.add((
          createdAt: created,
          total: reportNumber(data, ['total']),
          offerDiscount: reportNumber(data, ['offerDiscount']),
        ));
        for (final item in (data['items'] as List?) ?? const []) {
          if (item is! Map) continue;
          final id = (item['productId'] ?? '').toString();
          if (id.isEmpty) continue;
          sold[id] = (sold[id] ?? 0) + ((item['quantity'] as num?)?.toDouble() ?? 0);
        }
      }
      if (!mounted) return;
      setState(() {
        _products = [for (final doc in productDocs) _Product(doc.id, doc.data())];
        _sold = sold;
        _sales = sales;
        _costs = results[2] as Map<String, double>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Offers not loaded: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load offers. Check your connection and try again.';
      });
    }
  }

  List<ActiveOffer> get _active => [
    for (final product in _products) ?ActiveOffer.fromProduct(product.id, product.data),
  ];

  List<BundleOffer> get _suggested {
    final running = {for (final offer in _active) offer.slowId};
    return BundleOfferPlanner.plan([
      for (final product in _products)
        if (!running.contains(product.id))
          BundleCandidate(
            key: product.id,
            name: product.name,
            stock: product.stock,
            soldRecently: _sold[product.id] ?? 0,
            category: product.category,
            price: product.price,
          ),
    ]);
  }

  int _safeMax(String productId) {
    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => _Product(productId, const {}),
    );
    return OfferMath.safeMaxPercent(price: product.price, cost: _costs[productId]);
  }

  Future<void> _write(String productId, Map<String, dynamic> fields, String done) async {
    setState(() => _busy.add(productId));
    try {
      await _db.collection('products').doc(productId).update({
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done.tr)));
      }
    } catch (e) {
      debugPrint('Offer update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update the offer. Try again.'.tr)));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(productId));
    }
  }

  Future<void> _start(BundleOffer suggestion) async {
    final max = _safeMax(suggestion.slowMover.key);
    if (max < ActiveOffer.minPercent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No safe discount for {name}: it would sell below cost.'.trArgs({
              'name': suggestion.slowMover.name,
            }),
          ),
        ),
      );
      return;
    }
    var percent = suggestion.discountPercent.clamp(ActiveOffer.minPercent, max);
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text('Start this offer'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buy {anchor}, get {slow} {percent}% off'.trArgs({
                  'anchor': suggestion.anchor.name,
                  'slow': suggestion.slowMover.name,
                  'percent': percent,
                }),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in const [10, 15, 20, 25, 30, 40])
                    if (option <= max)
                      ChoiceChip(
                        label: Text('$option%'),
                        selected: percent == option,
                        onSelected: (_) => setDialog(() => percent = option),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                (_costs.containsKey(suggestion.slowMover.key)
                        ? 'Up to {max}% keeps it above cost.'
                        : 'Up to {max}% (add a cost price to see the exact safe limit).')
                    .trArgs({'max': max}),
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
              const SizedBox(height: 4),
              Text(
                'Applied automatically when both are in the cart.'.tr,
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel'.tr)),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, percent),
              child: Text('Start offer'.tr),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _write(
      suggestion.slowMover.key,
      ActiveOffer.startFields(
        anchorId: suggestion.anchor.key,
        anchorName: suggestion.anchor.name,
        percent: chosen,
      ),
      'Offer started. Cashiers get it automatically.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Offers & tips'.tr),
        actions: [
          IconButton(
            tooltip: 'Refresh'.tr,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!.tr, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
                children: [ContentWidth(child: Column(children: _sections()))],
              ),
            ),
    );
  }

  List<Widget> _sections() {
    final active = _active;
    final suggested = _suggested;
    final tips = OfferTips.build(
      products: [
        for (final p in _products)
          (
            id: p.id,
            name: p.name,
            stock: p.stock,
            price: p.price,
            cost: _costs[p.id],
            minStock: p.minStock,
            soldUnits: _sold[p.id] ?? 0,
          ),
      ],
      sales: _sales,
      money: Money.format,
    );
    return [
      _heading('Active offers', Icons.local_offer_rounded),
      if (active.isEmpty)
        _note('No offers running. Start one of the suggestions below.')
      else
        for (final offer in active) _activeCard(offer),
      const SizedBox(height: 20),
      _heading('Suggested offers', Icons.auto_awesome_outlined),
      _note('Best sellers paired with products that sell slowly (last 30 days).'),
      if (suggested.isEmpty)
        _note(
          'Nothing to suggest yet. Offers need a product that sells well and another with stock that sells much less.',
        )
      else
        for (final offer in suggested) _suggestionCard(offer),
      const SizedBox(height: 20),
      _heading('Tips for your store', Icons.lightbulb_outline_rounded),
      if (tips.isEmpty)
        _note('Record more sales to get tips.')
      else
        for (final tip in tips) _tipCard(tip),
    ];
  }

  Widget _heading(String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryDark),
        const SizedBox(width: 8),
        Text(
          text.tr,
          style: const TextStyle(
            fontSize: AppTypography.section,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(text.tr, style: const TextStyle(color: AppColors.muted)),
    ),
  );

  BoxDecoration get _card => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    border: Border.all(color: AppColors.border),
  );

  Widget _activeCard(ActiveOffer offer) {
    final used = _sales.where((s) => s.offerDiscount > 0).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buy {anchor}, get {slow} {percent}% off'.trArgs({
                    'anchor': offer.anchorName,
                    'slow': offer.slowName,
                    'percent': offer.percent,
                  }),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '{name} sold {n} in 30 days'.trArgs({
                    'name': offer.slowName,
                    'n': (_sold[offer.slowId] ?? 0).toStringAsFixed(0),
                  }),
                  style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
                ),
                if (used > 0)
                  Text(
                    'Offers used on {n} receipts'.trArgs({'n': used}),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: AppTypography.caption,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _busy.contains(offer.slowId)
                ? null
                : () => _write(offer.slowId, ActiveOffer.stopFields, 'Offer stopped'),
            child: Text('Stop'.tr),
          ),
        ],
      ),
    );
  }

  Widget _suggestionCard(BundleOffer offer) {
    final slow = offer.slowMover;
    final max = _safeMax(slow.key);
    final percent = offer.discountPercent.clamp(0, max);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buy {anchor}, get {slow} {percent}% off'.trArgs({
              'anchor': offer.anchor.name,
              'slow': slow.name,
              'percent': percent,
            }),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '{anchor}: {a} sold · {slow}: {b} sold, {stock} in stock'.trArgs({
              'anchor': offer.anchor.name,
              'a': offer.anchor.soldRecently.toStringAsFixed(0),
              'slow': slow.name,
              'b': slow.soldRecently.toStringAsFixed(0),
              'stock': slow.stock,
            }),
            style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
          ),
          if (slow.price > 0)
            Text(
              'Offer price: {from} → {to}'.trArgs({
                'from': Money.format(slow.price),
                'to': Money.format(slow.price * (100 - percent) / 100),
              }),
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
          if (offer.sameCategory)
            Text(
              'Same category, so customers are likely to want both'.tr,
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _busy.contains(slow.key) ? null : () => _start(offer),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text('Start offer'.tr),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipCard(OfferTip tip) {
    final icon = switch (tip.kind) {
      'clearance' => Icons.inventory_2_outlined,
      'restock' => Icons.warning_amber_rounded,
      'slowDay' => Icons.calendar_today_outlined,
      'basket' => Icons.shopping_basket_outlined,
      'margin' => Icons.trending_down_rounded,
      'costs' => Icons.price_change_outlined,
      _ => Icons.insights_outlined,
    };
    final args = {
      for (final entry in tip.args.entries)
        entry.key: entry.key == 'day' ? entry.value.toString().tr : entry.value,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(tip.text.trArgs(args))),
        ],
      ),
    );
  }
}
