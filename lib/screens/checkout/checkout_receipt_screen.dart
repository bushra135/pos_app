import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import '../../utils/cart_manager.dart';

/// Reviews the receipt, confirms payment, saves the sale, and updates stock.
class CheckoutReceiptScreen extends StatefulWidget {
  const CheckoutReceiptScreen({super.key});

  @override
  State<CheckoutReceiptScreen> createState() => _CheckoutReceiptScreenState();
}

class _CheckoutReceiptScreenState extends State<CheckoutReceiptScreen> {
  String selectedPaymentMethod = 'Cash';

  String storeName = '';
  String cashierName = '';
  String benefitNumber = '';
  String benefitQrBase64 = '';
  String storeCode = '';

  bool isLoading = true;
  bool isSavingSale = false;

  final AudioPlayer _successPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _successPlayer.setReleaseMode(ReleaseMode.stop);
    _loadStorePaymentData();
  }

  @override
  void dispose() {
    _successPlayer.dispose();
    super.dispose();
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
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final userData = userDoc.data()!;
      final String fullName = (userData['fullName'] ?? '').toString();
      final String firstName = fullName.isNotEmpty
          ? fullName.split(' ')[0]
          : '';
      final String fetchedStoreCode = (userData['storeCode'] ?? '')
          .toString()
          .trim();

      String fetchedStoreName = (userData['storeName'] ?? '').toString();
      String fetchedBenefitNumber = '';
      String fetchedBenefitQrBase64 = '';

      if (fetchedStoreCode.isNotEmpty) {
        final storeDoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(fetchedStoreCode)
            .get();

        if (storeDoc.exists) {
          final storeData = storeDoc.data()!;
          fetchedStoreName = (storeData['storeName'] ?? fetchedStoreName)
              .toString();
          fetchedBenefitNumber = (storeData['benefitNumber'] ?? '').toString();
          fetchedBenefitQrBase64 = (storeData['benefitQrBase64'] ?? '')
              .toString();
        }
      }

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

  String get receiptNumber {
    final now = DateTime.now();
    return 'RCPT${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmPayment() async {
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
      final firestore = FirebaseFirestore.instance;
      final currentUser = FirebaseAuth.instance.currentUser;
      // Capture the receipt number before saving the sale.
      final String saleReceiptNumber = receiptNumber;

      final items = CartManager.items.map((item) => item.toSaleData()).toList();

      final double subtotal = CartManager.items.fold<double>(
        0,
        (subtotal, item) => subtotal + item.totalPrice,
      );

      const double discount = 0;
      const double refund = 0;
      const double tax = 0;

      final double total = subtotal - discount + tax;

      // Submit the sale and stock updates in a single write transaction.
      await firestore.runTransaction((transaction) async {
        final saleRef = firestore.collection('sales').doc();

        transaction.set(saleRef, {
          'storeCode': storeCode,
          'storeName': storeName,
          'cashierUid': currentUser?.uid ?? '',
          'cashierName': cashierName,
          'paymentMethod': selectedPaymentMethod,
          'receiptNumber': saleReceiptNumber,
          'items': items,
          'subtotal': subtotal,
          'discount': discount,
          'refund': refund,
          'tax': tax,
          'total': total,
          'status': 'completed',
          'type': 'sale',
          'createdAt': FieldValue.serverTimestamp(),
        });

        for (final item in CartManager.items) {
          final productQuery = await firestore
              .collection('products')
              .where('barcode', isEqualTo: item.barcode)
              .limit(1)
              .get();

          if (productQuery.docs.isNotEmpty) {
            final productDoc = productQuery.docs.first;
            final productRef = productDoc.reference;

            final currentStock = ((productDoc.data()['stock'] ?? 0) as num)
                .toInt();

            transaction.update(productRef, {
              'stock': currentStock - item.quantity,
            });
          }
        }
      });

      // Clear the cart only after saving succeeds, so failed sales can be retried.
      CartManager.clearCart();

      await _playPaymentSuccessSound();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sale saved successfully')));

      await Future.delayed(const Duration(milliseconds: 650));

      if (!mounted) return;

      Navigator.pop(context, true);
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
            color: isSelected ? null : AppColors.surface,
            gradient: isSelected ? AppColors.brandGradient : null,
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
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
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
                            color: Colors.white,
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
                            color: Colors.white,
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
