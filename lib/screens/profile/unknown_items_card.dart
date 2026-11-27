import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_language.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../app/money.dart';
import '../../services/unknown_products.dart';

/// Owner only: what a cashier may do with a barcode that is not in the store yet.
/// Off (the default): the cashier sends the owner a request. On: the cashier may sell
/// at the shared reference price from other ShopPad stores, up to a maximum.
class UnknownItemsCard extends StatefulWidget {
  const UnknownItemsCard({
    super.key,
    required this.storeCode,
    required this.store,
    this.firestore,
    this.onSaved,
  });

  final String storeCode;
  final Map<String, dynamic> store;
  final FirebaseFirestore? firestore;
  final VoidCallback? onSaved;

  @override
  State<UnknownItemsCard> createState() => _UnknownItemsCardState();
}

/// Switch and maximum price, saved on the store (owner only, enforced by the rules).
class _UnknownItemsCardState extends State<UnknownItemsCard> {
  final _form = GlobalKey<FormState>();
  late final UnknownItemPolicy _initial = UnknownItemPolicy.fromStore(widget.store);
  late bool _allow = _initial.sharedPriceSales;
  late final _max = TextEditingController(
    text: _initial.maxPrice > 0 ? _initial.maxPrice.toStringAsFixed(3) : '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  String? _checkMax(String? value) {
    if (!_allow) return null;
    final max = double.tryParse((value ?? '').trim());
    if (max == null || !max.isFinite || max <= 0) {
      return 'Enter the highest price cashiers may use.';
    }
    if (max > UnknownItemPolicy.maxAllowed) return 'The maximum is BD 1000.';
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('stores')
          .doc(widget.storeCode)
          .update({
            'sharedPriceSales': _allow,
            'sharedPriceMax': Money.round(double.tryParse(_max.text.trim()) ?? 0),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings saved'.tr)));
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Unknown-product settings save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save your changes. Check your connection and try again.'.tr),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Products not in your store'.tr,
                    style: const TextStyle(
                      fontSize: AppTypography.subtitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'When a cashier scans a barcode you have not added, ShopPad identifies it and sends you a request to approve it with your price.'
                  .tr,
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allow,
              onChanged: _saving ? null : (v) => setState(() => _allow = v),
              title: Text('Let cashiers sell at the shared reference price'.tr),
              subtitle: Text(
                'The price other ShopPad stores set for the same barcode. It is not an official Bahrain retail price. The sale is flagged for you to review.'
                    .tr,
              ),
            ),
            if (_allow) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('shared-price-max'),
                controller: _max,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'Highest price cashiers may use'.tr,
                  helperText: 'Above this, the cashier sends you a request instead.'.tr,
                  helperMaxLines: 2,
                  suffixText: Money.symbol,
                  prefixIcon: const Icon(Icons.price_check_rounded),
                ),
                validator: (v) => _checkMax(v)?.tr,
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...'.tr : 'Save'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
