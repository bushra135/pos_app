import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_empty_state.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/cart_item.dart';
import '../../utils/cart_manager.dart';
import '../../widgets/product_image.dart';
import '../checkout/checkout_receipt_screen.dart';
import '../../app/app_language.dart';

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
        title: Text('Hold sale'.tr),
        content: TextField(
          onChanged: (value) => note = value,
          maxLength: 60,
          decoration: InputDecoration(labelText: 'Customer or note (optional)'.tr),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, note),
            child: Text('Hold sale'.tr),
          ),
        ],
      ),
    );
    if (label == null || !mounted) return;
    setState(() => _draftBusy = true);
    try {
      await CartManager.hold(label);
      _message('Sale held on this device. You can start the next customer.'.tr);
    } catch (_) {
      _message(
        'Could not hold the sale. Your current cart is kept. Check device storage and retry.'.tr,
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
                    Expanded(
                      child: Text(
                        'Held sales'.tr,
                        style: TextStyle(
                          fontSize: AppTypography.section,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close'.tr,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'Unpaid sales saved on this device. Your current cart is held automatically when you resume another sale. Stock is checked at checkout.'
                      .tr,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: CartManager.heldSales.isEmpty
                      ? Center(child: Text('No held sales'.tr))
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
      _message('Sale resumed. Review the items and prices before checkout.'.tr);
    } catch (_) {
      _message('Could not resume the sale. Your carts are kept. Please retry.'.tr);
    } finally {
      if (mounted) setState(() => _draftBusy = false);
    }
  }

  static final ButtonStyle _draftButtonStyle = OutlinedButton.styleFrom(
    backgroundColor: AppColors.surface,
    foregroundColor: AppColors.text,
    iconColor: AppColors.primaryDark,
    side: const BorderSide(color: AppColors.border),
    minimumSize: const Size(48, 46),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(
      fontFamily: AppTypography.family,
      fontSize: AppTypography.caption + 1,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _draftControls() => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two equal, clearly tappable buttons on white, instead of faint outlines.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _draftBusy || CartManager.items.isEmpty || !CartManager.canSave
                    ? null
                    : _holdSale,
                style: _draftButtonStyle,
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
                label: Text('Hold sale'.tr, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _draftBusy || !CartManager.canSave ? null : _openHeldSales,
                style: _draftButtonStyle,
                icon: const Icon(Icons.history_rounded, size: 20),
                label: Text(
                  'Held sales ({n})'.trArgs({'n': CartManager.heldSales.length}),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                        (CartManager.saving ? 'Saving cart...'.tr : 'Cart saved on this device'.tr),
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
                        _message('Cart is not saved yet. Check device storage and retry.'.tr);
                      }
                    },
                    child: Text('Retry'.tr),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  void _checkout() {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cart is empty'.tr)));
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
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 8),
                child: Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Back'.tr,
                      onPressed: () {
                        if (widget.onBackToHome != null) {
                          widget.onBackToHome!();
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                        fixedSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.text),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Cart'.tr,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (cartItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          (cartItems.length == 1 ? '1 item' : '{n} items').trArgs({
                            'n': cartItems.length,
                          }),
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            fontSize: AppTypography.caption,
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
                    ? AppEmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: 'No items in cart'.tr,
                        message:
                            'Open Scan to add products using the camera or enter a barcode manually.'
                                .tr,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 16),
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                for (var index = 0; index < cartItems.length; index++) ...[
                                  if (index > 0) const Divider(height: 1, color: AppColors.soft),
                                  _cartRow(cartItems[index], index),
                                ],
                              ],
                            ),
                          ),
                        ],
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
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Total'.tr,
                            style: TextStyle(
                              fontSize: AppTypography.button,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'BD ${CartManager.total.toStringAsFixed(3)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _checkout,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(
                            fontFamily: AppTypography.family,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        child: Text('Complete sale'.tr),
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

  /// One cart line: image, name and unit price, a quantity stepper and remove.
  Widget _cartRow(CartItem item, int index) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.soft,
            ),
            clipBehavior: Clip.antiAlias,
            child: ProductImage(
              source: item.image,
              placeholder: const Icon(Icons.inventory_2_outlined, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypography.body),
                ),
                Text(
                  'BD {price} each'.trArgs({'price': item.price.toStringAsFixed(3)}),
                  style: const TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE1E1DB)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Remove one {name}'.trArgs({'name': item.name}),
                  filled: false,
                  onPressed: () => setState(() => CartManager.decreaseQuantity(index)),
                ),
                SizedBox(
                  width: 26,
                  child: Text(
                    item.quantity.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: AppTypography.body,
                    ),
                  ),
                ),
                _stepButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Add one {name}'.trArgs({'name': item.name}),
                  filled: true,
                  onPressed: () => setState(() => CartManager.increaseQuantity(index)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove {name}'.trArgs({'name': item.name}),
            onPressed: () => setState(() => CartManager.removeItem(index)),
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required String tooltip,
    required bool filled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: filled ? AppColors.primary : AppColors.background,
          foregroundColor: filled ? AppColors.onBrand : AppColors.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}
