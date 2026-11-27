import 'package:pos_app/widgets/app_snack_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_language.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../utils/vat_invoice.dart';

/// Owner only: the VAT details printed on every invoice (NBR): whether the store is
/// VAT-registered, its 15-digit VAT account number and its address.
class VatSettingsCard extends StatefulWidget {
  const VatSettingsCard({
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
  State<VatSettingsCard> createState() => _VatSettingsCardState();
}

/// Form for the store's VAT status, 15-digit VAT number and address.
class _VatSettingsCardState extends State<VatSettingsCard> {
  final _form = GlobalKey<FormState>();
  late final StoreVat _initial = StoreVat.fromStore(widget.store);
  late bool _registered = _initial.registered;
  late final _number = TextEditingController(text: _initial.number);
  late final _address = TextEditingController(text: _initial.address);
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _address.dispose();
    super.dispose();
  }

  /// Validates and saves the VAT details on the store (owner only, enforced by the rules).
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await (widget.firestore ?? FirebaseFirestore.instance)
          .collection('stores')
          .doc(widget.storeCode)
          .update({
            'vatRegistered': _registered,
            'vatNumber': _registered ? VatChecks.digits(_number.text) : '',
            'storeAddress': _address.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(backgroundColor: AppColors.success, content: Text('VAT details saved'.tr)),
      );
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('VAT details save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          backgroundColor: AppColors.danger,
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
                const Icon(Icons.receipt_long_outlined, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'VAT invoice details'.tr,
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
              'Printed on every invoice, as the National Bureau for Revenue requires.'.tr,
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _registered,
              onChanged: _saving ? null : (v) => setState(() => _registered = v),
              title: Text('My store is VAT-registered'.tr),
              subtitle: Text(
                (_registered
                        ? 'Receipts are simplified tax invoices with 10% VAT included.'
                        : 'Receipts show no VAT, because none is collected.')
                    .tr,
              ),
            ),
            if (_registered) ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('vat-number'),
                controller: _number,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'VAT account number'.tr,
                  helperText: '15 digits, as on the registration certificate'.tr,
                  prefixIcon: const Icon(Icons.numbers_rounded),
                ),
                validator: (v) => VatChecks.vatNumber(v ?? '', required: true)?.tr,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('store-address'),
              controller: _address,
              enabled: !_saving,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Store address'.tr,
                helperText: 'Branch, city and country. A PO box alone is not enough.'.tr,
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.place_outlined),
              ),
              validator: (v) => VatChecks.address(v ?? '', required: _registered)?.tr,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...'.tr : 'Save VAT details'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
