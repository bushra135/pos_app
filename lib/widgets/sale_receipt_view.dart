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
import '../utils/receipt_text.dart';

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

class _SaleReceiptViewState extends State<SaleReceiptView> {
  bool exporting = false;

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
          SnackBar(
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
        SnackBar(content: Text('Could not open WhatsApp. Your sale is already saved.'.tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final date = sale.createdAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
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
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.successSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.success, size: 36),
                    ),
                  ),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale.storeName,
                            style: const TextStyle(
                              fontSize: AppTypography.headline,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            sale.receiptNumber,
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: AppColors.primaryDark,
                                ),
                                label: Text('Cashier: {name}'.trArgs({'name': sale.cashierName})),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.payments_outlined,
                                  size: 16,
                                  color: AppColors.primaryDark,
                                ),
                                label: Text(
                                  'Payment: {method}'.trArgs({'method': sale.paymentMethod.tr}),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Text(
                            'Items'.tr,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppTypography.subtitle,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final line in sale.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${line.quantity} × ${Money.format(line.price)}',
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
                                    fit: FlexFit.tight,
                                    child: Text(
                                      Money.format(line.subtotal),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(height: 28),
                          // Subtotal, discount and the VAT already inside the total.
                          for (final row in [
                            if (sale.discount > 0) ...[
                              ('Subtotal'.tr, Money.format(sale.subtotal)),
                              ('Discount'.tr, '− ${Money.format(sale.discount)}'),
                            ],
                            if (sale.vatRate > 0)
                              (
                                'VAT {rate}% (included)'.trArgs({
                                  'rate': sale.vatRate.toStringAsFixed(0),
                                }),
                                Money.format(sale.tax),
                              ),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(row.$1, style: const TextStyle(color: AppColors.muted)),
                                  Text(row.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                            ),
                            child: Text(
                              'Total: {amount}'.trArgs({'amount': Money.format(sale.total)}),
                              style: const TextStyle(
                                fontSize: AppTypography.title,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
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
