import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_language.dart';
import '../app/app_spacing.dart';
import '../app/app_typography.dart';
import '../app/money.dart';
import '../services/barcode_catalog_service.dart';
import '../services/unknown_products.dart';
import '../services/sale_sync_service.dart';
import '../utils/cart_manager.dart';
import 'product_image.dart';

/// Owner: the name, selling price and counted stock for a product being added from a
/// scan or a cashier's request. The price is never filled in for the owner; a shared
/// reference price can be copied with one tap.
Future<({String name, double price, int stock})?> showOwnerAddDialog(
  BuildContext context, {
  required String name,
  double sharedPrice = 0,
}) {
  final form = GlobalKey<FormState>();
  final nameField = TextEditingController(text: name);
  final priceField = TextEditingController();
  final stockField = TextEditingController();
  return showDialog<({String name, double price, int stock})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Add to your products'.tr),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameField,
                decoration: InputDecoration(labelText: 'Product name'.tr),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the product name.'.tr : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('owner-price'),
                controller: priceField,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'Your selling price'.tr,
                  suffixText: Money.symbol,
                ),
                validator: (v) {
                  final price = double.tryParse((v ?? '').trim());
                  return price == null || !price.isFinite || price <= 0
                      ? 'Enter a price above zero.'.tr
                      : null;
                },
              ),
              if (sharedPrice > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => priceField.text = sharedPrice.toStringAsFixed(3),
                    child: Text(
                      'Use the shared reference price ({price})'.trArgs({
                        'price': Money.format(sharedPrice),
                      }),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('owner-stock'),
                controller: stockField,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Units in stock (count them)'.tr),
                validator: (v) {
                  final stock = int.tryParse((v ?? '').trim());
                  return stock == null || stock < 0 ? 'Enter 0 or more units.'.tr : null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel'.tr)),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(dialogContext, (
              name: nameField.text.trim(),
              price: Money.round(double.parse(priceField.text.trim())),
              stock: int.parse(stockField.text.trim()),
            ));
          },
          child: Text('Add product'.tr),
        ),
      ],
    ),
  );
}

/// Shares the owner's chosen price with other ShopPad stores (best effort), the same
/// way saving a product in Products does.
void shareOwnerPrice(String barcode, String name, String category, double price, String image) {
  final community = BarcodeCatalogService.shared.community;
  if (community == null) return;
  unawaited(
    community
        .contribute(barcode: barcode, name: name, category: category, price: price, image: image)
        .catchError((Object _) {}),
  );
}

/// Owner: the cashiers' requests to add unknown barcodes, live. Each one can be added
/// with the owner's price and stock, or declined.
class ProductRequestsSheet extends StatelessWidget {
  const ProductRequestsSheet({super.key, required this.storeCode, this.firestore});

  final String storeCode;
  final FirebaseFirestore? firestore;

  static Future<void> show(BuildContext context, String storeCode, {FirebaseFirestore? db}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ProductRequestsSheet(storeCode: storeCode, firestore: db),
      );

