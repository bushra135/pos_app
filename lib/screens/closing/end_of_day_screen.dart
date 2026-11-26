import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/report_sale.dart';
import '../../services/sales_query.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';

/// Totals for one business day: what was sold, how it was paid, and the VAT inside it.
class DaySummary {
  DaySummary._({
    required this.receipts,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.net,
    required this.vat,
    required this.byPayment,
  });

  factory DaySummary.fromSales(Iterable<Map<String, dynamic>> sales) {
    var receipts = 0;
    double gross = 0, discounts = 0, refunds = 0, net = 0, vat = 0;
    final byPayment = <String, double>{};
    for (final data in sales) {
      final status = (data['status'] ?? 'completed').toString();
      if (status == 'pending') continue;
      final sale = ReportSale.fromMap(data);
      gross += sale.grossSales;
      discounts += sale.discount;
      refunds += sale.refund;
      net += sale.netSales;
      if (!sale.isRefund) receipts++;
      // Refunds store negative VAT.
      vat += reportNumber(data, ['tax', 'vat']);
      byPayment[sale.paymentMethod] = (byPayment[sale.paymentMethod] ?? 0) + sale.netSales;
    }
    return DaySummary._(
      receipts: receipts,
      gross: gross,
      discounts: discounts,
      refunds: refunds,
      net: net,
      vat: vat,
      byPayment: byPayment,
    );
  }

  final int receipts;
  final double gross, discounts, refunds, net, vat;
  final Map<String, double> byPayment;

  double get cashSales => byPayment['Cash'] ?? 0;

  /// Cash that should be in the drawer: the opening float plus today's cash sales.
  double expectedCash(double openingFloat) => openingFloat + cashSales;
}

/// End-of-day closing (Z-report): today's totals and a cash drawer count.
class EndOfDayScreen extends StatefulWidget {
  const EndOfDayScreen({super.key, this.firestore, this.currentUserId, this.now});

  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;
  final DateTime Function()? now;

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

/// End-of-day (Z) report: sales, refunds and expected cash, with a cash count.
class _EndOfDayScreenState extends State<EndOfDayScreen> {
  final _floatController = TextEditingController();
  final _countedController = TextEditingController();

  bool _loading = true;
  String? _error;
  DaySummary? _summary;
  String _storeName = '';
  String _personName = '';
  bool _storeWide = false;
  late final DateTime _day;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    final now = (widget.now ?? DateTime.now)();
    _day = DateTime(now.year, now.month, now.day);
    _load();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _countedController.dispose();
    super.dispose();
  }

