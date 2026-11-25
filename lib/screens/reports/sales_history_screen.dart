import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../models/sale_record.dart';
import '../../services/refund_service.dart';
import '../../services/report_download.dart';
import '../../utils/report_workbook.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/motion.dart';
import '../../widgets/sale_receipt_view.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';
import '../../app/app_spacing.dart';
import '../../utils/receipt_audit.dart';
import '../../app/app_typography.dart';

/// Owner-only, store-scoped history and a transparent cashier leaderboard.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
    this.firestore,
    this.currentUserId,
    this.now,
    this.exportReport,
    this.selectDateRange,
    this.showTopCashiers = false,
    this.initialCashier,
    this.initialPeriod = 'All time',
    this.initialDateRange,
  });
  final bool showTopCashiers;
  final String? initialCashier;
  final String initialPeriod;
  final DateTimeRange? initialDateRange;
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;
  final DateTime Function()? now;
  final Future<void> Function(String workbookBase64, String filename)? exportReport;
  final Future<DateTimeRange?> Function(BuildContext context, DateTimeRange? current)?
  selectDateRange;
  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _search = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  String? get _uid => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;
  final _profiles = <String, Map<String, dynamic>>{};
  List<_HistorySale> _sales = [];
  String? _ownerUid, _error, _cashier;
  String _period = 'All time', _query = '';
  String? _payment, _product, _status;
  bool _correctionsOnly = false;
  DateTimeRange? _dateRange;
  int _periodRevision = 0;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _cashier = widget.initialCashier;
    _period = widget.initialPeriod;
    _dateRange = widget.initialDateRange;
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  // Owner access and store-scoped live history.
  /// Current selling prices (product id -> price), to flag receipts sold below them.
  Map<String, double> _catalogPrices = const {};

  List<String> _issues(_HistorySale sale) =>
      ReceiptAudit.issues(sale.data, catalogPrices: _catalogPrices);

  Future<void> _load() async {
    final generation = ++_generation;
    await _subscription?.cancel();
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _uid;
      if (uid == null) throw StateError('Sign in as the store owner.');
      final profile =
          (await _db.collection('users').doc(uid).get().timeout(const Duration(seconds: 10)))
              .data();
      if (profile?['role'] != 'owner' ||
          profile?['isActive'] == false ||
          profile?['status'] == 'disabled') {
        throw StateError('Owner access required.');
      }
      final store = (profile?['storeCode'] ?? '').toString().trim();
      if (store.isEmpty) throw StateError('Store code not found.');
      final query = _db.collection('sales').where('storeCode', isEqualTo: store);
      final results = await Future.wait([
        query.get().timeout(const Duration(seconds: 10)),
        _db
            .collection('users')
            .where('storeCode', isEqualTo: store)
            .get()
            .timeout(const Duration(seconds: 10)),
        _db
            .collection('products')
            .where('storeCode', isEqualTo: store)
            .get()
            .timeout(const Duration(seconds: 10)),
      ]);
      _catalogPrices = {
        for (final product in results[2].docs)
          if (product.data()['price'] is num)
            product.id: (product.data()['price'] as num).toDouble(),
      };
      if (!mounted || generation != _generation || _uid != uid) return;
      _profiles.clear();
      for (final user in results[1].docs) {
        _profiles[user.id] = user.data();
        final authUid = (user.data()['uid'] ?? '').toString();
        if (authUid.isNotEmpty) _profiles[authUid] = user.data();
      }
      _ownerUid = uid;
      _accept(results[0]);
      _subscription = query.snapshots().listen(
        (snapshot) {
          if (mounted && generation == _generation && _uid == uid) {
            _accept(snapshot);
          }
        },
        onError: (Object error) {
          if (mounted && generation == _generation) {
            setState(() => _error = 'Could not refresh history. Tap refresh to retry.');
          }
        },
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error is StateError
              ? error.message.toString()
              : 'Could not load history. Check your connection and retry.';
        });
      }
    }
  }

  void _accept(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final records = snapshot.docs.map((doc) => _HistorySale(doc.id, doc.data())).toList()
      ..sort((a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)));
    setState(() {
      _sales = records;
      if (_product != null && !_productOptions.containsKey(_product)) {
        _product = null;
      }
      if (_payment != null && !records.any((sale) => sale.method == _payment)) {
        _payment = null;
      }
      if (_status != null && !records.any((sale) => sale.status == _status)) {
        _status = null;
      }
      _loading = false;
      _error = null;
      if (_cashier != null && !records.any((sale) => sale.cashierKey == _cashier)) {
        _cashier = null;
      }
    });
  }

  // Shared filtering for the visible list and Excel export.
  bool _inPeriod(_HistorySale sale) {
    if (_period == 'All time') return true;
    final date = sale.date;
    if (date == null) return false;
    if (_period == 'Custom range' && _dateRange != null) {
      final start = DateUtils.dateOnly(_dateRange!.start);
      final end = DateUtils.dateOnly(_dateRange!.end).add(const Duration(days: 1));
      return !date.isBefore(start) && date.isBefore(end);
    }
    final now = (widget.now?.call() ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final start = _period == 'Today'
        ? today
        : _period == 'Last 7 days'
        ? today.subtract(const Duration(days: 6))
        : DateTime(now.year, now.month);
    final end = _period == 'This month'
        ? DateTime(now.year, now.month + 1)
        : today.add(const Duration(days: 1));
    return !date.isBefore(start) && date.isBefore(end);
  }

  int get _extraFilterCount =>
      [_payment, _product, _status].whereType<String>().length + (_correctionsOnly ? 1 : 0);
  Map<String, String> get _productOptions => {
    for (final sale in _sales)
      for (final item in sale.items)
        _itemKey(
          item,
        ): '${item['name'] ?? item['productName'] ?? 'Item'}${item['barcode'] == null ? '' : ' · ${item['barcode']}'}',
  };
  List<Map<String, dynamic>> _matchingItems(_HistorySale sale) =>
      sale.items.where((item) => _product == null || _itemKey(item) == _product).toList();
  List<_HistorySale> get _filteredSales {
    final query = _query.toLowerCase().trim();
    return _sales
        .where(
          (sale) =>
              _inPeriod(sale) &&
              (_cashier == null || sale.cashierKey == _cashier) &&
              (_payment == null || sale.method == _payment) &&
              (_status == null || sale.status == _status) &&
              (!_correctionsOnly || sale.hasCorrections) &&
              (_product == null || _matchingItems(sale).isNotEmpty) &&
              (query.isEmpty ||
                  '${sale.receipt} ${sale.data['receiptNumber'] ?? ''} ${ReportWorkbook.reference('INV', sale.id)} ${ReportWorkbook.reference('CS', sale.cashierUid)} ${sale.cashierName} ${sale.items.map((item) => '${item['name']} ${item['barcode']}').join(' ')}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
  }

  double _netReceipt(_HistorySale sale) {
    if (!sale.completed) return 0;
    final refund = _number(sale.data['refund'] ?? sale.data['refundAmount']).abs();
    return sale.refund
        ? -(refund > 0 ? refund : sale.total.abs())
        : math.max(0, sale.total - refund);
  }

  double _matchingSoldUnits(List<_HistorySale> sales) => sales
      .where((sale) => sale.completed && !sale.refund)
      .fold<double>(
        0,
        (total, sale) =>
            total + _matchingItems(sale).fold<double>(0, (units, item) => units + _quantity(item)),
      );
  double _matchingSoldValue(List<_HistorySale> sales) => sales
      .where((sale) => sale.completed && !sale.refund)
      .fold<double>(
        0,
        (total, sale) =>
            total +
            _matchingItems(
              sale,
            ).fold<double>(0, (value, item) => value + _quantity(item) * _price(item)),
      );

  Future<void> _changePeriod(String value) async {
    FocusScope.of(context).unfocus();
    if (value != 'Custom range') {
      setState(() => _period = value);
      return;
    }
    final now = widget.now?.call() ?? DateTime.now();
    final DateTimeRange? range;
    final picker = widget.selectDateRange;
    if (picker != null) {
      range = await picker(context, _dateRange);
    } else {
      range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _dateRange,
        helpText: 'Select report dates',
        saveText: 'Apply',
      );
    }
    if (!mounted) return;
    setState(() {
      _periodRevision++;
      if (range != null) {
        _period = 'Custom range';
        _dateRange = range;
      }
    });
  }

  void _clearFilters() {
    FocusScope.of(context).unfocus();
    setState(() {
      _cashier = null;
      _payment = null;
      _product = null;
      _status = null;
      _correctionsOnly = false;
      _query = '';
      _search.clear();
      _period = 'All time';
      _dateRange = null;
      _periodRevision++;
    });
  }

  Future<void> _showFilters() async {
    FocusScope.of(context).unfocus();
    var payment = _payment, product = _product, status = _status;
    var corrections = _correctionsOnly;
    final products = _productOptions;
    final methods = _sales.map((sale) => sale.method).toSet().toList()..sort();
    final statuses = _sales.map((sale) => sale.status).toSet().toList()..sort();
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Report filters'.tr,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypography.headline),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: payment ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Payment method'.tr),
                  items: [
                    DropdownMenuItem(value: '', child: Text('All payments'.tr)),
                    ...methods.map(
                      (method) => DropdownMenuItem(value: method, child: Text(method)),
                    ),
                  ],
                  onChanged: (value) => setSheet(() => payment = value == '' ? null : value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: product ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Product'.tr),
                  items: [
                    DropdownMenuItem(value: '', child: Text('All products'.tr)),
                    ...products.entries.map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) => setSheet(() => product = value == '' ? null : value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Receipt status'.tr),
                  items: [
                    DropdownMenuItem(value: '', child: Text('All statuses'.tr)),
                    ...statuses.map((state) => DropdownMenuItem(value: state, child: Text(state))),
                  ],
                  onChanged: (value) => setSheet(() => status = value == '' ? null : value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Stock corrections only'.tr),
                  value: corrections,
                  onChanged: (value) => setSheet(() => corrections = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: Text('Apply filters'.tr),
                ),
                TextButton(onPressed: () => Navigator.pop(sheet, false), child: Text('Cancel'.tr)),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted && apply == true) {
      setState(() {
        _payment = payment;
        _product = product;
        _status = status;
        _correctionsOnly = corrections;
      });
    }
  }

  // Export the filtered snapshot without changing saved sales.
  Future<void> _export() async {
    final rows = _filteredSales;
    if (rows.isEmpty || _uid != _ownerUid) return;
    final data = <List<Object?>>[
      [
        'Receipt no.',
        'Date (local)',
        'Cashier',
        'Cashier code',
        'Payment',
        'Status',
        'Receipt total (BD)',
        'Recorded refund (BD)',
        'Net completed receipt (BD)',
        'Stock correction units',
        'Product filter',
        'Matching sold units',
        'Matching item value before discount/tax (BD)',
        'Items',
      ],
      for (final sale in rows)
        [
          ReportWorkbook.reference('INV', sale.id),
          _exportDate(sale.date),
          sale.cashierName,
          ReportWorkbook.reference('CS', sale.cashierUid),
          sale.method,
          sale.refund ? 'Refund · ${sale.status}' : sale.status,
          sale.total,
          _number(sale.data['refund'] ?? sale.data['refundAmount']).abs(),
          _netReceipt(sale),
          sale.correctionUnits,
          _product == null ? 'All products' : _productOptions[_product] ?? 'Selected product',
          _matchingSoldUnits([sale]),
          _matchingSoldValue([sale]),
          sale.items
              .map(
                (item) =>
                    '${item['name'] ?? item['productName'] ?? 'Item'} × ${_quantity(item).toStringAsFixed(0)}',
              )
              .join(' | '),
        ],
    ];
    try {
      final now = widget.now?.call() ?? DateTime.now();
      final filename =
          'shoppad-sales-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';
      await (widget.exportReport ?? downloadReport)(
        base64Encode(ReportWorkbook.encode(data)),
        filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Filtered report prepared for download. Open the Excel workbook.'.tr),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare the report. Retry the download.'.tr)),
        );
      }
    }
  }

  // Rank cashier IDs using integer fils to avoid floating-point ties.
  List<_CashierTotal> _rankings() {
    final totals = <String, _CashierTotal>{};
    for (final sale in _sales.where(_inPeriod)) {
      if (!sale.completed ||
          sale.refund ||
          sale.cashierUid.isEmpty ||
          sale.cashierKey == 'unknown' ||
          sale.cashierUid == _ownerUid ||
          _profiles[sale.cashierUid]?['role'] == 'owner') {
        continue;
      }
      final name = (_profiles[sale.cashierUid]?['fullName'] ?? sale.cashierName).toString();
      final row = totals.putIfAbsent(sale.cashierKey, () => _CashierTotal(sale.cashierKey, name));
      row.orders++;
      row.fils +=
          (math.max(
                    0,
                    sale.total - _number(sale.data['refund'] ?? sale.data['refundAmount']).abs(),
                  ) *
                  1000)
              .round();
    }
    return totals.values.toList()..sort((a, b) {
      final revenue = b.fils.compareTo(a.fils);
      if (revenue != 0) return revenue;
      final orders = b.orders.compareTo(a.orders);
      return orders != 0 ? orders : a.key.compareTo(b.key);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text((widget.showTopCashiers ? 'Top cashiers' : 'Sales history').tr),
      actions: [
        IconButton(
          tooltip: 'Refresh history'.tr,
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const ListSkeleton(leading: false)
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: Text('Retry'.tr)),
                ],
              ),
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('period-$_periodRevision'),
                  initialValue: _period,
                  decoration: InputDecoration(labelText: 'Period'.tr),
                  isExpanded: true,
                  items: ['All time', 'Today', 'Last 7 days', 'This month', 'Custom range']
                      .map((period) => DropdownMenuItem(value: period, child: Text(period.tr)))
                      .toList(),
                  onChanged: (value) => _changePeriod(value!),
                ),
              ),
              if (_period == 'Custom range' && _dateRange != null)
                Text(
                  '${_dateLabel(_dateRange!.start).split(' ').first} — ${_dateLabel(_dateRange!.end).split(' ').first}',
                ),
              Expanded(child: widget.showTopCashiers ? _leaderboard() : _history()),
            ],
          ),
  );

  // Receipt list and independent cashier performance presentation.
  Widget _history() {
    final cashiers = <String, String>{for (final sale in _sales) sale.cashierKey: sale.cashierName};
    final rows = _filteredSales;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search receipt, cashier or product'.tr,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            key: ValueKey(_cashier),
            initialValue: _cashier ?? '',
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Cashier'.tr),
            items: [
              DropdownMenuItem(value: '', child: Text('All cashiers'.tr)),
              ...cashiers.entries.map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _cashier = value == '' ? null : value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _showFilters,
                icon: const Icon(Icons.filter_alt_outlined),
                label: Text(
                  _extraFilterCount == 0
                      ? 'Filters'.tr
                      : 'Filters ({n})'.trArgs({'n': _extraFilterCount}),
                ),
              ),
              if (supportsReportDownload || widget.exportReport != null)
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : _export,
                  icon: const Icon(Icons.download_outlined),
                  label: Text('Export to Excel'.tr),
                ),
              IconButton(
                tooltip: 'Clear report filters'.tr,
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '{n} receipts · Net receipt total: {total}'.trArgs({
              'n': rows.length,
              'total': Money.format(
                rows.fold<double>(0, (total, sale) => total + _netReceipt(sale)),
              ),
            }),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (_product != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Selected product: {units} units · {value} before receipt discounts/tax. Net receipt total includes other items.'
                  .trArgs({
                    'units': _matchingSoldUnits(rows).toStringAsFixed(0),
                    'value': Money.format(_matchingSoldValue(rows)),
                  }),
              style: const TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
            ),
          ),

        Expanded(
          child: rows.isEmpty
              ? AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No receipts found'.tr,
                  message: 'No receipts match these filters.'.tr,
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => FadeSlideIn(
                    index: index,
                    child: Builder(
                      builder: (context) {
                        final sale = rows[index];
                        return Card(
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    sale.receipt,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: AppTypography.button,
                                    ),
                                  ),
                                ),
                                if (_issues(sale).isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                                    ),
                                    child: Text(
                                      'Review'.tr,
                                      style: const TextStyle(
                                        color: AppColors.warning,
                                        fontSize: AppTypography.caption,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${sale.cashierName} · ${_dateLabel(sale.date)}\n${sale.method.tr} · ${sale.refund ? 'Refund · '.tr : ''}${sale.status.tr}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              Money.format(sale.total),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: AppTypography.subtitle,
                                color: sale.refund ? AppColors.danger : AppColors.text,
                              ),
                            ),
                            onTap: () => _details(sale),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Device-only receipts appear here after synchronization.'.tr,
            style: TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  Widget _leaderboard() {
    final rows = _rankings();
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No completed cashier sales for this period.'.tr,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final tied =
        rows.where((row) => row.fils == rows.first.fils && row.orders == rows.first.orders).length >
        1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Ranked by net sales value (BD), then completed receipt count. Owner sales, refund transactions and receipts without a cashier ID are excluded.'
              .tr,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        ...rows.asMap().entries.map((entry) {
          final row = entry.value;
          final duplicateName = rows.where((other) => other.name == row.name).length > 1;
          final displayName = duplicateName ? '${row.name} · ${_shortId(row.key)}' : row.name;
          final best = row.fils == rows.first.fils && row.orders == rows.first.orders;
          return Card(
            color: best ? AppColors.accentSoft : null,
            child: ListTile(
              leading: best
                  ? const Icon(Icons.emoji_events_outlined, color: AppColors.primaryDark)
                  : Text('${entry.key + 1}'),
              title: Text(
                '${best ? (tied ? 'Joint top cashier · ' : 'Best cashier · ').tr : ''}$displayName',
              ),
              subtitle: Text('{n} completed receipts'.trArgs({'n': row.orders})),
              trailing: Text(
                Money.format((row.fils / 1000)),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SalesHistoryScreen(
                    firestore: _db,
                    currentUserId: widget.currentUserId,
                    now: widget.now,
                    initialCashier: row.key,
                    initialPeriod: _period,
                    initialDateRange: _dateRange,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Owner-approved return: choose units per item, then stock and reports update.
  Future<void> _startRefund(_HistorySale sale) async {
    final messenger = ScaffoldMessenger.of(context);
    final storeCode = (sale.data['storeCode'] ?? '').toString();
    final lines = <String, ({String name, double price, int sold})>{};
    for (final item in sale.items) {
      final id = (item['productId'] ?? '').toString();
      if (id.isEmpty) continue;
      final previous = lines[id];
      lines[id] = (
        name: (item['name'] ?? 'Item').toString(),
        price: _number(item['price']),
        sold: (previous?.sold ?? 0) + _number(item['quantity']).toInt(),
      );
    }
    if (lines.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('This receipt has no returnable items.'.tr)));
      return;
    }
    Map<String, int> already;
    try {
      already = await RefundService.refundedQuantities(
        _db,
        storeCode: storeCode,
        originalSaleId: sale.id,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not check earlier returns. Try again.'.tr)),
      );
      return;
    }
    if (!mounted) return;
    final available = {
      for (final entry in lines.entries)
        entry.key: (
          name: entry.value.name,
          price: entry.value.price,
          left: entry.value.sold - (already[entry.key] ?? 0),
        ),
    }..removeWhere((_, line) => line.left <= 0);
    if (available.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('Everything on this receipt was already returned.'.tr)),
      );
      return;
    }
    final paidShare = _number(sale.data['subtotal']) > 0 && sale.total > 0
        ? sale.total / _number(sale.data['subtotal'])
        : 1.0;
    final chosen = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _RefundDialog(receipt: sale.receipt, lines: available, paidShare: paidShare),
    );
    if (chosen == null || chosen.values.every((qty) => qty <= 0)) return;
    try {
      final uid = _uid ?? '';
      final amount = await RefundService.refund(
        _db,
        originalSaleId: sale.id,
        original: sale.data,
        quantities: chosen,
        ownerUid: uid,
        ownerName: (_profiles[uid]?['fullName'] ?? 'Owner').toString(),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Refunded {amount} · stock updated'.trArgs({'amount': Money.format(amount)}),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : 'Refund failed. Try again.')),
      );
    }
  }

  Future<void> _details(_HistorySale sale) async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: Column(
            children: [
              ListTile(
                title: Text(sale.receipt),
                trailing: IconButton(
                  tooltip: 'Close receipt'.tr,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('Date: {date}'.trArgs({'date': _dateLabel(sale.date)})),
                    Text('Cashier: {name}'.trArgs({'name': sale.cashierName})),
                    Text(
                      'Cashier ID: {id}'.trArgs({
                        'id': sale.cashierUid.isEmpty ? 'Not recorded'.tr : sale.cashierUid,
                      }),
                    ),
                    Text('Payment: {method}'.trArgs({'method': sale.method.tr})),
                    Text('Type: {type}'.trArgs({'type': (sale.refund ? 'Refund' : 'Sale').tr})),
                    Text('Status: {status}'.trArgs({'status': sale.status.tr})),
                    // What looked unusual, so the owner knows what to check.
                    for (final issue in _issues(sale))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.flag_outlined, size: 18, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                (ReceiptAudit.messages[issue] ?? issue).tr,
                                style: const TextStyle(color: AppColors.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(),
                    ...sale.items.map((item) {
                      final quantity = _number(item['quantity'] ?? item['qty']);
                      final price = _number(item['price'] ?? item['unitPrice']);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((item['name'] ?? item['productName'] ?? 'Item').toString()),
                        subtitle: Text(
                          '{barcode}\n{qty} × {price}'.trArgs({
                            'barcode': 'Barcode: {code}'.trArgs({
                              'code': item['barcode'] ?? 'Not recorded'.tr,
                            }),
                            'qty': quantity.toStringAsFixed(0),
                            'price': Money.format(price),
                          }),
                        ),
                        trailing: Text(Money.format((quantity * price))),
                      );
                    }),
                    const Divider(),
                    Text(
                      'Discount: {amount}'.trArgs({
                        'amount': Money.format(_number(sale.data['discount'])),
                      }),
                    ),
                    Text(
                      'Tax: {amount}'.trArgs({'amount': Money.format(_number(sale.data['tax']))}),
                    ),
                    Text(
                      'Refund: {amount}'.trArgs({
                        'amount': Money.format(
                          _number(sale.data['refund'] ?? sale.data['refundAmount']).abs(),
                        ),
                      }),
                    ),
                    Text(
                      'Total: {amount}'.trArgs({'amount': Money.format(sale.total)}),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTypography.headline,
                      ),
                    ),
                    if (sale.data['stockCorrections'] is List) ...[
                      const Divider(),
                      Text('Stock corrections'.tr, style: TextStyle(fontWeight: FontWeight.bold)),
                      ...(sale.data['stockCorrections'] as List).whereType<Map>().map(
                        (row) => Text(
                          '${row['name'] ?? row['productId']}: ${row['stockBefore']} + ${row['addedQuantity']} − ${row['quantitySold']} = ${row['stockAfter']}',
                        ),
                      ),
                    ],
                    if (!sale.refund && sale.status == 'completed')
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.assignment_return_outlined),
                          label: Text('Refund items'.tr),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _startRefund(sale);
                          },
                        ),
                      ),
                    if (sale.exportableReceipt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.receipt_long),
                          label: Text('View receipt / PDF'.tr),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => Scaffold(
                                  appBar: AppBar(title: Text('Receipt'.tr)),
                                  body: SaleReceiptView(
                                    sale: sale.exportableReceipt!,
                                    status: 'Synchronized',
                                    actionLabel: 'Back to history',
                                    actionIcon: Icons.history,
                                    onNewSale: () => Navigator.pop(context),
                                  ),
                                ),
                              ),
                            );
                          },
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

