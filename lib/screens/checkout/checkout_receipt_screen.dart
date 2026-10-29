import 'dart:convert';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/sale_record.dart';
import '../../services/sale_sync_service.dart';
import '../../utils/cart_manager.dart';
import '../../widgets/sale_receipt_view.dart';

/// Reviews the receipt, confirms payment, saves the sale, and updates stock.
class CheckoutReceiptScreen extends StatefulWidget {
  const CheckoutReceiptScreen({super.key, this.firestore, this.currentUserId});
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<CheckoutReceiptScreen> createState() => _CheckoutReceiptScreenState();
}

class _CheckoutReceiptScreenState extends State<CheckoutReceiptScreen> {
  String? get _uid => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;
  String selectedPaymentMethod = 'Cash';

  String storeName = '';
  String cashierName = '';
  String benefitNumber = '';
  String benefitQrBase64 = '';
  String storeCode = '';

  bool isLoading = true;
  bool isSavingSale = false;
  SaleRecord? completedSale;
  SaleSyncService? _receiptSync;
  String completedStatus = '';

  final AudioPlayer _successPlayer = AudioPlayer();
  late final String _saleId;
  late final DateTime _saleTime;

  @override
  void initState() {
    super.initState();
    _saleId = (widget.firestore ?? FirebaseFirestore.instance)
        .collection('sales')
        .doc()
        .id;
    _saleTime = DateTime.now();
    _receiptSync = SaleSyncService.maybeInstance;
    _receiptSync?.addListener(_refreshReceiptSync);
    _successPlayer.setReleaseMode(ReleaseMode.stop);
    _loadStorePaymentData();
  }

  @override
  void dispose() {
    _receiptSync?.removeListener(_refreshReceiptSync);
    _successPlayer.dispose();
    super.dispose();
  }

  void _refreshReceiptSync() {
    final sale = completedSale;
    final sync = _receiptSync;
    if (!mounted || sale == null || sync == null || _uid != sale.cashierUid)
      return;
    final rows = sync.pendingSales.where((row) => row.sale.id == sale.id);
    final next = rows.isEmpty && sync.online
        ? 'Synchronized'
        : rows.isNotEmpty && rows.first.isConflict
        ? 'Saved on device — stock needs review'
        : null;
    if (next != null && next != completedStatus) {
      setState(() => completedStatus = next);
    }
  }

  Future<void> _playPaymentSuccessSound() async {
    try {
      await HapticFeedback.lightImpact();
      await _successPlayer.stop();
      await _successPlayer.play(
        AssetSource('sounds/payment_success.mp3'),
        volume: 1,
      );
    } catch (e) {
      // Audio failure must not undo a successfully saved sale.
      debugPrint('Error playing payment success sound: $e');
    }
  }

  Future<void> _loadStorePaymentData() async {
    try {
      final uid = _uid;

      if (uid == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final sync = SaleSyncService.maybeInstance;
      if (sync == null) throw StateError('The sales service is not ready.');
      final contextData = await sync.loadContext(uid);
      final userData = Map<String, dynamic>.from(contextData['profile'] as Map);
      final String fullName = (userData['fullName'] ?? '').toString();
      final String firstName = fullName.split(' ').first;
      final String fetchedStoreCode = (userData['storeCode'] ?? '')
          .toString()
          .trim();

      final storeData = Map<String, dynamic>.from(contextData['store'] as Map);
      final fetchedStoreName =
          (storeData['storeName'] ?? userData['storeName'] ?? '').toString();
      final fetchedBenefitNumber = (storeData['benefitNumber'] ?? '')
          .toString();
      final fetchedBenefitQrBase64 = (storeData['benefitQrBase64'] ?? '')
          .toString();

      if (!mounted) return;

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        storeCode = fetchedStoreCode;
        benefitNumber = fetchedBenefitNumber;
        benefitQrBase64 = fetchedBenefitQrBase64;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading payment data: $e');

      if (!mounted) return;

      setState(() => isLoading = false);
    }
  }

  String get receiptNumber => 'RCPT-$_saleId';

  Future<void> _confirmPayment() async {
    if (isSavingSale || completedSale != null) return;
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    if (storeCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Store code not found')));
      return;
    }

    setState(() {
      isSavingSale = true;
    });

    try {
      final uid = _uid;
      final sync = SaleSyncService.maybeInstance;
      if (uid == null || sync == null) {
        throw StateError('Sign in before checkout.');
      }
      final items = <SaleLine>[];
      for (final item in CartManager.items) {
        if (item.productId.isEmpty || item.storeCode != storeCode) {
          throw StateError(
            'Remove this cart item and scan it again for your store.',
          );
        }
        items.add(
          SaleLine(
            productId: item.productId,
            barcode: item.barcode,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
          ),
        );
      }
      final sale = SaleRecord(
        id: _saleId,
        storeCode: storeCode,
        storeName: storeName,
        cashierUid: uid,
        cashierName: cashierName,
        paymentMethod: selectedPaymentMethod,
        createdAt: _saleTime,
        items: items,
      );
      final result = await sync.submit(sale);

      // Queued and conflicted receipts are already durably saved on this device.
      CartManager.clearCart();

      if (!mounted) return;
      // The durable receipt is ready; neither audio nor an informational dialog
      // should leave the payment button spinning or allow a second submission.
      setState(() {
        isSavingSale = false;
        completedSale = sale;
        completedStatus = result.status == SaleSubmissionStatus.synced
            ? 'Synchronized'
            : result.status == SaleSubmissionStatus.conflict
            ? 'Saved on device — stock needs review'
            : 'Saved on device — synchronization pending';
      });
      _refreshReceiptSync();
      unawaited(_playPaymentSuccessSound());

      if (result.status == SaleSubmissionStatus.synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale confirmed and stock updated')),
        );
      } else {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              result.status == SaleSubmissionStatus.conflict
                  ? 'Receipt needs review'
                  : 'Receipt saved — sync pending',
            ),
            content: Text(
              '$receiptNumber\n\n${result.message ?? 'Stock and reports will update when this receipt is confirmed online.'}\n\n'
              'No need to submit this sale again. It will retry automatically. Keep this browser data until synchronization completes; check Sales status for progress.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save sale: $e')));