  /// Loads today's receipts: the whole store for an owner, own sales for a cashier.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = widget.currentUserId != null
          ? widget.currentUserId!()
          : FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in to close the day.');
      final profile = (await _db.collection('users').doc(uid).get()).data() ?? {};
      final storeCode = (profile['storeCode'] ?? '').toString();
      if (storeCode.isEmpty) throw StateError('Store not found for this account.');
      // Owners close the whole store; cashiers close their own drawer.
      final storeWide = profile['role'] == 'owner';
      final docs = await SalesQuery.since(
        _db,
        storeCode: storeCode,
        cashierUid: storeWide ? null : uid,
        from: _day,
        timeout: const Duration(seconds: 15),
      );
      final end = _day.add(const Duration(days: 1));
      final today = docs.map((doc) => doc.data()).where((data) {
        final created = reportDate(data['createdAt']);
        return created != null && created.isBefore(end);
      });
      if (!mounted) return;
      setState(() {
        _summary = DaySummary.fromSales(today);
        _storeName = (profile['storeName'] ?? '').toString();
        _personName = (profile['fullName'] ?? '').toString();
        _storeWide = storeWide;
        _loading = false;
      });
    } catch (e) {
      debugPrint('End of day error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load today\'s sales. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  double _amount(TextEditingController controller) => double.tryParse(controller.text.trim()) ?? 0;

  String get _dateLabel =>
      '${_day.day.toString().padLeft(2, '0')}/${_day.month.toString().padLeft(2, '0')}/${_day.year}';

  /// Builds the report as a PDF (Arabic-capable font) and opens the share sheet.
  Future<void> _sharePdf() async {
    final summary = _summary;
    if (summary == null) return;
    final opening = _amount(_floatController);
    final countedText = _countedController.text.trim();
    final counted = _amount(_countedController);
    final expected = summary.expectedCash(opening);
    try {
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
      final doc = pw.Document();
      pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label),
            pw.Text(value, style: pw.TextStyle(fontSize: bold ? 14 : 11)),
          ],
        ),
      );
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: font),
          margin: const pw.EdgeInsets.all(32),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _storeName.isEmpty ? 'ShopPad' : _storeName,
                style: const pw.TextStyle(fontSize: AppTypography.headline),
              ),
              pw.Text(
                'End of day report (Z-report) · $_dateLabel',
                style: const pw.TextStyle(fontSize: AppTypography.body),
              ),
              pw.Text(_storeWide ? 'Whole store'.tr : 'Cashier: $_personName'),
              pw.Divider(),
              row('Receipts', '${summary.receipts}'),
              row('Gross sales', Money.format(summary.gross)),
              row('Discounts', '- ${Money.format(summary.discounts)}'),
              row('Refunds', '- ${Money.format(summary.refunds)}'),
              row('Net sales', Money.format(summary.net), bold: true),
              row('VAT included (10%)', Money.format(summary.vat)),
              pw.Divider(),
              for (final entry in summary.byPayment.entries)
                row(entry.key, Money.format(entry.value)),
              pw.Divider(),
              row('Opening float', Money.format(opening)),
              row('Expected cash in drawer', Money.format(expected)),
              if (countedText.isNotEmpty) ...[
                row('Counted cash', Money.format(counted)),
                row('Difference', Money.format(counted - expected), bold: true),
              ],
              pw.SizedBox(height: 24),
              pw.Text('Signature: ____________________'.tr),
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'z-report-${_day.year}-${_day.month}-${_day.day}.pdf',
        bounds: Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100),
      );
    } catch (e) {
      debugPrint('Z-report export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create the PDF. Try again.'.tr)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('End of day'.tr)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text('Try again'.tr)),
                    ],
                  ),
                ),
              )
            : _buildReport(_summary!),
      ),
    );
  }

  /// The report body: totals, payment split, opening float, counted cash and difference.
  Widget _buildReport(DaySummary summary) {
    final opening = _amount(_floatController);
    final expected = summary.expectedCash(opening);
    final counted = _amount(_countedController);
    final hasCount = _countedController.text.trim().isNotEmpty;
    final difference = counted - expected;
    final balanced = difference.abs() < 0.0005;

    Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label.tr, style: const TextStyle(color: AppColors.muted)),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 16 : AppTypography.body,
              color: color ?? AppColors.text,
            ),
          ),
        ],
      ),
    );

    Widget card(String title, List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.tr,
            style: const TextStyle(fontSize: AppTypography.section, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.hero,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_storeWide ? 'Whole store'.tr : 'My drawer'.tr} · $_dateLabel',
                style: const TextStyle(color: AppColors.onHeroMuted, fontWeight: FontWeight.w700),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  Money.format(summary.net),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onHero,
                  ),
                ),
              ),
              Text(
                (summary.receipts == 1 ? '1 receipt today' : '{n} receipts today').trArgs({
                  'n': summary.receipts,
                }),
                style: const TextStyle(color: AppColors.onHeroMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        card('Sales', [
          row('Gross sales', Money.format(summary.gross)),
          row('Discounts', '- ${Money.format(summary.discounts)}'),
          row('Refunds', '- ${Money.format(summary.refunds)}'),
          const Divider(height: 20),
          row('Net sales', Money.format(summary.net), bold: true),
          row('VAT included (10%)', Money.format(summary.vat)),
        ]),
        const SizedBox(height: 14),
        card('By payment method', [
          if (summary.byPayment.isEmpty)
            Text('No payments yet today.'.tr, style: TextStyle(color: AppColors.muted)),
          for (final entry in summary.byPayment.entries) row(entry.key, Money.format(entry.value)),
        ]),
        const SizedBox(height: 14),
        card('Cash drawer', [
          Text(
            'Count the cash in the drawer and enter it below.'.tr,
            style: TextStyle(color: AppColors.muted, fontSize: AppTypography.body),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _floatController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Opening float (cash at start of day)'.tr,
              suffixText: Money.symbol,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countedController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Counted cash'.tr, suffixText: Money.symbol),
          ),
          const SizedBox(height: 10),
          row('Expected in drawer', Money.format(expected), bold: true),
          if (hasCount)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: balanced
                    ? AppColors.successSoft
                    : difference > 0
                    ? AppColors.warningSoft
                    : AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
              ),
              child: Row(
                children: [
                  Icon(
                    balanced ? Icons.check_circle_outline : Icons.error_outline,
                    color: balanced
                        ? AppColors.success
                        : difference > 0
                        ? AppColors.warning
                        : AppColors.danger,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      balanced
                          ? 'Drawer balanced'.tr
                          : difference > 0
                          ? 'Over by {amount}'.trArgs({'amount': Money.format(difference)})
                          : 'Short by {amount}'.trArgs({'amount': Money.format(-difference)}),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _sharePdf,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text('Share Z-report PDF'.tr),
        ),
      ],
    );
  }
}