// Read-only history adapters for current and legacy documents.
class _HistorySale {
  _HistorySale(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  /// The sequential invoice number when the sale has one (newer receipts), else the
  /// receipt id.
  String get receipt => (data['invoiceNumber'] ?? data['receiptNumber'] ?? 'RCPT-$id').toString();
  String get cashierUid => (data['cashierUid'] ?? data['cashierId'] ?? '').toString();
  String get cashierName => (data['cashierName'] ?? 'Unknown cashier').toString();
  String get cashierKey => cashierUid.isNotEmpty
      ? cashierUid
      : cashierName == 'Unknown cashier'
      ? 'unknown'
      : 'legacy:$cashierName';
  String get method => (data['paymentMethod'] ?? data['paymentType'] ?? 'Not recorded').toString();
  String get status => (data['status'] ?? 'completed').toString();
  int get correctionUnits => data['stockCorrectionUnits'] is num
      ? (data['stockCorrectionUnits'] as num).toInt()
      : data['stockCorrections'] is List
      ? (data['stockCorrections'] as List).whereType<Map>().fold<int>(
          0,
          (total, row) => total + _number(row['addedQuantity']).toInt(),
        )
      : 0;
  bool get hasCorrections => correctionUnits > 0;
  bool get completed => ['completed', 'confirmed', 'paid'].contains(status.toLowerCase());
  bool get refund =>
      data['type']?.toString().toLowerCase() == 'refund' || data['isRefund'] == true || total < 0;
  double get total => _number(data['total'] ?? data['totalAmount'] ?? data['grandTotal']);
  List<Map<String, dynamic>> get items =>
      (data['items'] ?? data['cartItems'] ?? data['products']) is List
      ? ((data['items'] ?? data['cartItems'] ?? data['products']) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : [];
  DateTime? get date {
    final value = data['createdAt'];
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is num && value.isFinite && value.abs() <= 8640000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
    }
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  }

  SaleRecord? get exportableReceipt {
    try {
      // VAT and discounts are part of the receipt record now; only refunds and
      // incomplete records are left out.
      if (!completed ||
          refund ||
          date == null ||
          _number(data['refund'] ?? data['refundAmount']) != 0) {
        return null;
      }
      final receipt = SaleRecord.fromJson({
        ...data,
        'id': id,
        'createdAt': date!.toUtc().toIso8601String(),
      });
      return (receipt.total - total).abs() < 0.00001 ? receipt : null;
    } catch (_) {
      return null;
    }
  }
}

class _CashierTotal {
  _CashierTotal(this.key, this.name);
  final String key, name;
  int orders = 0, fils = 0;
}

double _number(dynamic value) {
  final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  return parsed.isFinite ? parsed : 0;
}

String _dateLabel(DateTime? date) {
  if (date == null) return 'Date not recorded';
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}';
}

