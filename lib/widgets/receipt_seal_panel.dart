import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/app_language.dart';
import '../app/app_colors.dart';
import '../models/sale_record.dart';
import '../services/receipt_seal_service.dart';

/// Never paints a decorative authenticity mark on an unsigned or pending receipt.
class ReceiptSealPanel extends StatefulWidget {
  const ReceiptSealPanel({super.key, required this.sale, required this.status});
  final SaleRecord sale;
  final String status;
  @override
  State<ReceiptSealPanel> createState() => _ReceiptSealPanelState();
}

class _ReceiptSealPanelState extends State<ReceiptSealPanel> {
  late Future<ReceiptSealData?> _seal;
  @override
  void initState() {
    super.initState();
    _seal = ReceiptSealService.load(widget.sale);
  }

  @override
  void didUpdateWidget(covariant ReceiptSealPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sale.id != widget.sale.id || oldWidget.status != widget.status) {
      _seal = ReceiptSealService.load(widget.sale);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ReceiptSealData?>(
    future: _seal,
    builder: (context, snapshot) {
      final seal = snapshot.data;
      if (seal == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
          onPressed: () async {
            await launchUrl(seal.url, mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.verified_outlined),
          label: Text('Verify receipt'.tr),
        ),
      );
    },
  );
}
