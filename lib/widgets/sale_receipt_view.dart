import 'package:pos_app/widgets/app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sale_record.dart';
import '../app/app_colors.dart';
import '../services/receipt_service.dart';
import '../app/app_language.dart';
import '../app/money.dart';
import '../app/app_typography.dart';
import '../app/app_spacing.dart';
import '../utils/receipt_layout.dart';
import '../utils/receipt_text.dart';
import 'motion.dart';
import 'receipt_card.dart';

/// Export failures stay on this screen and cannot submit the sale again.
class SaleReceiptView extends StatefulWidget {
  const SaleReceiptView({
    super.key,
    required this.sale,
    required this.status,
    required this.onNewSale,
    this.actionLabel = 'New sale',
    this.actionIcon = Icons.qr_code_scanner,
  });
  final SaleRecord sale;
  final String status;
  final VoidCallback onNewSale;
  final String actionLabel;
  final IconData actionIcon;

  @override
  State<SaleReceiptView> createState() => _SaleReceiptViewState();
}

/// Separate bilingual labels and isolate dates/identifiers from surrounding RTL.
class _ReceiptLabel extends StatelessWidget {
  const _ReceiptLabel(this.value, {required this.style, required this.align});
  final String value;
  final TextStyle style;
  final TextAlign align;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: align == TextAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.stretch,
    children: [
      for (final part in value.split(' · '))
        Text(
          part,
          style: style,
          textAlign: align,
          textDirection: RegExp(r'[؀-ۿ]').hasMatch(part) ? TextDirection.rtl : TextDirection.ltr,
        ),
    ],
  );
}

/// Receipt with print, share-PDF and send actions.
class _SaleReceiptViewState extends State<SaleReceiptView> {
  bool exporting = false;

  /// Builds the receipt PDF, then prints it or opens the share sheet.
  Future<void> _export({required bool print}) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final bytes = await ReceiptService.generatePdf(widget.sale, status: widget.status);
      if (!mounted) return;
      if (print) {
        await Printing.layoutPdf(name: widget.sale.receiptNumber, onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: '${widget.sale.receiptNumber}.pdf',
          bounds: Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Could not export receipt. Your sale is already saved. Try again.'.tr),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  /// Asks for the customer's number (optional), then opens WhatsApp with the receipt.
  Future<void> _sendWhatsApp() async {
    final controller = TextEditingController();
    String? error;
    final number = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          void send() {
            final text = controller.text.trim();
            if (text.isEmpty) return Navigator.pop(dialogContext, '');
            final digits = ReceiptText.whatsappNumber(text);
            if (digits == null) {
              setDialog(() => error = 'Enter a valid phone number'.tr);
              return;
            }
            Navigator.pop(dialogContext, digits);
          }

          return AlertDialog(
            title: Text('Send on WhatsApp'.tr),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Customer phone (optional)'.tr,
                hintText: '3300 0000',
                helperText: 'Leave empty to choose the chat in WhatsApp'.tr,
                errorText: error,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              onSubmitted: (_) => send(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel'.tr)),
              FilledButton(onPressed: send, child: Text('Send'.tr)),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (number == null || !mounted) return;
    final link = ReceiptText.whatsappLink(widget.sale, number: number.isEmpty ? null : number);
    final opened = await launchUrl(
      link,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not open WhatsApp. Your sale is already saved.'.tr),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !exporting) widget.onNewSale();
      },
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Center(child: _SuccessMark()),
                  const SizedBox(height: 12),
                  Text(
                    'Sale saved'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppTypography.title, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
                  ),
                  const SizedBox(height: 24),
                  // A receipt keeps receipt proportions on wide screens.
                  FadeSlideIn(
                    index: 2,
                    offset: 24,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: _ReceiptPaper(layout: ReceiptLayout.of(sale)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: exporting ? null : _sendWhatsApp,
                        icon: const Icon(Icons.chat_outlined),
                        label: Text('Send on WhatsApp'.tr),
                      ),
                      OutlinedButton.icon(
                        onPressed: exporting ? null : () => _export(print: false),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text('Share PDF'.tr),
                      ),
                      OutlinedButton.icon(
                        onPressed: exporting ? null : () => _export(print: true),
                        icon: const Icon(Icons.print_outlined),
                        label: Text('Print'.tr),
                      ),
                    ],
                  ),
                  if (exporting)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: exporting ? null : widget.onNewSale,
                  icon: Icon(widget.actionIcon),
                  label: Text(widget.actionLabel.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipt as printed: bilingual, in the app's receipt shape. Its content comes
/// from [ReceiptLayout], the same source as the PDF and the WhatsApp text.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({required this.layout});

  final ReceiptLayout layout;

  Widget _row(ReceiptRow row, {double size = AppTypography.caption}) => Builder(
    builder: (context) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ReceiptLabel(
                row.label,
                align: rtl ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  color: row.strong ? AppColors.text : AppColors.muted,
                  fontSize: size,
                  fontWeight: row.strong ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: _ReceiptLabel(
                row.value,
                align: rtl ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                  fontSize: row.strong ? size + 3 : size,
                  fontWeight: row.strong ? FontWeight.w700 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final sale = layout.sale;
    final buyer = layout.buyer;
    return ReceiptCard(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sale.storeName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: AppTypography.headline, fontWeight: FontWeight.w700),
          ),
          for (final line in layout.storeLines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _ReceiptLabel(
                line,
                align: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
            ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
              ),
              child: _ReceiptLabel(
                layout.title,
                align: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: AppTypography.caption,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ReceiptRule(color: AppColors.border),
          const SizedBox(height: 8),
          for (final row in layout.meta) _row(row),
          if (buyer.isNotEmpty) ...[
            const SizedBox(height: 8),
            const ReceiptRule(color: AppColors.border),
            const SizedBox(height: 8),
            for (final row in buyer) _row(row),
          ],
          const SizedBox(height: 8),
          const ReceiptRule(color: AppColors.border),
          const SizedBox(height: 8),
          for (final line in sale.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${line.quantity} × ${Money.format(line.price)}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: AppTypography.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      Money.format(line.subtotal),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const ReceiptRule(color: AppColors.border),
          const SizedBox(height: 8),
          for (final row in layout.totals) _row(row, size: AppTypography.body),
          const SizedBox(height: 10),
          const _ReceiptLabel(
            ReceiptLayout.thanks,
            align: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
          ),
        ],
      ),
    );
  }
}

/// The paid tick: pops in with a gentle overshoot (static with reduced motion).
class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
      child: const Icon(Icons.check_rounded, color: AppColors.success, size: 36),
    );
    if (Motion.reduced(context)) return mark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Opacity(opacity: ((scale - 0.5) * 2).clamp(0.0, 1.0), child: child),
      ),
      child: mark,
    );
  }
}
