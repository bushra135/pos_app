import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_empty_state.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
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
  bool _draftBusy = false;

  @override
  void initState() {
    super.initState();
    CartManager.revision.addListener(_cartChanged);
  }

  void _cartChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CartManager.revision.removeListener(_cartChanged);
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _holdSale() async {
    if (_draftBusy || CartManager.items.isEmpty) return;
    var note = '';
    final label = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hold sale'),
        content: TextField(
          onChanged: (value) => note = value,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Customer or note (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, note),
            child: const Text('Hold sale'),
          ),
        ],
      ),
    );
    if (label == null || !mounted) return;
    setState(() => _draftBusy = true);
    try {
      await CartManager.hold(label);
      _message('Sale held on this device. You can start the next customer.');
    } catch (_) {
      _message(
        'Could not hold the sale. Your current cart is kept. Check device storage and retry.',
      );
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Future<void> _openHeldSales() async {
    if (_draftBusy) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.65,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Held sales',
                        style: TextStyle(
                          fontSize: AppTypography.section,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Unpaid sales saved on this device. Your current cart is held automatically when you resume another sale. Stock is checked at checkout.',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: CartManager.heldSales.isEmpty
                      ? const Center(child: Text('No held sales'))
                      : ListView.separated(
                          itemCount: CartManager.heldSales.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 12),
                          itemBuilder: (_, index) {
                            final row = CartManager.heldSales[index];
                            return Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.pause_circle_outline,
                                  color: AppColors.primaryDark,
                                ),
                                title: Text(row['label'].toString()),
                                subtitle: Text(
                                  '${(row['items'] as List).length} products · BD ${(row['total'] as num).toStringAsFixed(3)}',
                                ),
                                trailing: const Icon(Icons.play_arrow),
                                onTap: () => Navigator.pop(sheetContext, row['id'].toString()),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _draftBusy = true);
    try {
      await CartManager.resume(selected);
      _message('Sale resumed. Review the items and prices before checkout.');
    } catch (_) {
      _message('Could not resume the sale. Your carts are kept. Please retry.');
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  Widget _draftControls() => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _draftBusy || CartManager.items.isEmpty || !CartManager.canSave
                  ? null
                  : _holdSale,
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Hold sale'),
            ),
            OutlinedButton.icon(
              onPressed: _draftBusy || !CartManager.canSave ? null : _openHeldSales,
              icon: const Icon(Icons.restore),
              label: Text('Held sales (${CartManager.heldSales.length})'),
            ),
          ],
        ),
        if (_draftBusy)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (CartManager.canSave)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  CartManager.saveError != null
                      ? Icons.error_outline
                      : CartManager.saving
                      ? Icons.sync
                      : Icons.check_circle_outline,
                  size: 16,
                  color: CartManager.saveError != null ? AppColors.danger : AppColors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    CartManager.saveError ??
                        (CartManager.saving ? 'Saving cart...' : 'Cart saved on this device'),
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: CartManager.saveError != null ? AppColors.danger : AppColors.muted,
                    ),
                  ),
                ),
                if (CartManager.saveError != null)
                  TextButton(
                    onPressed: () async {
                      try {
                        await CartManager.flush();
                      } catch (_) {
                        _message('Cart is not saved yet. Check device storage and retry.');
                      }
                    },
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  void _checkout() {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty')));
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
        if (widget.onSaleCompleted != null) {
          widget.onSaleCompleted!();
        } else {
          widget.onBackToHome?.call();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = CartManager.items;

    return AbsorbPointer(
      absorbing: _draftBusy || CartManager.switching,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 10),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
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
              _draftControls(),
              Expanded(
                child: cartItems.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: 'No items in cart',
                        message:
                            'Open Scan to add products using the camera or enter a barcode manually.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                        itemCount: cartItems.length,
                        itemBuilder: (context, index) {
                          final item = cartItems[index];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
                                  icon: const Icon(Icons.delete, color: AppColors.danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (cartItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page, 14, AppSpacing.page, 16),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
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
                              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
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
      ),
    );
  }
}
