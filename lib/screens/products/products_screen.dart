import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../services/barcode_catalog_service.dart';
import '../../services/browser_scanner.dart';
import '../../utils/product_category_suggestion.dart';
import '../../utils/product_image_data.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/barcode_lookup_panel.dart';
import '../../widgets/product_image.dart';
import '../../widgets/scanner_error_panel.dart';
import '../../app/app_language.dart';

/// Manages store products, images, and low stock alert thresholds.
/// Manages store-scoped products, barcode suggestions, images and low-stock alerts.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.firestore, this.currentUserId, this.catalog});
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;
  final BarcodeCatalogService? catalog;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const Duration _requestTimeout = Duration(seconds: 20);
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController searchController = TextEditingController();

  String searchText = '';

  /// Owners see and edit cost prices; cashiers never do.
  bool _isOwner = false;

  /// Product list order chosen from the sort button next to search.
  _ProductSort _sort = _ProductSort.name;
  String storeCode = '';
  bool isLoadingStore = true;

  @override
  void initState() {
    super.initState();
    _loadStoreCode();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // Store context and inventory queries.
  Future<void> _loadStoreCode() async {
    try {
      final uid = widget.currentUserId != null
          ? widget.currentUserId!()
          : FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        if (!mounted) return;
        setState(() => isLoadingStore = false);
        return;
      }

      final userDoc = await _firestore.collection('users').doc(uid).get();
      final code = (userDoc.data()?['storeCode'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        storeCode = code;
        _isOwner = userDoc.data()?['role'] == 'owner';
        isLoadingStore = false;
      });
    } catch (e) {
      debugPrint('Error loading store code: $e');

      if (!mounted) return;

      setState(() => isLoadingStore = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream() {
    return _firestore.collection('products').where('storeCode', isEqualTo: storeCode).snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _storeProductDocs(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final docs = snapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    // The product list and alerts share store filtering and name sorting.
    final filtered = docs.where((doc) {
      final data = doc.data();
      final productStoreCode = (data['storeCode'] ?? '').toString().trim();
      return productStoreCode == storeCode;
    }).toList();

    filtered.sort((a, b) {
      final aName = (a.data()['name'] ?? '').toString().toLowerCase();
      final bName = (b.data()['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return filtered;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lowStockDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final lowDocs = docs.where((doc) {
      final item = doc.data();
      return _stockFrom(item) <= _minStockFrom(item);
    }).toList();

    lowDocs.sort((a, b) {
      return _stockFrom(a.data()).compareTo(_stockFrom(b.data()));
    });

    return lowDocs;
  }

  int _stockFrom(Map<String, dynamic> item) {
    // Older records may use quantity instead of stock.
    final value = item['stock'] ?? item['quantity'] ?? 0;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? 0;
  }

  int _minStockFrom(Map<String, dynamic> item) {
    // Support legacy field names without modifying stored records.
    final value = item['minStock'] ?? item['minQuantity'] ?? item['minimumStock'] ?? 5;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? 5;
  }

  String _priceLabel(Map<String, dynamic> item) {
    final price = double.tryParse((item['price'] ?? 0).toString()) ?? 0;
    return 'BD ${price.toStringAsFixed(3)}';
  }

  String _stockText(Map<String, dynamic> item) {
    final stock = _stockFrom(item);
    final minStock = _minStockFrom(item);

    if (stock <= 0) return 'Out';
    if (stock <= minStock) return 'Low $stock';

    return '$stock left';
  }

  Color _stockColor(Map<String, dynamic> item) {
    final stock = _stockFrom(item);
    final minStock = _minStockFrom(item);

    if (stock <= 0) return AppColors.danger;
    if (stock <= minStock) return AppColors.warning;

    return AppColors.text;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Barcode input and validation.
  Future<String?> _scanBarcode(BuildContext scannerContext) async {
    if (kIsWeb) return scanBrowserBarcode();
    String? scannedCode;
    int cameraAttempt = 0;

    await showDialog(
      context: scannerContext,
      builder: (context) => StatefulBuilder(
        builder: (context, setScannerState) {
          return Dialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: SizedBox(
              height: 420,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    child: MobileScanner(
                      key: ValueKey(cameraAttempt),
                      errorBuilder: (context, error, child) => ScannerErrorPanel(
                        error: error,
                        onRetry: () => setScannerState(() => cameraAttempt++),
                      ),
                      onDetect: (capture) {
                        if (scannedCode != null || capture.barcodes.isEmpty) {
                          return;
                        }

                        final code = capture.barcodes.first.rawValue;

                        if (code != null && code.isNotEmpty) {
                          scannedCode = code;
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: CircleAvatar(
                      backgroundColor: AppColors.soft,
                      child: IconButton(
                        tooltip: 'Close'.tr,
                        icon: const Icon(Icons.close, color: AppColors.text),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Scan product barcode'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return scannedCode;
  }

  String _productSaveError(Object error, String stage) {
    if (error is TimeoutException) {
      if (stage == 'Saving product') {
        return 'Save confirmation timed out. Check your connection and retry; '
            'the same product will be used.';
      }
      return '$stage timed out. Check your connection and try again.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return stage == 'Checking barcode'
              ? 'Unable to check this barcode in your store. Check your account access and try again.'
              : 'You do not have permission to save this product or image.';
        case 'unauthenticated':
          return 'Your session has expired. Sign in again.';
        case 'resource-exhausted':
          return 'The store has reached its data limit. Please try again later.';
        case 'unavailable':
        case 'network-request-failed':
          return 'Could not connect while ${stage.toLowerCase()}. '
              'Check your connection and try again.';
        default:
          return '$stage failed (${error.code}). Please try again.';
      }
    }
    return '$stage failed. Please try again.';
  }

  // Product editor: lookup, image selection, validation, and save.
  void _showProductDialog({String? docId, Map<String, dynamic>? product}) {
    // The dialog route can outlive its Products screen during navigation refreshes.
    final productFirestore = _firestore;
    final catalogue = widget.catalog ?? BarcodeCatalogService.shared;
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController(text: product?['name']?.toString() ?? '');
    final categoryController = TextEditingController(text: product?['category']?.toString() ?? '');
    final priceController = TextEditingController(text: product?['price']?.toString() ?? '');
    final costController = TextEditingController(
      text: (product?['cost'] is num && (product!['cost'] as num) > 0)
          ? product['cost'].toString()
          : '',
    );
    final stockController = TextEditingController(text: product?['stock']?.toString() ?? '');
    final minStockController = TextEditingController(
      text: (product?['minStock'] ?? product?['minQuantity'] ?? product?['minimumStock'] ?? 5)
          .toString(),
    );
    final barcodeController = TextEditingController(text: product?['barcode']?.toString() ?? '');
    final existingImage = product?['image']?.toString().trim() ?? '';
    final imageController = TextEditingController(
      // Embedded image data belongs in the preview, not in the URL text field.
      text: existingImage.startsWith('data:image/') ? '' : existingImage,
    );

    final bool isEdit = docId != null;
    // Reuse one document if a delayed write is retried after a timeout.
    final productRef = productFirestore.collection('products').doc(docId);

    Uint8List? pickedImageBytes;
    String imagePreviewUrl = existingImage;
    String? preparedImage;
    String? saveError;
    String saveStage = 'Checking barcode';
    bool isLookingUp = false;
    bool categoryManuallyEdited = false;
    String? automaticCategory;
    final lookupKey = GlobalKey<BarcodeLookupPanelState>();
    Map<String, dynamic>? catalogueSource = product?['catalogueSource'] is Map
        ? Map<String, dynamic>.from(product!['catalogueSource'])
        : null;
    bool isChoosingImage = false;
    bool isSavingProduct = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> chooseImage() async {
              if (isChoosingImage || isSavingProduct) return;
              setDialogState(() {
                isChoosingImage = true;
                saveError = null;
              });
              try {
                final image = await _imagePicker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1200,
                  maxHeight: 1200,
                  imageQuality: 75,
                );
                if (image == null || !context.mounted) return;

                final bytes = await image.readAsBytes().timeout(_requestTimeout);
                if (!context.mounted) return;
                final imageData = await ProductImageData.prepare(bytes).timeout(_requestTimeout);
                if (!context.mounted) return;

                setDialogState(() {
                  preparedImage = imageData;
                  pickedImageBytes = Uri.parse(imageData).data!.contentAsBytes();
                  imagePreviewUrl = '';
                  imageController.clear();
                });
              } catch (error) {
                if (!context.mounted) return;
                setDialogState(() {
                  saveError = error is FormatException
                      ? error.message
                      : 'Could not read the image. Please choose another image.';
                });
              } finally {
                if (context.mounted) {
                  setDialogState(() => isChoosingImage = false);
                }
              }
            }

            Future<void> saveProduct() async {
              if (isSavingProduct || isChoosingImage || isLookingUp) return;
              final String name = nameController.text.trim();
              final String category = categoryController.text.trim();
              final double? price = double.tryParse(priceController.text.trim());
              final costText = costController.text.trim();
              final double? cost = costText.isEmpty ? 0 : double.tryParse(costText);
              final int? stock = int.tryParse(stockController.text.trim());
              final int minStock = int.tryParse(minStockController.text.trim()) ?? 5;
              final String barcode = barcodeController.text.trim();

              if (storeCode.isEmpty) {
                setDialogState(() => saveError = 'Store code not found');
                return;
              }

              if (name.isEmpty ||
                  category.isEmpty ||
                  price == null ||
                  !price.isFinite ||
                  price < 0 ||
                  stock == null ||
                  stock < 0 ||
                  minStock < 0 ||
                  barcode.isEmpty ||
                  (_isOwner && (cost == null || !cost.isFinite || cost < 0))) {
                setDialogState(() {
                  saveError = 'Please fill all required fields correctly';
                });
                return;
              }

              setDialogState(() {
                isSavingProduct = true;
                saveError = null;
                saveStage = 'Checking barcode';
              });

              try {
                // Rules authorize queries by store; filtering after reading is too late.
                final duplicateBarcodeQuery = await productFirestore
                    .collection('products')
                    .where('storeCode', isEqualTo: storeCode)
                    .where('barcode', isEqualTo: barcode)
                    .get(const GetOptions(source: Source.server))
                    .timeout(_requestTimeout);
                if (!context.mounted) return;

                // Barcodes must be unique within the store, excluding the product being edited.
                final bool barcodeExists = duplicateBarcodeQuery.docs.any((doc) {
                  final data = doc.data();
                  final productStoreCode = (data['storeCode'] ?? '').toString().trim();

                  return doc.id != productRef.id && productStoreCode == storeCode;
                });

                if (barcodeExists) {
                  setDialogState(() {
                    saveError = 'This barcode already exists';
                  });
                  return;
                }

                final image = preparedImage ?? imagePreviewUrl.trim();
                if (!context.mounted) return;

                setDialogState(() {
                  saveStage = 'Saving product';
                });

                final Map<String, dynamic> productData = {
                  'name': name,
                  'category': category,
                  'price': price,
                  // Cost is owner-only; cashier edits leave it untouched.
                  if (_isOwner) 'cost': cost ?? 0,
                  'stock': stock,
                  'minStock': minStock,
                  'barcode': barcode,
                  'image': image,
                  'catalogueSource': catalogueSource,
                  'storeCode': storeCode,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (isEdit) {
                  await productRef.update(productData).timeout(_requestTimeout);
                } else {
                  await productRef
                      .set({...productData, 'createdAt': FieldValue.serverTimestamp()})
                      .timeout(_requestTimeout);
                }
                // Share only barcode, name and category so other stores can find this product.
                // Best effort: it must never delay or fail the store's own save.
                final community = catalogue.community;
                if (community != null) {
                  unawaited(
                    community
                        .contribute(
                          barcode: barcode,
                          name: name,
                          category: category,
                          price: price,
                          image: image,
                        )
                        .catchError((Object e) => debugPrint('Catalogue share skipped: $e')),
                  );
                }
                if (!context.mounted) return;

                Navigator.pop(context);
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit ? 'Product updated successfully' : 'Product added successfully',
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Product save error: $e');
                if (!context.mounted) return;
                setDialogState(() => saveError = _productSaveError(e, saveStage));
              } finally {
                if (context.mounted) {
                  setDialogState(() => isSavingProduct = false);
                }
              }
            }

            final hasImage = pickedImageBytes != null || imagePreviewUrl.trim().isNotEmpty;
            final isBusy = isSavingProduct || isChoosingImage || isLookingUp;

            return PopScope(
              // The picker can stay open; allow dismissing the form until saving.
              canPop: !isSavingProduct,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.text.withValues(alpha: 0.08),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isEdit ? 'Edit product' : 'Add product',
                                style: const TextStyle(
                                  fontSize: AppTypography.title,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            // Delete lives here so the product list stays uncluttered.
                            if (isEdit)
                              IconButton(
                                tooltip: 'Delete product'.tr,
                                onPressed: isBusy
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        _showDeleteDialog(
                                          docId,
                                          (product?['name'] ?? '').toString(),
                                        );
                                      },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.danger,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                barcodeController,
                                'Barcode',
                                onChanged: (_) => setDialogState(() {
                                  catalogueSource = null;
                                }),
                                enabled: !isBusy,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.soft,
                                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    color: AppColors.primaryDark,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () async {
                                          final result = await _scanBarcode(context);

                                          if (result != null && context.mounted) {
                                            if (barcodeController.text.trim() != result) {
                                              setDialogState(() {
                                                catalogueSource = null;
                                              });
                                            }
                                            barcodeController.text = result;
                                            if (!isEdit) {
                                              await lookupKey.currentState?.lookup();
                                            }
                                          }
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                        BarcodeLookupPanel(
                          key: lookupKey,
                          barcode: barcodeController,
                          catalog: catalogue,
                          enabled: !isSavingProduct && !isChoosingImage,
                          onBusyChanged: (busy) {
                            if (context.mounted) {
                              setDialogState(() => isLookingUp = busy);
                            }
                          },
                          onProduct: (result) {
                            if (!context.mounted) return;
                            setDialogState(() {
                              var filled = false;
                              if (nameController.text.trim().isEmpty) {
                                nameController.text = result.name;
                                filled = true;
                              }
                              if (categoryController.text.trim().isEmpty &&
                                  result.category.isNotEmpty) {
                                categoryController.text = result.category;
                                filled = true;
                              }
                              if (pickedImageBytes == null &&
                                  imagePreviewUrl.isEmpty &&
                                  imageController.text.trim().isEmpty &&
                                  result.imageUrl.isNotEmpty) {
                                // Embedded images from other stores go to the preview, not the URL field.
                                if (!result.imageUrl.startsWith('data:image/')) {
                                  imageController.text = result.imageUrl;
                                }
                                imagePreviewUrl = result.imageUrl;
                                filled = true;
                              }
                              // A price set by another ShopPad store is only a starting point.
                              if (priceController.text.trim().isEmpty &&
                                  result.suggestedPrice > 0) {
                                priceController.text = result.suggestedPrice.toStringAsFixed(3);
                                filled = true;
                              }
                              if (filled) catalogueSource = result.attribution;
                            });
                          },
                        ),
                        if (catalogueSource != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 12),
                            child: SelectableText(
                              [
                                'Source: ${catalogueSource!['provider']} · ${catalogueSource!['note'] ?? (catalogueSource!.containsKey('dataLicense') ? 'data ODbL · images CC BY-SA' : 'name and category only')}',
                                if ('${catalogueSource!['url'] ?? ''}'.isNotEmpty)
                                  '${catalogueSource!['url']}',
                              ].join('\n'),
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ),
                        _buildField(
                          nameController,
                          'Product name',
                          enabled: !isBusy,
                          onChanged: (value) {
                            if (categoryManuallyEdited) return;
                            final current = categoryController.text.trim();
                            if (current.isNotEmpty && current != automaticCategory) {
                              return;
                            }
                            final suggestion = ProductCategorySuggestion.fromName(value);
                            setDialogState(() {
                              automaticCategory = suggestion;
                              categoryController.text = suggestion ?? '';
                            });
                          },
                        ),
                        _buildField(
                          categoryController,
                          'Category',
                          enabled: !isBusy,
                          onChanged: (_) => setDialogState(() {
                            categoryManuallyEdited = true;
                            automaticCategory = null;
                          }),
                        ),
                        if (automaticCategory != null)
                          Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Suggested from product name · you can change it'.tr,
                              style: TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ),
                        _buildField(
                          priceController,
                          'Price',
                          enabled: !isBusy,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        if (_isOwner)
                          _buildField(
                            costController,
                            'Cost price (owner only, optional)',
                            enabled: !isBusy,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        _buildField(
                          stockController,
                          'Stock',
                          enabled: !isBusy,
                          keyboardType: TextInputType.number,
                        ),
                        _buildField(
                          minStockController,
                          'Low stock alert limit',
                          enabled: !isBusy,
                          keyboardType: TextInputType.number,
                        ),
                        _buildField(
                          imageController,
                          'Image URL',
                          enabled: !isBusy,
                          onChanged: (value) {
                            setDialogState(() {
                              pickedImageBytes = null;
                              preparedImage = null;
                              imagePreviewUrl = value.trim();
                            });
                          },
                        ),
                        _buildProductImagePreview(
                          pickedImageBytes: pickedImageBytes,
                          imageUrl: imagePreviewUrl,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isBusy ? null : chooseImage,
                                icon: const Icon(Icons.upload_file_rounded),
                                label: Text(
                                  isChoosingImage ? 'Preparing image...' : 'Choose image',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: const BorderSide(color: AppColors.primaryDark),
                                  foregroundColor: AppColors.primaryDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                              ),
                            ),
                            if (hasImage) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isBusy
                                      ? null
                                      : () {
                                          setDialogState(() {
                                            pickedImageBytes = null;
                                            preparedImage = null;
                                            imagePreviewUrl = '';
                                            imageController.clear();
                                          });
                                        },
                                  icon: const Icon(Icons.close_rounded),
                                  label: Text('Remove'.tr),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: AppColors.border),
                                    foregroundColor: AppColors.text,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (isSavingProduct) ...[
                          Text(
                            '$saveStage...',
                            style: const TextStyle(color: AppColors.primaryDark),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            backgroundColor: AppColors.soft,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (saveError != null) ...[
                          Text(saveError!, style: const TextStyle(color: AppColors.danger)),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSavingProduct ? null : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                                child: Text(
                                  'Cancel'.tr,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isBusy ? null : saveProduct,
                                style: ElevatedButton.styleFrom(
                                  elevation: 2,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                                child: isSavingProduct
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: AppColors.onBrand,
                                        ),
                                      )
                                    : Text(
                                        isEdit ? 'Save' : 'Add product',
                                        style: const TextStyle(
                                          color: AppColors.onBrand,
                                          fontSize: AppTypography.button,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProductImagePreview({
    required Uint8List? pickedImageBytes,
    required String imageUrl,
  }) {
    final cleanUrl = imageUrl.trim();

    return Container(
      width: double.infinity,
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: pickedImageBytes != null
          ? Image.memory(pickedImageBytes, fit: BoxFit.cover)
          : cleanUrl.isNotEmpty
          ? ProductImage(
              source: cleanUrl,
              placeholder: const Center(
                child: Icon(Icons.broken_image_rounded, color: AppColors.muted, size: 42),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, color: AppColors.muted, size: 42),
                SizedBox(height: 8),
                Text(
                  'Add image by URL or upload from device'.tr,
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        enabled: enabled,
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint.tr,
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // Delete confirmation and low-stock notifications.
  void _showDeleteDialog(String docId, String productName) {
    final productRef = _firestore.collection('products').doc(docId);
    bool deleting = false;
    String? errorMessage;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => PopScope(
          canPop: !deleting,
          child: AlertDialog(
            title: Text('Delete product'.tr),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Are you sure you want to delete "$productName"?'),
                const SizedBox(height: 8),
                Text('Existing receipts will stay in sales history.'.tr),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMessage!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.pop(dialogContext),
                child: Text('Cancel'.tr),
              ),
              TextButton(
                onPressed: deleting
                    ? null
                    : () async {
                        updateDialog(() {
                          deleting = true;
                          errorMessage = null;
                        });
                        try {
                          await productRef.delete().timeout(_requestTimeout);
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (mounted) {
                            _showMessage('Product deleted successfully');
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          updateDialog(() {
                            deleting = false;
                            errorMessage = error is TimeoutException
                                ? 'Delete confirmation timed out. Refresh products before retrying.'
                                : error is FirebaseException && error.code == 'permission-denied'
                                ? 'You do not have permission to delete this product. Check your store account access.'
                                : 'Could not delete the product. Check your connection and try again.';
                          });
                        }
                      },
                child: Text(
                  deleting ? 'Deleting...' : 'Delete',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLowStockSheet(List<QueryDocumentSnapshot<Map<String, dynamic>>> lowStockDocs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.58,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Low stock alerts'.tr,
                          style: TextStyle(
                            fontSize: AppTypography.section,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: lowStockDocs.isEmpty
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${lowStockDocs.length}',
                          style: TextStyle(
                            color: lowStockDocs.isEmpty ? AppColors.success : AppColors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: lowStockDocs.isEmpty
                        ? Center(
                            child: Text(
                              'No low stock products right now'.tr,
                              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: lowStockDocs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = lowStockDocs[index];
                              final item = doc.data();

                              final name = (item['name'] ?? '').toString();
                              final image = (item['image'] ?? '').toString();
                              final stock = _stockFrom(item);
                              final minStock = _minStockFrom(item);
                              final status = stock <= 0 ? 'Out of stock' : 'Low stock';

                              return Material(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showProductDialog(docId: doc.id, product: item);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        _productThumb(image),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$status · $stock left · minimum $minStock',
                                                style: TextStyle(
                                                  color: stock <= 0
                                                      ? AppColors.danger
                                                      : AppColors.warning,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: AppTypography.caption,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: AppColors.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNotificationButton() {
    if (storeCode.isEmpty) {
      return const SizedBox(width: 8);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productsStream(),
      builder: (context, snapshot) {
        final docs = _storeProductDocs(snapshot.data);
        final lowDocs = _lowStockDocs(docs);
        final count = lowDocs.length;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Low stock alerts'.tr,
                onPressed: () => _showLowStockSheet(lowDocs),
                icon: Icon(
                  count > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  color: count > 0 ? AppColors.danger : AppColors.text,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // Product rows and filters.
  Widget _productThumb(String imageUrl) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(color: AppColors.soft, borderRadius: BorderRadius.circular(12)),
    clipBehavior: Clip.antiAlias,
    child: ProductImage(
      source: imageUrl,
      fit: BoxFit.cover,
      placeholder: const Icon(Icons.inventory_2_outlined, color: AppColors.muted, size: 22),
    ),
  );

  /// Adds received units to a product's stock, e.g. +12 for a new box of notebooks.
  Future<void> _showRestockDialog(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final item = doc.data();
    final name = (item['name'] ?? '').toString();
    final current = _stockFrom(item);
    final messenger = ScaffoldMessenger.of(context);

    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _RestockDialog(name: name, current: current),
    );
    if (amount == null || amount <= 0) return;

    try {
      // Increment on the server so a sale saved at the same moment is not overwritten.
      await doc.reference
          .update({
            'stock': FieldValue.increment(amount),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(_requestTimeout);
      messenger.showSnackBar(
        SnackBar(content: Text('$name restocked: +$amount (now ${current + amount})')),
      );
    } catch (e) {
      debugPrint('Restock failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update stock. Check your connection and try again.'.tr)),
      );
    }
  }

  Widget _productRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final item = doc.data();
    final name = (item['name'] ?? '').toString();
    final category = (item['category'] ?? '').toString().trim();
    final barcode = (item['barcode'] ?? '').toString().trim();
    final stockColor = _stockColor(item);
    final low = _stockFrom(item) <= _minStockFrom(item);
    final details = [
      if (category.isNotEmpty) category,
      if (barcode.isNotEmpty) barcode,
    ].join(' · ');

    return Tooltip(
      message: 'Edit product'.tr,
      child: InkWell(
        onTap: () => _showProductDialog(docId: doc.id, product: item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              _productThumb((item['image'] ?? '').toString()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.button,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _priceLabel(item),
                    style: const TextStyle(
                      fontSize: AppTypography.button,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: low ? 8 : 0),
                    decoration: BoxDecoration(
                      color: low ? stockColor.withValues(alpha: 0.12) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stockText(item),
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w700,
                        color: stockColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Quick restock: add received units without opening the full editor.
              IconButton.filledTonal(
                tooltip: 'Restock'.tr,
                onPressed: () => _showRestockDialog(doc),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentSoft,
                  foregroundColor: AppColors.primaryDark,
                  fixedSize: const Size(40, 40),
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortButton() {
    return PopupMenuButton<_ProductSort>(
      tooltip: 'Sort products'.tr,
      initialValue: _sort,
      onSelected: (value) => setState(() => _sort = value),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final option in _ProductSort.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == _sort ? Icons.check_rounded : option.icon,
                  size: 20,
                  color: option == _sort ? AppColors.primaryDark : AppColors.muted,
                ),
                const SizedBox(width: 12),
                Text(
                  option.label,
                  style: TextStyle(fontWeight: option == _sort ? FontWeight.w800 : FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _sort == _ProductSort.name ? AppColors.surface : AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          border: Border.all(
            color: _sort == _ProductSort.name ? AppColors.border : AppColors.primary,
          ),
        ),
        child: Icon(
          Icons.sort_rounded,
          color: _sort == _ProductSort.name ? AppColors.text : AppColors.onBrand,
        ),
      ),
    );
  }

  double _priceFrom(Map<String, dynamic> item) =>
      double.tryParse((item['price'] ?? 0).toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: canPop
            ? IconButton(
                tooltip: 'Back'.tr,
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        titleSpacing: canPop ? 0 : AppSpacing.page,
        title: Text(
          'Products'.tr,
          style: TextStyle(color: AppColors.text, fontSize: 26, fontWeight: FontWeight.w800),
        ),
        actions: [_buildNotificationButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: storeCode.isEmpty ? null : () => _showProductDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onBrand,
        elevation: 2,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add'.tr,
          style: TextStyle(fontFamily: AppTypography.family, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: isLoadingStore
            ? const Center(child: CircularProgressIndicator())
            : storeCode.isEmpty
            ? Center(child: Text('Store code not found'.tr))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _productsStream(),
                builder: (context, snapshot) {
                  final waiting = snapshot.connectionState == ConnectionState.waiting;
                  final docs = waiting || snapshot.hasError
                      ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                      : _storeProductDocs(snapshot.data);
                  final filteredDocs = docs.where((doc) {
                    final item = doc.data();
                    final name = (item['name'] ?? '').toString().toLowerCase();
                    final category = (item['category'] ?? '').toString().toLowerCase();
                    final barcode = (item['barcode'] ?? '').toString().toLowerCase();
                    return searchText.isEmpty ||
                        name.contains(searchText) ||
                        category.contains(searchText) ||
                        barcode.contains(searchText);
                  }).toList();

                  String nameOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                      (doc.data()['name'] ?? '').toString().toLowerCase();
                  filteredDocs.sort((a, b) {
                    final byChoice = switch (_sort) {
                      _ProductSort.name => 0,
                      _ProductSort.priceLow => _priceFrom(a.data()).compareTo(_priceFrom(b.data())),
                      _ProductSort.priceHigh => _priceFrom(
                        b.data(),
                      ).compareTo(_priceFrom(a.data())),
                      _ProductSort.stockLow => _stockFrom(a.data()).compareTo(_stockFrom(b.data())),
                    };
                    return byChoice != 0 ? byChoice : nameOf(a).compareTo(nameOf(b));
                  });

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                onChanged: (value) =>
                                    setState(() => searchText = value.trim().toLowerCase()),
                                decoration: InputDecoration(
                                  hintText: 'Search name, category or barcode'.tr,
                                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.muted),
                                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildSortButton(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: waiting
                            ? const Center(child: CircularProgressIndicator())
                            : snapshot.hasError
                            ? Center(child: Text('Something went wrong'.tr))
                            : filteredDocs.isEmpty
                            ? AppEmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: docs.isEmpty
                                    ? 'Your inventory starts here'.tr
                                    : 'No products found'.tr,
                                message: docs.isEmpty
                                    ? 'Tap Add to create your first product with its barcode, price, and stock.'
                                          .tr
                                    : 'Try another name, category or barcode.'.tr,
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.page,
                                  0,
                                  AppSpacing.page,
                                  96,
                                ),
                                children: [
                                  Material(
                                    color: AppColors.surface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: const BorderSide(color: AppColors.border),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      children: [
                                        for (var i = 0; i < filteredDocs.length; i++) ...[
                                          if (i > 0)
                                            const Divider(height: 1, color: AppColors.soft),
                                          _productRow(filteredDocs[i]),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// Orders offered by the sort button on the products list.
enum _ProductSort {
  name('Name A–Z', Icons.sort_by_alpha_rounded),
  priceLow('Price: low to high', Icons.arrow_upward_rounded),
  priceHigh('Price: high to low', Icons.arrow_downward_rounded),
  stockLow('Lowest stock first', Icons.inventory_2_outlined);

  const _ProductSort(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Asks how many units arrived; owns its text field so closing never races disposal.
class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.name, required this.current});

  final String name;
  final int current;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(_controller.text.trim()) ?? 0;
    final valid = value > 0 && value <= 100000;
    return AlertDialog(
      title: Text('Restock ${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In stock now: ${widget.current}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in const [1, 6, 12, 24])
                  ChoiceChip(
                    label: Text('+$n'),
                    selected: value == n,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _controller.text = '$n'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Units received'.tr, hintText: 'e.g. 12'.tr),
            ),
            if (valid) ...[
              const SizedBox(height: 10),
              Text(
                'New stock: ${widget.current + value}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, value) : null,
          child: Text('Add to stock'.tr),
        ),
      ],
    );
  }
}
