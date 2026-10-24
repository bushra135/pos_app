import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app_colors.dart';
import '../../services/barcode_catalog_service.dart';
import '../../widgets/product_image.dart';
import '../../widgets/app_empty_state.dart';
import '../../services/sale_sync_service.dart';
import '../../utils/barcode_scan_guard.dart';
import '../../utils/cart_manager.dart';

/// Continuous camera checkout with a live cart and an explicit repeat action.
class ScanScreen extends StatefulWidget {
  final BarcodeCatalogService? catalog;
  final VoidCallback? onGoToCart;
  final VoidCallback? onBackToHome;

  const ScanScreen({
    super.key,
    this.onGoToCart,
    this.onBackToHome,
    this.catalog,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 100,
    facing: CameraFacing.back,
  );
  final _audioPlayer = AudioPlayer();
  final _barcodeInputController = TextEditingController();
  final _barcodeGuard = BarcodeScanGuard();
  Timer? _releaseTimer;
  final List<String> _pendingBarcodes = [];
  static const int _maximumPendingScans = 12;
  bool _isAddingProduct = false;
  bool _isProductInfoOpen = false;
  bool _isTorchEnabled = false;
  bool _isManualEntryVisible = false;
  String? _statusMessage;
  bool _hasScanError = false;
  String? _lastAddedProductId;
  String? _lastAddedStoreCode;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _scannerController.dispose();
    _audioPlayer.dispose();
    _barcodeInputController.dispose();
    super.dispose();
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    final codes = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((code) => code.isNotEmpty)
        .toList();
    // Keep a held label latched. It must leave the camera before it is rearmed.
    if (codes.contains(_barcodeGuard.heldCode)) {
      _releaseTimer?.cancel();
      _releaseTimer = Timer(
        const Duration(milliseconds: 1600),
        _barcodeGuard.release,
      );
    }
    if (_isManualEntryVisible || _isProductInfoOpen || codes.isEmpty) return;
    if (_pendingBarcodes.length >= _maximumPendingScans) return;
    final code = codes.first;
    if (!_barcodeGuard.accept(code)) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(
      const Duration(milliseconds: 1600),
      _barcodeGuard.release,
    );
    if (_isAddingProduct) {
      _pendingBarcodes.add(code);
    } else {
      unawaited(_addProductByBarcode(code));
    }
  }

