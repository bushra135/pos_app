import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import '../../utils/product_image_data.dart';
import '../../widgets/product_image.dart';

/// Manages store products, images, and low stock alert thresholds.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const double _minimumCardWidth = 160;
  static const double _cardPadding = 10;
  static const double _gridSpacing = 8;
  static const double _actionExtent = 48;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const TextStyle _productNameStyle = TextStyle(
    fontFamily: AppTypography.family,
    fontSize: AppTypography.body,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.text,
  );
  static const TextStyle _productPriceStyle = TextStyle(
    fontFamily: AppTypography.family,
    fontSize: AppTypography.body,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.primaryDark,
  );
  static const TextStyle _productStockStyle = TextStyle(
    fontFamily: AppTypography.family,
    fontSize: AppTypography.caption,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController searchController = TextEditingController();

  String searchText = '';
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

  Future<void> _loadStoreCode() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => isLoadingStore = false);
        return;
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final code = (userDoc.data()?['storeCode'] ?? '').toString().trim();

      if (!mounted) return;

      setState(() {
        storeCode = code;
        isLoadingStore = false;
      });
    } catch (e) {
      debugPrint('Error loading store code: $e');

      if (!mounted) return;

      setState(() => isLoadingStore = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream() {
    return _firestore.collection('products').snapshots();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _storeProductDocs(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final docs =
        snapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

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
    final value =
        item['minStock'] ?? item['minQuantity'] ?? item['minimumStock'] ?? 5;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? 5;
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

  Future<String?> _scanBarcode() async {
    String? scannedCode;

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
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
                    onDetect: (capture) {
                      if (capture.barcodes.isEmpty) return;

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
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Text(
                    'Scan product barcode',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return scannedCode;
  }

  Future<XFile?> _pickImageFromDevice() async {
    return _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );
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
          return 'You do not have permission to save this product or image.';
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

  void _showProductDialog({String? docId, Map<String, dynamic>? product}) {
    final nameController = TextEditingController(
      text: product?['name']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: product?['category']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: product?['price']?.toString() ?? '',
    );
    final stockController = TextEditingController(
      text: product?['stock']?.toString() ?? '',
    );
    final minStockController = TextEditingController(
      text:
          (product?['minStock'] ??
                  product?['minQuantity'] ??
                  product?['minimumStock'] ??
                  5)
              .toString(),
    );
    final barcodeController = TextEditingController(
      text: product?['barcode']?.toString() ?? '',
    );
    final existingImage = product?['image']?.toString().trim() ?? '';
    final imageController = TextEditingController(
      // Embedded image data belongs in the preview, not in the URL text field.
      text: existingImage.startsWith('data:image/') ? '' : existingImage,
    );

    final bool isEdit = docId != null;
    // Reuse one document if a delayed write is retried after a timeout.
    final productRef = _firestore.collection('products').doc(docId);

    Uint8List? pickedImageBytes;
    String imagePreviewUrl = existingImage;
    String? preparedImage;
    String? saveError;
    String saveStage = 'Checking barcode';
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
                final image = await _pickImageFromDevice();
                if (image == null || !mounted || !context.mounted) return;

                final bytes = await image.readAsBytes().timeout(
                  _requestTimeout,
                );
                if (!mounted || !context.mounted) return;
                final imageData = await ProductImageData.prepare(
                  bytes,
                ).timeout(_requestTimeout);
                if (!mounted || !context.mounted) return;

                setDialogState(() {
                  preparedImage = imageData;
                  pickedImageBytes = Uri.parse(
                    imageData,
                  ).data!.contentAsBytes();
                  imagePreviewUrl = '';
                  imageController.clear();
                });
              } catch (error) {
                if (!mounted || !context.mounted) return;
                setDialogState(() {
                  saveError = error is FormatException
                      ? error.message
                      : 'Could not read the image. Please choose another image.';
                });
              } finally {
                if (mounted && context.mounted) {
                  setDialogState(() => isChoosingImage = false);
                }
              }
            }

            Future<void> saveProduct() async {
              if (isSavingProduct || isChoosingImage) return;
              final String name = nameController.text.trim();
              final String category = categoryController.text.trim();
              final double? price = double.tryParse(
                priceController.text.trim(),
              );
              final int? stock = int.tryParse(stockController.text.trim());
              final int minStock =
                  int.tryParse(minStockController.text.trim()) ?? 5;
              final String barcode = barcodeController.text.trim();

              if (storeCode.isEmpty) {
                setDialogState(() => saveError = 'Store code not found');
                return;
              }

              if (name.isEmpty ||
                  category.isEmpty ||
                  price == null ||
                  stock == null ||
                  minStock < 0 ||
                  barcode.isEmpty) {
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
                final duplicateBarcodeQuery = await _firestore
                    .collection('products')
                    .where('barcode', isEqualTo: barcode)
                    .get(const GetOptions(source: Source.server))
                    .timeout(_requestTimeout);
                if (!mounted || !context.mounted) return;

                // Barcodes must be unique within the store, excluding the product being edited.
                final bool barcodeExists = duplicateBarcodeQuery.docs.any((
                  doc,
                ) {
                  final data = doc.data();
                  final productStoreCode = (data['storeCode'] ?? '')
                      .toString()
                      .trim();

                  return doc.id != productRef.id &&
                      productStoreCode == storeCode;
                });

                if (barcodeExists) {
                  setDialogState(() {
                    saveError = 'This barcode already exists';
                  });
                  return;
                }

                final image = preparedImage ?? imagePreviewUrl.trim();
                if (!mounted || !context.mounted) return;

                setDialogState(() {
                  saveStage = 'Saving product';
                });

                final Map<String, dynamic> productData = {
                  'name': name,
                  'category': category,
                  'price': price,
                  'stock': stock,
                  'minStock': minStock,
                  'barcode': barcode,
                  'image': image,
                  'storeCode': storeCode,
                  'updatedAt': FieldValue.serverTimestamp(),
                };

                if (isEdit) {
                  await productRef.update(productData).timeout(_requestTimeout);
                } else {
                  await productRef
                      .set({
                        ...productData,
                        'createdAt': FieldValue.serverTimestamp(),
                      })
                      .timeout(_requestTimeout);
                }
                if (!mounted || !context.mounted) return;

                Navigator.pop(context);
                _showMessage(
                  isEdit
                      ? 'Product updated successfully'
                      : 'Product added successfully',
                );
              } catch (e) {
                debugPrint('Product save error: $e');
                if (!mounted || !context.mounted) return;
                setDialogState(
                  () => saveError = _productSaveError(e, saveStage),
                );
              } finally {
                if (mounted && context.mounted) {
                  setDialogState(() => isSavingProduct = false);
                }
              }
            }

            final hasImage =
                pickedImageBytes != null || imagePreviewUrl.trim().isNotEmpty;
            final isBusy = isSavingProduct || isChoosingImage;

            return PopScope(
              // The picker can stay open; allow dismissing the form until saving.
              canPop: !isSavingProduct,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.cardRadius,
                      ),
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
                        Text(
                          isEdit ? 'Edit Product' : 'Add Product',
                          style: const TextStyle(
                            fontSize: AppTypography.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                          nameController,
                          'Product Name',
                          enabled: !isBusy,
                        ),
                        _buildField(
                          categoryController,
                          'Category',
                          enabled: !isBusy,
                        ),
                        _buildField(
                          priceController,
                          'Price',
                          enabled: !isBusy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        _buildField(
                          stockController,
                          'Stock',
                          enabled: !isBusy,
                          keyboardType: TextInputType.number,
                        ),
                        _buildField(
                          minStockController,
                          'Low Stock Alert Limit',
                          enabled: !isBusy,
                          keyboardType: TextInputType.number,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                barcodeController,
                                'Barcode',
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
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.controlRadius,
                                  ),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    color: AppColors.primaryDark,
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () async {
                                          final result = await _scanBarcode();

                                          if (result != null &&
                                              mounted &&
                                              context.mounted) {
                                            barcodeController.text = result;
                                          }
                                        },
                                ),
                              ),
                            ),
                          ],
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
                                  isChoosingImage
                                      ? 'Preparing image...'
                                      : 'Choose Image',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: const BorderSide(
                                    color: AppColors.primaryDark,
                                  ),
                                  foregroundColor: AppColors.primaryDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.controlRadius,
                                    ),
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
                                  label: const Text('Remove'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: BorderSide(color: AppColors.border),
                                    foregroundColor: AppColors.text,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.controlRadius,
                                      ),
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
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                            ),
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
                          Text(
                            saveError!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSavingProduct
                                    ? null
                                    : () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.controlRadius,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.controlRadius,
                                    ),
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
                                        isEdit ? 'Save' : 'Add Product',
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
                child: Icon(
                  Icons.broken_image_rounded,
                  color: AppColors.muted,
                  size: 42,
                ),
              ),
            )
          : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, color: AppColors.muted, size: 42),
                SizedBox(height: 8),
                Text(
                  'Add image by URL or upload from device',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
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
          hintText: hint,
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

  void _showDeleteDialog(String docId, String productName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Product'),
          content: Text('Are you sure you want to delete "$productName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _firestore.collection('products').doc(docId).delete();

                if (!mounted || !context.mounted) return;

                Navigator.pop(context);
                _showMessage('Product deleted successfully');
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showLowStockSheet(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lowStockDocs,
  ) {
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
                      const Expanded(
                        child: Text(
                          'Low Stock Alerts',
                          style: TextStyle(
                            fontSize: AppTypography.section,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: lowStockDocs.isEmpty
                              ? AppColors.success.withValues(alpha: 0.12)
                              : AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${lowStockDocs.length}',
                          style: TextStyle(
                            color: lowStockDocs.isEmpty
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: lowStockDocs.isEmpty
                        ? const Center(
                            child: Text(
                              'No low stock products right now',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: lowStockDocs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = lowStockDocs[index];
                              final item = doc.data();

                              final name = (item['name'] ?? '').toString();
                              final image = (item['image'] ?? '').toString();
                              final stock = _stockFrom(item);
                              final minStock = _minStockFrom(item);
                              final status = stock <= 0
                                  ? 'Out of stock'
                                  : 'Low stock';

                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.cardRadius,
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.cardRadius,
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showProductDialog(
                                      docId: doc.id,
                                      product: item,
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.cardRadius,
                                      ),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _productImage(image),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                                  fontSize:
                                                      AppTypography.caption,
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
                tooltip: 'Low stock alerts',
                onPressed: () => _showLowStockSheet(lowDocs),
                icon: Icon(
                  count > 0
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: count > 0 ? AppColors.danger : AppColors.text,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
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

  Widget _productImage(String imageUrl) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProductImage(
        source: imageUrl,
        fit: BoxFit.contain,
        placeholder: const Icon(
          Icons.inventory_2,
          color: AppColors.primaryDark,
          size: 32,
        ),
      ),
    );
  }

  double _productCardExtent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    double cardWidth,
  ) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final contentWidth = cardWidth - _cardPadding * 2;

    double measure(String text, TextStyle style) {
      painter.text = TextSpan(text: text, style: style);
      painter.layout(maxWidth: contentWidth);
      return painter.height;
    }

    // Measure the real Cairo text at the current scale so every card fits its content.
    double extent = 168;
    for (final doc in docs) {
      final item = doc.data();
      final stockStyle = _productStockStyle.copyWith(
        color: _stockColor(item),
        fontWeight: _stockFrom(item) <= _minStockFrom(item)
            ? FontWeight.w600
            : FontWeight.w400,
      );
      final height =
          _cardPadding * 2 +
          _actionExtent * 2 +
          20 +
          measure((item['name'] ?? '').toString(), _productNameStyle) +
          measure('\$${item['price']}', _productPriceStyle) +
          measure(_stockText(item), stockStyle);
      if (height > extent) extent = height;
    }
    painter.dispose();
    return extent.ceilToDouble() + 2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Products',
          style: TextStyle(
            color: AppColors.text,
            fontSize: AppTypography.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [_buildNotificationButton()],
      ),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        ),
        child: FloatingActionButton(
          onPressed: storeCode.isEmpty ? null : () => _showProductDialog(),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onBrand,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          ),
          child: const Icon(Icons.add, color: AppColors.onBrand),
        ),
      ),
      body: SafeArea(
        child: isLoadingStore
            ? const Center(child: CircularProgressIndicator())
            : storeCode.isEmpty
            ? const Center(child: Text('Store code not found'))
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: (value) {
                        setState(() {
                          searchText = value.trim().toLowerCase();
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.cardRadius,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _productsStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Something went wrong'),
                            );
                          }

                          final docs = _storeProductDocs(snapshot.data);

                          final filteredDocs = docs.where((doc) {
                            final item = doc.data();

                            final String name = (item['name'] ?? '')
                                .toString()
                                .toLowerCase();
                            final String category = (item['category'] ?? '')
                                .toString()
                                .toLowerCase();
                            final String barcode = (item['barcode'] ?? '')
                                .toString()
                                .toLowerCase();

                            return searchText.isEmpty ||
                                name.contains(searchText) ||
                                category.contains(searchText) ||
                                barcode.contains(searchText);
                          }).toList();

                          if (filteredDocs.isEmpty) {
                            return const Center(
                              child: Text('No products found'),
                            );
                          }

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              // A second column starts only when two 160 px cards and the gap fit.
                              final columns =
                                  ((constraints.maxWidth + _gridSpacing) /
                                          (_minimumCardWidth + _gridSpacing))
                                      .floor()
                                      .clamp(1, 6)
                                      .toInt();
                              final cardWidth =
                                  (constraints.maxWidth -
                                      _gridSpacing * (columns - 1)) /
                                  columns;
                              final cardExtent = _productCardExtent(
                                filteredDocs,
                                cardWidth,
                              );

                              return GridView.builder(
                                padding: const EdgeInsets.only(bottom: 90),
                                itemCount: filteredDocs.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: _gridSpacing,
                                      mainAxisSpacing: _gridSpacing,
                                      mainAxisExtent: cardExtent,
                                    ),
                                itemBuilder: (context, index) {
                                  final doc = filteredDocs[index];
                                  final item = doc.data();
                                  final String docId = doc.id;

                                  final String name = (item['name'] ?? '')
                                      .toString();
                                  final String image = (item['image'] ?? '')
                                      .toString();

                                  final stockText = _stockText(item);
                                  final stockColor = _stockColor(item);

                                  return Container(
                                    padding: const EdgeInsets.all(_cardPadding),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.controlRadius,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _productImage(image),
                                            const Spacer(),
                                            Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                IconButton(
                                                  tooltip: 'Edit product',
                                                  iconSize: 20,
                                                  visualDensity:
                                                      VisualDensity.standard,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: _actionExtent,
                                                        height: _actionExtent,
                                                      ),
                                                  onPressed: () {
                                                    _showProductDialog(
                                                      docId: docId,
                                                      product: item,
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    color: AppColors.primaryDark,
                                                  ),
                                            ),
                                                IconButton(
                                                  tooltip: 'Delete product',
                                                  iconSize: 20,
                                                  visualDensity:
                                                      VisualDensity.standard,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: _actionExtent,
                                                        height: _actionExtent,
                                                      ),
                                                  onPressed: () {
                                                    _showDeleteDialog(docId, name);
                                                  },
                                                  icon: const Icon(
                                                    Icons.delete,
                                                    color: AppColors.danger,
                                                  ),
                                            ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(name, style: _productNameStyle),
                                        const SizedBox(height: 6),
                                        Text(
                                          '\$${item['price']}',
                                          style: _productPriceStyle,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          stockText,
                                          style: _productStockStyle.copyWith(
                                            color: stockColor,
                                            fontWeight:
                                                _stockFrom(item) <=
                                                    _minStockFrom(item)
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
