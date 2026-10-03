import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import '../../utils/cart_manager.dart';
import '../../widgets/product_image.dart';
import '../checkout/checkout_receipt_screen.dart';

/// Shows the shared cart and returns to the home screen after a confirmed sale.
class CartScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  final VoidCallback? onSaleCompleted;

  const CartScreen({super.key, this.onBackToHome, this.onSaleCompleted});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  void _checkout() {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    // Checkout returns true only after saving the sale; cancellation keeps the cart.
    Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CheckoutReceiptScreen()),
    ).then((result) async {
      if (!mounted) return;
      setState(() {});

      if (result == true) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        widget.onSaleCompleted?.call();
        widget.onBackToHome?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = CartManager.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                14,
                AppSpacing.page,
                10,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (widget.onBackToHome != null) {
                        widget.onBackToHome!();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back, size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cart',
                      style: TextStyle(
                        fontSize: AppTypography.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${cartItems.length}',
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: AppTypography.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cartItems.isEmpty
                  ? const Center(
                      child: Text(
                        'No items in cart',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          color: AppColors.muted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.page,
                      ),
                      itemCount: cartItems.length,
                      itemBuilder: (context, index) {
                        final item = cartItems[index];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.cardRadius,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.text.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: AppColors.accentSoft,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ProductImage(
                                  source: item.image,
                                  placeholder: const Icon(
                                    Icons.inventory,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: AppTypography.body,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'BD ${item.price.toStringAsFixed(3)}',
                                      style: const TextStyle(
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Subtotal: BD ${item.totalPrice.toStringAsFixed(3)}',
                                      style: const TextStyle(
                                        fontSize: AppTypography.caption,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        CartManager.increaseQuantity(index);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.add_circle,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  Text(
                                    item.quantity.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppTypography.label,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        CartManager.decreaseQuantity(index);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    CartManager.removeItem(index);
                                  });
                                },
                                icon: const Icon(
                                  Icons.delete,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (cartItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  14,
                  AppSpacing.page,
                  16,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: AppTypography.section,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'BD ${CartManager.total.toStringAsFixed(3)}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: AppTypography.metric,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checkout,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.controlRadius,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Complete Sale',
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontWeight: FontWeight.w700,
                            fontSize: AppTypography.button,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