      setState(() {
        isSavingSale = false;
      });
    }
  }

  Widget _buildPaymentOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: isSavingSale ? null : onTap,
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isSelected ? AppColors.primaryDark : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.onBrand : AppColors.muted,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTypography.label,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.onBrand : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptItem({
    required String name,
    required int quantity,
    required double subtotal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text('x$quantity', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          Text(
            'BD ${subtotal.toStringAsFixed(3)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildQrPlaceholder() {
    return Container(
      height: 180,
      width: 180,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.qr_code, size: 70, color: AppColors.muted),
    );
  }

  Widget _buildQrPreview() {
    if (benefitQrBase64.isEmpty) return _buildQrPlaceholder();

    try {
      final Uint8List bytes = base64Decode(benefitQrBase64);

      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          bytes,
          height: 180,
          width: 180,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildQrPlaceholder();
          },
        ),
      );
    } catch (_) {
      // Show a placeholder when the stored Base64 data is invalid.
      return _buildQrPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (completedSale != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SaleReceiptView(
          sale: completedSale!,
          status: completedStatus,
          onNewSale: () => Navigator.pop(context, true),
        ),
      );
    }
    final cartItems = CartManager.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.surface.withValues(
                            alpha: 0.25,
                          ),
                          child: IconButton(
                            onPressed: isSavingSale
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: AppColors.onBrand,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Payment & Receipt',
                                style: TextStyle(
                                  color: AppColors.onBrand,
                                  fontSize: AppTypography.title,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Review payment and invoice details',
                                style: TextStyle(
                                  color: AppColors.onBrand,
                                  fontSize: AppTypography.body,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Method',
                                style: TextStyle(
                                  fontSize: AppTypography.section,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _buildPaymentOption(
                                    title: 'Cash',
                                    icon: Icons.payments_outlined,
                                    isSelected: selectedPaymentMethod == 'Cash',
                                    onTap: () {
                                      setState(() {
                                        selectedPaymentMethod = 'Cash';
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  _buildPaymentOption(
                                    title: 'BenefitPay',
                                    icon: Icons.qr_code,
                                    isSelected:
                                        selectedPaymentMethod == 'BenefitPay',
                                    onTap: () {
                                      setState(() {
                                        selectedPaymentMethod = 'BenefitPay';
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total Amount',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: AppTypography.body,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'BD ${CartManager.total.toStringAsFixed(3)}',
                                      style: const TextStyle(
                                        fontSize: AppTypography.metric,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selectedPaymentMethod == 'BenefitPay') ...[
                                const SizedBox(height: 18),
                                if (benefitNumber.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'BenefitPay Number',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: AppTypography.body,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          benefitNumber,
                                          style: const TextStyle(
                                            fontSize: AppTypography.section,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (benefitQrBase64.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'Scan to pay',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildQrPreview(),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Receipt',
                                style: TextStyle(
                                  fontSize: AppTypography.section,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Store',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  Text(
                                    storeName.isEmpty ? 'My Store' : storeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Cashier',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  Text(
                                    cashierName.isEmpty
                                        ? 'Cashier'
                                        : cashierName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Receipt No.',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                  Text(
                                    receiptNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(color: AppColors.border),
                              const SizedBox(height: 10),
                              ...cartItems.map(
                                (item) => _buildReceiptItem(
                                  name: item.name,
                                  quantity: item.quantity,
                                  subtotal: item.totalPrice,
                                ),
                              ),
                              Divider(color: AppColors.border),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Subtotal',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'BD ${CartManager.total.toStringAsFixed(3)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Discount',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'BD 0.000',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Tax',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'BD 0.000',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: AppTypography.section,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'BD ${CartManager.total.toStringAsFixed(3)}',
                                    style: const TextStyle(
                                      fontSize: AppTypography.metric,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSavingSale ? null : _confirmPayment,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSavingSale
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onBrand,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    selectedPaymentMethod == 'Cash'
                                        ? 'Confirm Cash Payment'
                                        : 'Payment Received',
                                    style: const TextStyle(
                                      color: AppColors.onBrand,
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppTypography.button,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