  Future<void> _add(BuildContext context, UnknownProducts service, ProductRequest r) async {
    final messenger = ScaffoldMessenger.of(context);
    final input = await showOwnerAddDialog(context, name: r.name, sharedPrice: r.sharedPrice);
    if (input == null) return;
    try {
      await service.addAsOwner(
        storeCode: storeCode,
        barcode: r.barcode,
        name: input.name,
        price: input.price,
        stock: input.stock,
        request: r,
      );
      // Sharing prices is opt-in in product management; approval never publishes store data.
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('{name} added to your products'.trArgs({'name': input.name})),
        ),
      );
    } catch (e) {
      debugPrint('Approve request failed: $e');
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text((e is StateError ? e.message : 'Could not add the product. Try again.').tr),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = UnknownProducts(firestore ?? FirebaseFirestore.instance);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: StreamBuilder<List<ProductRequest>>(
          stream: service.pending(storeCode),
          builder: (context, snapshot) {
            final requests = snapshot.data ?? const <ProductRequest>[];
            return Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Products waiting for you'.tr,
                    style: const TextStyle(
                      fontSize: AppTypography.section,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cashiers scanned these barcodes. Add each one with your price, or decline it.'
                        .tr,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: snapshot.hasError
                        ? Center(
                            child: Text(
                              'Could not load requests. Check your connection and permissions.'.tr,
                            ),
                          )
                        : !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : requests.isEmpty
                        ? Center(child: Text('No requests right now.'.tr))
                        : ListView.separated(
                            itemCount: requests.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => _RequestCard(
                              request: requests[i],
                              onAdd: () => _add(context, service, requests[i]),
                              onDecline: () async {
                                try {
                                  await service.decline(requests[i]);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.danger,
                                        content: Text(
                                          'Could not decline this request. Try again.'.tr,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One request: photo, name, brand and size, who asked, any shared reference price.
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onAdd, required this.onDecline});

  final ProductRequest request;
  final VoidCallback onAdd;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final details = [
      if (r.brand.isNotEmpty) r.brand,
      if (r.size.isNotEmpty) r.size,
      r.barcode,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: ProductImage(
                  source: r.image,
                  placeholder: const Icon(Icons.inventory_2_outlined, color: AppColors.muted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(details, style: const TextStyle(color: AppColors.muted)),
                    if (r.requestedByName.isNotEmpty)
                      Text(
                        'Asked by {name}'.trArgs({'name': r.requestedByName}),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: AppTypography.caption,
                        ),
                      ),
                    if (r.sharedPrice > 0)
                      Text(
                        'Shared reference price: {price} (not an official retail price)'.trArgs({
                          'price': Money.format(r.sharedPrice),
                        }),
                        style: const TextStyle(fontSize: AppTypography.caption),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onDecline, child: Text('Decline'.tr)),
              const SizedBox(width: 8),
              FilledButton(onPressed: onAdd, child: Text('Add product'.tr)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Actions use fresh server authorization; catalogue information alone grants no access.
class UnknownProductActions extends StatefulWidget {
  const UnknownProductActions({super.key, required this.barcode, this.product});
  final String barcode;
  final CatalogProduct? product;
  @override
  State<UnknownProductActions> createState() => _UnknownProductActionsState();
}

class _UnknownProductActionsState extends State<UnknownProductActions> {
  bool busy = false;
  String? message;
  Future<void> _perform({bool sell = false}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final sync = SaleSyncService.maybeInstance;
      final uid = sync?.currentUserId();
      if (sync == null || uid == null) throw StateError('Sign in before scanning products.');
      final contextData = await sync.loadContext(uid);
      final profile = Map<String, dynamic>.from(contextData['profile'] as Map);
      final code = profile['storeCode'].toString();
      if (sync.currentUserId() != uid) throw StateError('Your account has changed.');
      final service = UnknownProducts(sync.firestore);
      if (sell) {
        final product = widget.product;
        if (product == null || CartManager.items.isNotEmpty) {
          throw StateError('Sell an unknown product separately without a discount.');
        }
        final quote = await service.registerAtSharedPrice(
          storeCode: code,
          uid: uid,
          product: product,
          price: product.suggestedPrice,
        );
        if (sync.currentUserId() != uid || !mounted) return;
        CartManager.addItem(
          name: quote['name'] as String,
          price: quote['price'] as double,
          barcode: widget.barcode,
          image: product.imageUrl,
          productId: quote['id'] as String,
          storeCode: code,
        );
        if (mounted) Navigator.pop(context);
      } else {
        final sent = await service.requestApproval(
          storeCode: code,
          uid: uid,
          requestedByName: (profile['fullName'] ?? '').toString(),
          barcode: widget.barcode,
          product: widget.product,
        );
        if (mounted) {
          setState(
            () => message = sent
                ? 'Request sent to the owner.'
                : 'A request is already waiting for the owner.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => message = error is StateError
              ? error.message.toString()
              : 'Could not complete this action. Check your connection and permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: busy ? null : () => _perform(),
        child: Text('Request owner approval'.tr),
      ),
      if ((widget.product?.suggestedPrice ?? 0) > 0)
        OutlinedButton(
          onPressed: busy ? null : () => _perform(sell: true),
          child: Text('Use owner-authorized reference price'.tr),
        ),
      if (message != null) Text(message!.tr),
    ],
  );
}
