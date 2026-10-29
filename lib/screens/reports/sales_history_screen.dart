import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../models/sale_record.dart';
import '../../services/report_download.dart';
import '../../utils/report_csv.dart';
import '../../widgets/sale_receipt_view.dart';

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
  final Future<void> Function(String csv, String filename)? exportReport;
  final Future<DateTimeRange?> Function(
    BuildContext context,
    DateTimeRange? current,
  )?
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
          (await _db
                  .collection('users')
                  .doc(uid)
                  .get()
                  .timeout(const Duration(seconds: 10)))
              .data();
      if (profile?['role'] != 'owner' ||
          profile?['isActive'] == false ||
          profile?['status'] == 'disabled') {
        throw StateError('Owner access required.');
      }
      final store = (profile?['storeCode'] ?? '').toString().trim();
      if (store.isEmpty) throw StateError('Store code not found.');
      final query = _db
          .collection('sales')
          .where('storeCode', isEqualTo: store);
      final results = await Future.wait([
        query.get().timeout(const Duration(seconds: 10)),
        _db
            .collection('users')
            .where('storeCode', isEqualTo: store)
            .get()
            .timeout(const Duration(seconds: 10)),
      ]);
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
            setState(
              () => _error = 'Could not refresh history. Tap refresh to retry.',
            );
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
    final records =
        snapshot.docs.map((doc) => _HistorySale(doc.id, doc.data())).toList()
          ..sort(
            (a, b) =>
                (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)),
          );
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
      if (_cashier != null &&
          !records.any((sale) => sale.cashierKey == _cashier)) {
        _cashier = null;
      }
    });
  }

  // Shared filtering for the visible list and CSV export.
  bool _inPeriod(_HistorySale sale) {
    if (_period == 'All time') return true;
    final date = sale.date;
    if (date == null) return false;
    if (_period == 'Custom range' && _dateRange != null) {
      final start = DateUtils.dateOnly(_dateRange!.start);
      final end = DateUtils.dateOnly(
        _dateRange!.end,
      ).add(const Duration(days: 1));
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
      [_payment, _product, _status].whereType<String>().length +
      (_correctionsOnly ? 1 : 0);
  Map<String, String> get _productOptions => {
    for (final sale in _sales)
      for (final item in sale.items)
        _itemKey(
          item,
        ): '${item['name'] ?? item['productName'] ?? 'Item'}${item['barcode'] == null ? '' : ' · ${item['barcode']}'}',
  };
  List<Map<String, dynamic>> _matchingItems(_HistorySale sale) => sale.items
      .where((item) => _product == null || _itemKey(item) == _product)
      .toList();
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
                  '${sale.receipt} ${sale.cashierName} ${sale.items.map((item) => '${item['name']} ${item['barcode']}').join(' ')}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
  }

  double _netReceipt(_HistorySale sale) {
    if (!sale.completed) return 0;
    final refund = _number(
      sale.data['refund'] ?? sale.data['refundAmount'],
    ).abs();
    return sale.refund
        ? -(refund > 0 ? refund : sale.total.abs())
        : math.max(0, sale.total - refund);
  }

  double _matchingSoldUnits(List<_HistorySale> sales) => sales
      .where((sale) => sale.completed && !sale.refund)
      .fold<double>(
        0,
        (total, sale) =>
            total +
            _matchingItems(
              sale,
            ).fold<double>(0, (units, item) => units + _quantity(item)),
      );
  double _matchingSoldValue(List<_HistorySale> sales) => sales
      .where((sale) => sale.completed && !sale.refund)
      .fold<double>(
        0,
        (total, sale) =>
            total +
            _matchingItems(sale).fold<double>(
              0,
              (value, item) => value + _quantity(item) * _price(item),
            ),
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
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(sheet).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Report filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: payment ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All payments'),
                    ),
                    ...methods.map(
                      (method) =>
                          DropdownMenuItem(value: method, child: Text(method)),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheet(() => payment = value == '' ? null : value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: product ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All products'),
                    ),
                    ...products.entries.map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheet(() => product = value == '' ? null : value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Receipt status',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All statuses'),
                    ),
                    ...statuses.map(
                      (state) =>
                          DropdownMenuItem(value: state, child: Text(state)),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheet(() => status = value == '' ? null : value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stock corrections only'),
                  value: corrections,
                  onChanged: (value) => setSheet(() => corrections = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: const Text('Apply filters'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, false),
                  child: const Text('Cancel'),
                ),
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
        'Receipt',
        'Date (local)',
        'Cashier',
        'Cashier ID',
        'Payment',
        'Status',
        'Type',
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
          sale.receipt,
          _exportDate(sale.date),
          sale.cashierName,
          sale.cashierUid,
          sale.method,
          sale.status,
          sale.refund ? 'Refund' : 'Sale',
          sale.total,
          _number(sale.data['refund'] ?? sale.data['refundAmount']).abs(),
          _netReceipt(sale),
          sale.correctionUnits,
          _product == null
              ? 'All products'
              : _productOptions[_product] ?? 'Selected product',
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
          'shoppad-sales-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
      await (widget.exportReport ?? downloadReport)(
        ReportCsv.encode(data),
        filename,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Filtered report prepared for download. Open the CSV in Excel.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not prepare the report. Retry the download.'),
          ),
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
      final name = (_profiles[sale.cashierUid]?['fullName'] ?? sale.cashierName)
          .toString();
      final row = totals.putIfAbsent(
        sale.cashierKey,
        () => _CashierTotal(sale.cashierKey, name),
      );
      row.orders++;
      row.fils +=
          (math.max(
                    0,
                    sale.total -
                        _number(
                          sale.data['refund'] ?? sale.data['refundAmount'],
                        ).abs(),
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
      title: Text(widget.showTopCashiers ? 'Top cashiers' : 'Sales history'),
      actions: [
        IconButton(
          tooltip: 'Refresh history',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Retry')),
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
                  decoration: const InputDecoration(labelText: 'Period'),
                  isExpanded: true,
                  items:
                      [
                            'All time',
                            'Today',
                            'Last 7 days',
                            'This month',
                            'Custom range',
                          ]
                          .map(
                            (period) => DropdownMenuItem(
                              value: period,
                              child: Text(period),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => _changePeriod(value!),
                ),
              ),
              if (_period == 'Custom range' && _dateRange != null)
                Text(
                  '${_dateLabel(_dateRange!.start).split(' ').first} — ${_dateLabel(_dateRange!.end).split(' ').first}',
                ),
              Expanded(
                child: widget.showTopCashiers ? _leaderboard() : _history(),
              ),
            ],
          ),
  );

  // Receipt list and independent cashier performance presentation.
  Widget _history() {
    final cashiers = <String, String>{
      for (final sale in _sales) sale.cashierKey: sale.cashierName,
    };
    final rows = _filteredSales;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Search receipt, cashier or product',
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
            decoration: const InputDecoration(labelText: 'Cashier'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All cashiers')),
              ...cashiers.entries.map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (value) =>
                setState(() => _cashier = value == '' ? null : value),
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
                  'Filters${_extraFilterCount == 0 ? '' : ' ($_extraFilterCount)'}',
                ),
              ),
              if (supportsReportDownload || widget.exportReport != null)
                OutlinedButton.icon(
                  onPressed: rows.isEmpty ? null : _export,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export CSV'),
                ),
              IconButton(
                tooltip: 'Clear report filters',
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            '${rows.length} receipts · Net receipt total: BD ${rows.fold<double>(0, (total, sale) => total + _netReceipt(sale)).toStringAsFixed(3)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (_product != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Selected product: ${_matchingSoldUnits(rows).toStringAsFixed(0)} units · BD ${_matchingSoldValue(rows).toStringAsFixed(3)} before receipt discounts/tax. Net receipt total includes other items.',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),

        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No receipts match these filters.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final sale = rows[index];
                    return Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: ListTile(
                        title: Text(
                          sale.receipt,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${sale.cashierName} · ${_dateLabel(sale.date)}\n${sale.method} · ${sale.refund ? 'Refund · ' : ''}${sale.status}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          'BD ${sale.total.toStringAsFixed(3)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _details(sale),
                      ),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Device-only receipts appear here after synchronization.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ),
      ],
    );
  }

  Widget _leaderboard() {
    final rows = _rankings();
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No completed cashier sales for this period.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final tied =
        rows
            .where(
              (row) =>
                  row.fils == rows.first.fils &&
                  row.orders == rows.first.orders,
            )
            .length >
        1;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Ranked by net sales value (BD), then completed receipt count. Owner sales, refund transactions and receipts without a cashier ID are excluded.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        ...rows.asMap().entries.map((entry) {
          final row = entry.value;
          final duplicateName =
              rows.where((other) => other.name == row.name).length > 1;
          final displayName = duplicateName
              ? '${row.name} · ${_shortId(row.key)}'
              : row.name;
          final best =
              row.fils == rows.first.fils && row.orders == rows.first.orders;
          return Card(
            color: best ? AppColors.accentSoft : null,
            child: ListTile(
              leading: best
                  ? const Icon(
                      Icons.emoji_events_outlined,
                      color: AppColors.primaryDark,
                    )
                  : Text('${entry.key + 1}'),
              title: Text(
                '${best ? (tied ? 'Joint top cashier · ' : 'Best cashier · ') : ''}$displayName',
              ),
              subtitle: Text('${row.orders} completed receipts'),
              trailing: Text(
                'BD ${(row.fils / 1000).toStringAsFixed(3)}',
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
                  tooltip: 'Close receipt',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('Date: ${_dateLabel(sale.date)}'),
                    Text('Cashier: ${sale.cashierName}'),
                    Text(
                      'Cashier ID: ${sale.cashierUid.isEmpty ? 'Not recorded' : sale.cashierUid}',
                    ),
                    Text('Payment: ${sale.method}'),
                    Text('Type: ${sale.refund ? 'Refund' : 'Sale'}'),
                    Text('Status: ${sale.status}'),
                    const Divider(),
                    ...sale.items.map((item) {
                      final quantity = _number(item['quantity'] ?? item['qty']);
                      final price = _number(item['price'] ?? item['unitPrice']);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (item['name'] ?? item['productName'] ?? 'Item')
                              .toString(),
                        ),
                        subtitle: Text(
                          'Barcode: ${item['barcode'] ?? 'Not recorded'}\n${quantity.toStringAsFixed(0)} × BD ${price.toStringAsFixed(3)}',
                        ),
                        trailing: Text(
                          'BD ${(quantity * price).toStringAsFixed(3)}',
                        ),
                      );
                    }),
                    const Divider(),
                    Text(
                      'Discount: BD ${_number(sale.data['discount']).toStringAsFixed(3)}',
                    ),
                    Text(
                      'Tax: BD ${_number(sale.data['tax']).toStringAsFixed(3)}',
                    ),
                    Text(
                      'Refund: BD ${_number(sale.data['refund'] ?? sale.data['refundAmount']).abs().toStringAsFixed(3)}',
                    ),
                    Text(
                      'Total: BD ${sale.total.toStringAsFixed(3)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    if (sale.data['stockCorrections'] is List) ...[
                      const Divider(),
                      const Text(
                        'Stock corrections',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...(sale.data['stockCorrections'] as List)
                          .whereType<Map>()
                          .map(
                            (row) => Text(
                              '${row['name'] ?? row['productId']}: ${row['stockBefore']} + ${row['addedQuantity']} − ${row['quantitySold']} = ${row['stockAfter']}',
                            ),
                          ),
                    ],
                    if (sale.exportableReceipt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('View receipt / PDF'),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => Scaffold(
                                  appBar: AppBar(title: const Text('Receipt')),
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
  String get receipt => (data['receiptNumber'] ?? 'RCPT-$id').toString();
  String get cashierUid =>
      (data['cashierUid'] ?? data['cashierId'] ?? '').toString();
  String get cashierName =>
      (data['cashierName'] ?? 'Unknown cashier').toString();
  String get cashierKey => cashierUid.isNotEmpty
      ? cashierUid
      : cashierName == 'Unknown cashier'
      ? 'unknown'
      : 'legacy:$cashierName';
  String get method =>
      (data['paymentMethod'] ?? data['paymentType'] ?? 'Not recorded')
          .toString();
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
  bool get completed =>
      ['completed', 'confirmed', 'paid'].contains(status.toLowerCase());
  bool get refund =>
      data['type']?.toString().toLowerCase() == 'refund' ||
      data['isRefund'] == true ||
      total < 0;
  double get total =>
      _number(data['total'] ?? data['totalAmount'] ?? data['grandTotal']);
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
      if (!completed ||
          refund ||
          date == null ||
          _number(data['tax']) != 0 ||
          _number(data['discount']) != 0 ||
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
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return parsed.isFinite ? parsed : 0;
}

String _dateLabel(DateTime? date) {
  if (date == null) return 'Date not recorded';
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}';
}

String _shortId(String value) =>
    value.length <= 6 ? value : value.substring(value.length - 6);

String _itemKey(Map<String, dynamic> item) {
  final barcode = (item['barcode'] ?? '').toString().trim();
  if (barcode.isNotEmpty) return 'barcode:$barcode';
  final id = (item['productId'] ?? item['id'] ?? '').toString().trim();
  return id.isNotEmpty
      ? 'id:$id'
      : 'name:${item['name'] ?? item['productName'] ?? 'Item'}';
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
