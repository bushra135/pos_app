import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/sale_record.dart';
import '../services/receipt_service.dart';

/// Export failures stay on this screen and cannot submit the sale again.
class SaleReceiptView extends StatefulWidget {
  const SaleReceiptView({
    super.key,
    required this.sale,
    required this.status,
    required this.onNewSale,
  });
  final SaleRecord sale;
  final String status;
  final VoidCallback onNewSale;

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
                  const Icon(Icons.check_circle, color: Colors.green, size: 56),
                  const Text(
                    'Sale saved',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(widget.status, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Text(sale.storeName, style: const TextStyle(fontSize: 22)),
                  SelectableText(sale.receiptNumber),
                  Text(sale.createdAt.toLocal().toString().split('.').first),
                  Text('Cashier: ${sale.cashierName}'),
                  Text('Payment: ${sale.paymentMethod}'),
                  const Divider(),
                  for (final line in sale.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.name),
                      subtitle: Text(
                        '${line.quantity} × BD ${line.price.toStringAsFixed(3)}',
                      ),
                      trailing: Text('BD ${line.subtotal.toStringAsFixed(3)}'),
                    ),
                  const Divider(),
                  Text(
                    'Total: BD ${sale.total.toStringAsFixed(3)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: exporting
                            ? null
                            : () => _export(print: false),
                        icon: const Icon(Icons.share),
                        label: const Text('Share PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: exporting
                            ? null
                            : () => _export(print: true),
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                      ),
                    ],
                  ),
                  if (exporting) const LinearProgressIndicator(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: exporting ? null : widget.onNewSale,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('New sale'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
