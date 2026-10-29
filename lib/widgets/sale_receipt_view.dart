import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/sale_record.dart';
import '../app/app_colors.dart';
import '../services/receipt_service.dart';

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
      final bytes = await ReceiptService.generatePdf(
        widget.sale,
        status: widget.status,
      );
      if (!mounted) return;
      if (print) {
        await Printing.layoutPdf(
          name: widget.sale.receiptNumber,
          onLayout: (_) async => bytes,
        );
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
          const SnackBar(
            content: Text(
              'Could not export receipt. Your sale is already saved. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
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
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.success,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sale saved',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
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
                              fontSize: 20,
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
                              fontSize: 12,
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
                                label: Text('Cashier: ${sale.cashierName}'),
                              ),
                              Chip(
                                avatar: const Icon(
                                  Icons.payments_outlined,
                                  size: 16,
                                  color: AppColors.primaryDark,
                                ),
                                label: Text('Payment: ${sale.paymentMethod}'),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          const Text(
                            'Items',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${line.quantity} × BD ${line.price.toStringAsFixed(3)}',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    fit: FlexFit.tight,
                                    child: Text(
                                      'BD ${line.subtotal.toStringAsFixed(3)}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(height: 28),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Total: BD ${sale.total.toStringAsFixed(3)}',
                              style: const TextStyle(
                                fontSize: 24,
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
                      OutlinedButton.icon(
                        onPressed: exporting
                            ? null
                            : () => _export(print: false),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: const Text('Share PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exporting
                            ? null
                            : () => _export(print: true),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print'),
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
                  label: Text(widget.actionLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