  Future<void> _playScanFeedback() async {
    // Feedback failure must never report an already-added item as a failed scan.
    try {
      await HapticFeedback.lightImpact();
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (error) {
      debugPrint('Scan feedback unavailable: $error');
    }
  }

  Future<void> _addProductByBarcode(String code) async {
    if (_isAddingProduct || code.trim().isEmpty) return;
    setState(() => _isAddingProduct = true);
    try {
      final sync = SaleSyncService.maybeInstance;
      if (sync == null) throw StateError('The sales service is not ready.');
      final data = await sync.findProduct(code.trim(), preferCache: true);
      if (!mounted) return;
      final name = (data['name'] ?? '').toString();
      final productId = data['id'] as String;
      final storeCode = data['storeCode'] as String;
      CartManager.addItem(
        name: name,
        price: (data['price'] as num).toDouble(),
        barcode: (data['barcode'] ?? code).toString(),
        image: (data['image'] ?? '').toString(),
        productId: productId,
        storeCode: storeCode,
      );
      setState(() {
        _statusMessage =
            '$name · BD ${(data['price'] as num).toStringAsFixed(3)} added';
        _hasScanError = false;
        _lastAddedProductId = productId;
        _lastAddedStoreCode = storeCode;
        _barcodeInputController.clear();
      });
      unawaited(_playScanFeedback());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not add product: $error';
        _hasScanError = true;
      });
      if (error is ProductNotFoundException) {
        await _showUnknownProduct(code.trim());
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingProduct = false);
        // Preserve scan order and stock checks without dropping the next barcode.
        if (_pendingBarcodes.isNotEmpty) {
          unawaited(_addProductByBarcode(_pendingBarcodes.removeAt(0)));
        }
      }
    }
  }

  Future<void> _showUnknownProduct(String code) async {
    _isProductInfoOpen = true;
    final lookup = (widget.catalog ?? BarcodeCatalogService.shared)
        .lookup(code)
        .then<({CatalogProduct? product, String? error})>(
          (product) => (product: product, error: null),
          onError: (Object error) => (product: null, error: error.toString()),
        );
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New barcode'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    code,
                    style: const TextStyle(color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<({CatalogProduct? product, String? error})>(
                    future: lookup,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Looking up this product…'),
                            ],
                          ),
                        );
                      }
                      final product = snapshot.data?.product;
                      if (snapshot.data?.error != null || product == null) {
                        return Text(
                          snapshot.data?.error != null
                              ? snapshot.data!.error!
                              : 'No match in the free product catalogues. This product can still be added manually.',
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.imageUrl.isNotEmpty)
                            SizedBox(
                              height: 140,
                              width: double.infinity,
                              child: ProductImage(
                                source: product.imageUrl,
                                placeholder: const Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          if (product.category.isNotEmpty)
                            Text(product.category),
                          const SizedBox(height: 10),
                          SelectableText(
                            '${product.provider} · data ODbL · images CC BY-SA\n${product.sourceUrl}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Not in your store yet. Ask the owner to add it in Products: scan this barcode, review the details, and set the selling price and stock before selling.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
              },
              child: const Text('Copy barcode'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      _isProductInfoOpen = false;
    }
  }

  void _undoLastAddition() {
    final index = CartManager.items.indexWhere(
      (item) =>
          item.productId == _lastAddedProductId &&
          item.storeCode == _lastAddedStoreCode,
    );
    if (index < 0) return;
    setState(() {
      CartManager.decreaseQuantity(index);
      _lastAddedProductId = null;
      _statusMessage = 'Last addition undone';
      _hasScanError = false;
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
      if (mounted) setState(() => _isTorchEnabled = !_isTorchEnabled);
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasScanError = true;
          _statusMessage = 'Flash is unavailable on this camera';
        });
      }
    }
  }

  Widget _buildScanHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _isAddingProduct ? null : widget.onBackToHome,
            tooltip: 'Home',
            icon: const Icon(Icons.arrow_back),
          ),
          const Expanded(
            child: Text(
              'Scan & sell',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: _toggleTorch,
            tooltip: 'Toggle flash',
            icon: Icon(_isTorchEnabled ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Expanded(
      flex: 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcodeDetection,
            errorBuilder: (context, error, child) => const ColoredBox(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Camera unavailable. Allow camera access or use manual barcode entry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: .8,
                heightFactor: .6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: ColoredBox(
              color: Colors.black54,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Move each barcode into view. Use + for identical items.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
          if (_isAddingProduct && !_isProductInfoOpen)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildManualBarcodeInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _barcodeInputController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Barcode',
                hintText: 'Type the product barcode',
                prefixIcon: Icon(Icons.barcode_reader),
              ),
              onSubmitted: _isAddingProduct ? null : _addProductByBarcode,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isAddingProduct
                ? null
                : () => _addProductByBarcode(_barcodeInputController.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryOptions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Current sale',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton.icon(
          onPressed: _isAddingProduct
              ? null
              : () => setState(
                  () => _isManualEntryVisible = !_isManualEntryVisible,
                ),
          icon: Icon(
            _isManualEntryVisible
                ? Icons.close_rounded
                : Icons.keyboard_outlined,
            size: 18,
          ),
          label: Text(_isManualEntryVisible ? 'Close entry' : 'Enter barcode'),
        ),
      ],
    ),
  );

  Widget _buildScanStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            _hasScanError ? Icons.error_outline : Icons.check_circle_outline,
            color: _hasScanError ? AppColors.danger : AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_hasScanError && _lastAddedProductId != null)
            TextButton(
              onPressed: _isAddingProduct ? null : _undoLastAddition,
              child: const Text('Undo'),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveCart() {
    return Expanded(
      flex: 4,
      child: CartManager.items.isEmpty
          ? const AppEmptyState(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Ready for your first item',
              message: 'Scan a barcode or use Enter barcode to add a product.',
            )
          : ListView.builder(
              itemCount: CartManager.items.length,
              itemBuilder: (context, index) {
                final item = CartManager.items[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'BD ${item.price.toStringAsFixed(3)} each | BD ${item.totalPrice.toStringAsFixed(3)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove one',
                        onPressed: _isAddingProduct
                            ? null
                            : () => setState(() {
                                CartManager.decreaseQuantity(index);
                                _lastAddedProductId = null;
                              }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${item.quantity}'),
                      IconButton(
                        tooltip: 'Add one',
                        onPressed: _isAddingProduct
                            ? null
                            : () => _addProductByBarcode(item.barcode),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildReviewSaleButton(int unitCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$unitCount items',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ),
              Flexible(
                child: Text(
                  'BD ${CartManager.total.toStringAsFixed(3)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isAddingProduct || unitCount == 0
                  ? null
                  : widget.onGoToCart,
              icon: const Icon(Icons.shopping_cart_checkout),
              label: const Text('Review sale'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unitCount = CartManager.items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildScanHeader(),
            _buildCameraPreview(),
            _buildEntryOptions(),
            if (_isManualEntryVisible) _buildManualBarcodeInput(),
            if (_statusMessage != null) _buildScanStatus(),
            _buildLiveCart(),
            _buildReviewSaleButton(unitCount),
          ],
        ),
      ),
    );
  }
}