String _shortId(String value) => value.length <= 6 ? value : value.substring(value.length - 6);

String _itemKey(Map<String, dynamic> item) {
  final barcode = (item['barcode'] ?? '').toString().trim();
  if (barcode.isNotEmpty) return 'barcode:$barcode';
  final id = (item['productId'] ?? item['id'] ?? '').toString().trim();
  return id.isNotEmpty ? 'id:$id' : 'name:${item['name'] ?? item['productName'] ?? 'Item'}';
}

double _quantity(Map<String, dynamic> item) =>
    _number(item['quantity'] ?? item['qty'] ?? item['count']);
double _price(Map<String, dynamic> item) =>
    _number(item['price'] ?? item['unitPrice'] ?? item['salePrice']);
String _exportDate(DateTime? date) {
  if (date == null) return '';
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}

/// Picks how many units of each item the customer is returning.
class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.receipt, required this.lines, required this.paidShare});

  final String receipt;
  final Map<String, ({String name, double price, int left})> lines;
  final double paidShare;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final Map<String, int> _qty = {for (final id in widget.lines.keys) id: 0};

  @override
  Widget build(BuildContext context) {
    final amount = widget.lines.entries.fold<double>(
      0,
      (running, entry) => running + entry.value.price * (_qty[entry.key] ?? 0) * widget.paidShare,
    );
    return AlertDialog(
      title: Text('Refund · {receipt}'.trArgs({'receipt': widget.receipt})),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in widget.lines.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Up to {n} · {price} each'.trArgs({
                                'n': entry.value.left,
                                'price': Money.format(entry.value.price),
                              }),
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'One less {name}'.trArgs({'name': entry.value.name}),
                        onPressed: (_qty[entry.key] ?? 0) > 0
                            ? () => setState(() => _qty[entry.key] = _qty[entry.key]! - 1)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${_qty[entry.key]}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        tooltip: 'Return one {name}'.trArgs({'name': entry.value.name}),
                        onPressed: (_qty[entry.key] ?? 0) < entry.value.left
                            ? () => setState(() => _qty[entry.key] = _qty[entry.key]! + 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Text(
                'Refund to customer: ${Money.format(amount)}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
        FilledButton(
          onPressed: amount > 0 ? () => Navigator.pop(context, _qty) : null,
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: Text('Confirm refund'.tr),
        ),
      ],
    );
  }
}
