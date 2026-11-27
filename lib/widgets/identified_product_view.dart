import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../app/app_language.dart';
import '../app/app_typography.dart';
import '../app/money.dart';
import '../services/barcode_catalog_service.dart';
import 'product_image.dart';

/// What ShopPad found for a scanned barcode: photo, name, brand, size, category,
/// description, where the details came from, and the price situation.
///
/// Prices are labelled by kind and never mixed: a shared reference price (set by a
/// ShopPad store, not an official retail price), and an explicit note that no Bahrain
/// retail price is available from any official source.
class IdentifiedProductView extends StatelessWidget {
  const IdentifiedProductView({super.key, required this.product});

  final CatalogProduct product;

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: AppColors.muted, fontSize: AppTypography.caption);
    final details = [
      if (product.brand.isNotEmpty) product.brand,
      if (product.size.isNotEmpty) product.size,
      if (product.category.isNotEmpty) product.category,
    ].join(' · ');
    final shared =
        product.productType == CatalogProduct.communityType && product.suggestedPrice > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          width: double.infinity,
          child: ProductImage(
            source: product.imageUrl,
            placeholder: const Center(
              child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted, size: 36),
            ),
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypography.section),
        ),
        if (details.isNotEmpty) ...[const SizedBox(height: 2), Text(details)],
        if (product.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(product.description, style: muted, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        if (shared)
          Text(
            'Shared reference price: {price} · set by a ShopPad store{date}. Not an official retail price.'
                .trArgs({
                  'price': Money.format(product.suggestedPrice),
                  'date': product.sharedPriceDate == null
                      ? ''
                      : ' ${'on {date}'.trArgs({'date': _date(product.sharedPriceDate!)})}',
                }),
            style: const TextStyle(fontSize: AppTypography.caption, color: AppColors.text),
          )
        else
          Text('No shared reference price for this barcode yet.'.tr, style: muted),
        if (product.referencePrice > 0 && product.referenceCurrency.isNotEmpty)
          Text(
            'External reference offer: {price} {currency}. Not your selling price.'.trArgs({
              'price': product.referencePrice.toStringAsFixed(2),
              'currency': product.referenceCurrency,
            }),
            style: muted,
          ),
        Text('Bahrain retail price: not available from an official source.'.tr, style: muted),
        const SizedBox(height: 6),
        SelectableText(product.creditLine, style: muted),
      ],
    );
  }
}
