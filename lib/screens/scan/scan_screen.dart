import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app_colors.dart';
import '../../app/app_typography.dart';
import '../../services/barcode_catalog_service.dart';
import '../../services/browser_scanner.dart';
import '../../widgets/motion.dart';
import '../../widgets/product_image.dart';
import '../../widgets/scanner_error_panel.dart';
import '../../widgets/app_empty_state.dart';
import '../../services/sale_sync_service.dart';
import '../../utils/barcode_scan_guard.dart';
import '../../utils/cart_manager.dart';
import '../checkout/checkout_receipt_screen.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';
import '../../app/app_spacing.dart';

typedef BrowserCheckoutLauncher =
    Future<bool> Function({
      required Future<String> Function(String) onBarcode,
      required String summary,
    });

/// Continuous camera checkout with a live cart and an explicit repeat action.
class ScanScreen extends StatefulWidget {
  final BarcodeCatalogService? catalog;
  final VoidCallback? onGoToCart;
  final VoidCallback? onBackToHome;

  /// Called after a sale paid straight from the scanner is saved.
  final VoidCallback? onSaleCompleted;
  final BrowserCheckoutLauncher? browserCheckout;

  const ScanScreen({
    super.key,
    this.onGoToCart,
    this.onBackToHome,
    this.onSaleCompleted,
    this.catalog,
    this.browserCheckout,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final _cameraPreviewKey = GlobalKey();
  bool _browserPreviewFailed = false;
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
  bool _browserScannerOpen = false;
  bool _isProductInfoOpen = false;
  bool _isTorchEnabled = false;
  bool _isManualEntryVisible = false;
  String? _statusMessage;
  bool _hasScanError = false;
  String? _lastAddedProductId;
  String? _lastAddedStoreCode;

  /// Keeps the entry field ready for the next scan from a USB/Bluetooth reader.
  final _entryFocus = FocusNode();

  /// Keys from a barcode reader arrive within a few milliseconds of each other; a
  /// person types far slower. Only a fast burst ending in Enter counts as a scan.
  final _readerBuffer = StringBuffer();
  DateTime _lastReaderKey = DateTime(0);

  /// Products matching a typed name, for items whose barcode cannot be scanned.
  List<Map<String, dynamic>> _nameMatches = const [];

  /// Products the owner marked as quick buttons (one tap, same stock checks as a scan).
  List<Map<String, dynamic>> _quickProducts = const [];

  Future<void> _loadQuickProducts() async {
    try {
      final products = await SaleSyncService.maybeInstance?.quickProducts() ?? const [];
      if (mounted) setState(() => _quickProducts = products);
    } catch (error) {
      debugPrint('Quick buttons not loaded: $error');
    }
  }

  Timer? _searchDebounce;

  bool get _usesBrowserScanner => kIsWeb || widget.browserCheckout != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    unawaited(_loadQuickProducts());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _usesBrowserScanner) {
        unawaited(_openBrowserCheckout());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _searchDebounce?.cancel();
    _entryFocus.dispose();
    _releaseTimer?.cancel();
    if (_browserScannerOpen) closeBrowserScanner();
    _scannerController.dispose();
    _audioPlayer.dispose();
    _barcodeInputController.dispose();
    super.dispose();
  }

  // Decode, de-duplicate, and queue camera detections.
  void _handleBarcodeDetection(BarcodeCapture capture) {
    final codes = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((code) => code.isNotEmpty)
        .toList();
    // Keep a held label latched. It must leave the camera before it is rearmed.
    if (codes.contains(_barcodeGuard.heldCode)) {
      _releaseTimer?.cancel();
      _releaseTimer = Timer(const Duration(milliseconds: 1600), _barcodeGuard.release);
    }
    if (_isManualEntryVisible || _isProductInfoOpen || codes.isEmpty) return;
    if (_pendingBarcodes.length >= _maximumPendingScans) return;
    final code = codes.first;
    if (!_barcodeGuard.accept(code)) return;
    _releaseTimer?.cancel();
    _releaseTimer = Timer(const Duration(milliseconds: 1600), _barcodeGuard.release);
    if (_isAddingProduct) {
      _pendingBarcodes.add(code);
    } else {
      unawaited(_addProductByBarcode(code));
    }
  }

  /// Barcode readers that act as a keyboard work on any screen size, with no field open.
  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || _isProductInfoOpen) return false;
    // A focused text field (barcode entry, dialogs) handles its own keys.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final now = DateTime.now();
    if (now.difference(_lastReaderKey) > const Duration(milliseconds: 80)) _readerBuffer.clear();
    _lastReaderKey = now;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _readerBuffer.toString();
      _readerBuffer.clear();
      if (code.length < 4) return false;
      _queueBarcode(code);
      return true;
    }
    final character = event.character;
    if (character != null && RegExp(r'^[0-9A-Za-z-]$').hasMatch(character)) {
      _readerBuffer.write(character);
    }
    return false;
  }

  void _queueBarcode(String code) {
    if (_isAddingProduct) {
      if (_pendingBarcodes.length < _maximumPendingScans) _pendingBarcodes.add(code);
    } else {
      unawaited(_addProductByBarcode(code));
    }
  }

  /// The entry field takes a barcode or part of a product name.
  void _onEntryChanged(String value) {
    _searchDebounce?.cancel();
    final text = value.trim();
    if (text.length < 2 || RegExp(r'^\d+$').hasMatch(text)) {
      if (_nameMatches.isNotEmpty) setState(() => _nameMatches = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 200), () async {
      final sync = SaleSyncService.maybeInstance;
      if (sync == null) return;
      try {
        final matches = await sync.searchProducts(text);
        if (mounted && _barcodeInputController.text.trim() == text) {
          setState(() => _nameMatches = matches);
        }
      } catch (error) {
        debugPrint('Product name search failed: $error');
      }
    });
  }

  void _onEntrySubmitted(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    if (RegExp(r'^\d+$').hasMatch(text) || _nameMatches.isEmpty) {
      _queueBarcode(text);
    } else if (_nameMatches.length == 1) {
      _addMatch(_nameMatches.single);
    }
    _entryFocus.requestFocus();
  }

  void _addMatch(Map<String, dynamic> product) {
    final barcode = (product['barcode'] ?? '').toString().trim();
    setState(() {
      _nameMatches = const [];
      _barcodeInputController.clear();
    });
    if (barcode.isEmpty) {
      setState(() {
        _hasScanError = true;
        _statusMessage = '{name} has no barcode yet. Ask the owner to add one in Products.'.trArgs({
          'name': product['name'],
        });
      });
      unawaited(_playErrorFeedback());
      return;
    }
    _queueBarcode(barcode);
    _entryFocus.requestFocus();
  }

  /// A different signal for problems, so the cashier notices without looking.
  Future<void> _playErrorFeedback() async {
    try {
      await HapticFeedback.heavyImpact();
      for (var i = 0; i < 2; i++) {
        await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }
    } catch (error) {
      debugPrint('Scan feedback unavailable: $error');
    }
  }

  /// Short, translated reasons instead of raw exceptions.
  String _scanErrorMessage(Object error, String code) {
    if (error is ProductNotFoundException) {
      return 'Not in your store yet: {code}'.trArgs({'code': code});
    }
    if (error is StateError) {
      const known = {
        'The sales service is not ready.',
        'Sign in before scanning products.',
        'Multiple products in this store use this barcode.',
        'This product is not available in the offline catalogue.',
        'Wait for the cart to finish switching.',
      };
      if (known.contains(error.message)) return error.message.tr;
    }
    debugPrint('Scan failed for $code: $error');
    return 'Could not add this product. Check the connection and try again.'.tr;
  }

  Future<void> _openCheckout() async {
    if (_isAddingProduct || CartManager.items.isEmpty) return;
    if (_browserScannerOpen) closeBrowserScanner();
    final paid = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const CheckoutReceiptScreen()));
    if (!mounted) return;
    setState(() {
      if (paid == true) {
        _statusMessage = null;
        _lastAddedProductId = null;
      }
    });
    if (paid == true) {
      widget.onSaleCompleted?.call();
      unawaited(_loadQuickProducts());
    }
    if (mounted && _usesBrowserScanner && !_browserScannerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openBrowserCheckout());
      });
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

  // Resolve a store product before updating the cart.
  Future<void> _addProductByBarcode(String code) async {
    if (_isAddingProduct || code.trim().isEmpty) return;
    setState(() {
      _isAddingProduct = true;
      // Visible right away, so a slow connection never looks like a missed scan.
      _statusMessage = 'Looking up {code}…'.trArgs({'code': code.trim()});
      _hasScanError = false;
    });
    try {
      final sync = SaleSyncService.maybeInstance;
      if (sync == null) throw StateError('The sales service is not ready.');
      Map<String, dynamic> data;
      var miscounted = false;
      try {
        data = await sync.findProduct(code.trim(), preferCache: true);
      } on OutOfStockException catch (error) {
        // Records say zero, but the item is in the customer's hand: the cashier decides.
        if (!mounted) return;
        if (_browserScannerOpen) closeBrowserScanner();
        final sell = await _confirmMiscounted(error.productName);
        if (!mounted) return;
        if (!sell) {
          setState(() {
            _statusMessage = '{name} not added: recorded stock is 0.'.trArgs({
              'name': error.productName,
            });
            _hasScanError = true;
          });
          unawaited(_playErrorFeedback());
          return;
        }
        data = await sync.findProduct(code.trim(), preferCache: true, allowStockCorrection: true);
        miscounted = true;
      }
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
        cost: data['cost'] is num ? (data['cost'] as num).toDouble() : 0,
      );
      setState(() {
        _statusMessage = miscounted
            ? '{name} added as miscounted · stock will be corrected and the owner alerted'.trArgs({
                'name': name,
              })
            : '{name} · {price} added'.trArgs({
                'name': name,
                'price': Money.format(data['price'] as num),
              });
        _hasScanError = false;
        _lastAddedProductId = productId;
        _lastAddedStoreCode = storeCode;
        _barcodeInputController.clear();
      });
      unawaited(_playScanFeedback());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = _scanErrorMessage(error, code.trim());
        _hasScanError = true;
      });
      unawaited(_playErrorFeedback());
      if (error is ProductNotFoundException) {
        if (_browserScannerOpen) closeBrowserScanner();
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

  /// Lets the cashier sell an item the records show as sold out. Checkout raises the
  /// stock to match, logs a stock correction and flags it for the owner.
  Future<bool> _confirmMiscounted(String productName) async {
    _isProductInfoOpen = true;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.inventory_2_outlined, color: AppColors.warning, size: 32),
          title: Text('Out of stock in the system'.tr),
          content: Text(
            'The records show 0 {name} left. If the customer has the item in hand, the stock count was wrong.\n\nSell it as a miscounted product: the stock is corrected at checkout and the owner gets an alert to review.'
                .trArgs({'name': productName}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel'.tr),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text('Sell as miscounted'.tr),
            ),
          ],
        ),
      );
      return result == true;
    } finally {
      _isProductInfoOpen = false;
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
          title: Text('New barcode'.tr),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(code, style: const TextStyle(color: AppColors.primaryDark)),
                  const SizedBox(height: 12),
                  FutureBuilder<({CatalogProduct? product, String? error})>(
                    future: lookup,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Looking up this product…'.tr),
                            ],
                          ),
                        );
                      }
                      final product = snapshot.data?.product;
                      if (snapshot.data?.error != null || product == null) {
                        return Text(
                          snapshot.data?.error != null
                              ? snapshot.data!.error!
                              : 'No match in ShopPad or the free product catalogues. This product can still be added manually.'
                                    .tr,
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
                                  child: Icon(Icons.image_not_supported_outlined),
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppTypography.section,
                            ),
                          ),
                          if (product.category.isNotEmpty) Text(product.category),
                          const SizedBox(height: 10),
                          SelectableText(
                            product.creditLine,
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Not in your store yet. Ask the owner to add it in Products: scan this barcode, review the details, and set the selling price and stock before selling.'
                        .tr,
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
              child: Text('Copy barcode'.tr),
            ),
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Close'.tr)),
          ],
        ),
      );
    } finally {
      _isProductInfoOpen = false;
      if (mounted && _usesBrowserScanner && !_browserScannerOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openBrowserCheckout());
        });
      }
    }
  }

  void _undoLastAddition() {
    final index = CartManager.items.indexWhere(
      (item) => item.productId == _lastAddedProductId && item.storeCode == _lastAddedStoreCode,
    );
    if (index < 0) return;
    setState(() {
      CartManager.decreaseQuantity(index);
      _lastAddedProductId = null;
      _statusMessage = 'Last addition undone'.tr;
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
          _statusMessage = 'Flash is unavailable on this camera'.tr;
        });
      }
    }
  }

  Widget _buildScanHeader() {
    final style = IconButton.styleFrom(
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      fixedSize: const Size(44, 44),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: _isAddingProduct ? null : widget.onBackToHome,
            tooltip: 'Home'.tr,
            style: style,
            icon: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.text),
          ),
          Expanded(
            child: Text(
              'Scan & sell'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppTypography.section, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton.outlined(
            onPressed: _usesBrowserScanner ? null : _toggleTorch,
            tooltip: 'Toggle flash'.tr,
            style: style,
            icon: Icon(
              _isTorchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              size: 20,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  String get _browserCartSummary {
    final units = CartManager.items.fold<int>(0, (sum, item) => sum + item.quantity);
    return (units == 1 ? '1 item · {total}' : '{n} items · {total}').trArgs({
      'n': units,
      'total': Money.format(CartManager.total),
    });
  }

  // Keep browser video aligned with the Flutter camera region.
  void _positionBrowserCamera() {
    if (!mounted) return;
    final box = _cameraPreviewKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    positionBrowserCamera(
      jsonEncode({
        'left': offset.dx,
        'top': offset.dy,
        'width': box.size.width,
        'height': box.size.height,
      }),
    );
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _browserScannerOpen) _positionBrowserCamera();
    });
  }

  Future<void> _openBrowserCheckout() async {
    if (_browserScannerOpen || _isAddingProduct || _isProductInfoOpen) return;
    _browserScannerOpen = true;
    _positionBrowserCamera();
    try {
      final review = await (widget.browserCheckout ?? scanBrowserCheckout)(
        summary: _browserCartSummary,
        onBarcode: (code) async {
          if (!mounted) {
            return jsonEncode({'ok': false, 'message': 'Scanner closed'.tr, 'summary': ''});
          }
          if (!_isManualEntryVisible && !_isProductInfoOpen) {
            await _addProductByBarcode(code);
          }
          return jsonEncode({
            'ok': !_hasScanError,
            'message': _statusMessage ?? 'Ready to scan'.tr,
            'summary': _browserCartSummary,
          });
        },
      );
      if (mounted && review && CartManager.items.isNotEmpty) {
        widget.onGoToCart?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasScanError = true;
          _browserPreviewFailed = true;
          _statusMessage = 'Could not open browser camera. Retry or use Enter barcode.'.tr;
        });
      }
    } finally {
      _browserScannerOpen = false;
    }
  }

  // Camera, manual entry, live cart, and checkout controls.
  Widget _buildCameraPreview() {
    if (_usesBrowserScanner) {
      return Expanded(
        flex: 4,
        child: SizedBox.expand(
          key: _cameraPreviewKey,
          child: ColoredBox(
            color: AppColors.navy,
            child: Center(
              child: _browserPreviewFailed
                  ? FilledButton.icon(
                      onPressed: _openBrowserCheckout,
                      icon: const Icon(Icons.refresh),
                      label: Text('Retry camera'.tr),
                    )
                  : Text('Starting camera...'.tr, style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      );
    }
    return Expanded(
      flex: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: ColoredBox(
            color: AppColors.navy,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleBarcodeDetection,
                  errorBuilder: (context, error, child) => ScannerErrorPanel(
                    error: error,
                    onRetry: () async {
                      await _scannerController.stop();
                      if (!mounted) return;
                      try {
                        await _scannerController.start();
                      } on MobileScannerException {
                        // The scanner rebuilds its error panel with the current error.
                      }
                    },
                  ),
                ),
                const IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: .72,
                      heightFactor: .5,
                      // Corner brackets stay visible over any camera image.
                      child: CustomPaint(painter: _ScanFramePainter()),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Text(
                          'Move each barcode into view. Use + for identical items.'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: AppTypography.caption),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isAddingProduct && !_isProductInfoOpen)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualBarcodeInput({bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeInputController,
                  focusNode: _entryFocus,
                  autofocus: autofocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Barcode or product name'.tr,
                    hintText: 'Scan, type a barcode, or search by name'.tr,
                    prefixIcon: const Icon(Icons.barcode_reader),
                  ),
                  onChanged: _onEntryChanged,
                  onSubmitted: _isAddingProduct ? null : _onEntrySubmitted,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
                onPressed: _isAddingProduct
                    ? null
                    : () => _onEntrySubmitted(_barcodeInputController.text),
                child: Text('Add'.tr),
              ),
            ],
          ),
          if (_nameMatches.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _nameMatches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final product = _nameMatches[i];
                  final price = product['price'] is num ? product['price'] as num : 0;
                  return ListTile(
                    dense: true,
                    minTileHeight: 48,
                    title: Text(
                      (product['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      Money.format(price),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: _isAddingProduct ? null : () => _addMatch(product),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// On wide screens the entry field is always shown, so the toggle is left out.
  /// One-tap buttons for frequent items; each adds through the normal barcode path.
  Widget _buildQuickProducts() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: _quickProducts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final product = _quickProducts[i];
          final price = product['price'] is num ? product['price'] as num : 0;
          return ActionChip(
            avatar: const Icon(Icons.bolt_rounded, size: 18, color: AppColors.primaryDark),
            label: Text(
              '{name} · {price}'.trArgs({
                'name': product['name'] ?? '',
                'price': Money.format(price),
              }),
            ),
            onPressed: _isAddingProduct ? null : () => _addMatch(product),
          );
        },
      ),
    );
  }

  Widget _buildEntryOptions({bool showToggle = true}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Current sale'.tr,
            style: TextStyle(fontSize: AppTypography.subtitle, fontWeight: FontWeight.w800),
          ),
        ),
        if (showToggle)
          TextButton.icon(
            onPressed: _isAddingProduct
                ? null
                : () => setState(() => _isManualEntryVisible = !_isManualEntryVisible),
            icon: Icon(
              _isManualEntryVisible ? Icons.close_rounded : Icons.keyboard_outlined,
              size: 18,
            ),
            label: Text(_isManualEntryVisible ? 'Close entry'.tr : 'Enter barcode'.tr),
          ),
      ],
    ),
  );

  Widget _buildScanStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (_isAddingProduct && !_isProductInfoOpen)
            const SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            Icon(
              _hasScanError ? Icons.error_outline : Icons.check_circle_outline,
              color: _hasScanError ? AppColors.danger : AppColors.success,
              size: 20,
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage!, maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (!_hasScanError && _lastAddedProductId != null)
            TextButton(
              onPressed: _isAddingProduct ? null : _undoLastAddition,
              child: Text('Undo'.tr),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveCart() {
    return Expanded(
      flex: 4,
      child: CartManager.items.isEmpty
          ? AppEmptyState(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Ready for your first item'.tr,
              message: 'Scan a barcode, use a barcode reader, or search by name.'.tr,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              itemCount: CartManager.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = CartManager.items[index];
                final justAdded = item.productId == _lastAddedProductId && !_hasScanError;
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                    border: Border.all(
                      color: justAdded ? AppColors.primaryDark : AppColors.border,
                      width: justAdded ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '{price} each · {total}'.trArgs({
                                'price': Money.format(item.price),
                                'total': Money.format(item.totalPrice),
                              }),
                              style: TextStyle(
                                fontSize: AppTypography.caption,
                                color: justAdded ? AppColors.primaryDark : AppColors.muted,
                                fontWeight: justAdded ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove one'.tr,
                        onPressed: _isAddingProduct
                            ? null
                            : () => setState(() {
                                CartManager.decreaseQuantity(index);
                                _lastAddedProductId = null;
                              }),
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted),
                      ),
                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(
                        tooltip: 'Add one'.tr,
                        onPressed: _isAddingProduct
                            ? null
                            : () => _addProductByBarcode(item.barcode),
                        icon: const Icon(Icons.add_circle, color: AppColors.primary),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Cart to review or edit, and Pay to go straight to payment (one step fewer).
  Widget _buildReviewSaleButton(int unitCount) {
    final enabled = !_isAddingProduct && unitCount > 0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Review sale'.tr,
            child: OutlinedButton.icon(
              onPressed: enabled ? widget.onGoToCart : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 56),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: const BorderSide(color: AppColors.border),
                shape: shape,
              ),
              icon: const Icon(Icons.shopping_cart_outlined, size: 20),
              label: RollingText(
                '$unitCount',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: AppTypography.subtitle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: enabled ? _openCheckout : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                disabledBackgroundColor: AppColors.soft,
                disabledForegroundColor: AppColors.muted,
                shape: shape,
                textStyle: const TextStyle(
                  fontFamily: AppTypography.family,
                  fontSize: AppTypography.subtitle,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text('Pay'.tr),
                  const Spacer(),
                  RollingText(Money.format(CartManager.total)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_usesBrowserScanner && _browserScannerOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _browserScannerOpen) _positionBrowserCamera();
      });
    }
    final unitCount = CartManager.items.fold<int>(0, (total, item) => total + item.quantity);
    // On a counter PC or tablet the camera sits beside the sale, and the entry field is
    // always ready for a barcode reader.
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final entryVisible = _isManualEntryVisible || wide;
    final salePane = [
      if (!wide) _buildEntryOptions(),
      if (entryVisible) _buildManualBarcodeInput(autofocus: wide),
      if (_quickProducts.isNotEmpty) _buildQuickProducts(),
      if (_statusMessage != null) _buildScanStatus(),
      _buildLiveCart(),
      _buildReviewSaleButton(unitCount),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildScanHeader(),
                        _buildCameraPreview(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildEntryOptions(showToggle: false),
                        ...salePane,
                      ],
                    ),
                  ),
                ],
              )
            : Column(children: [_buildScanHeader(), _buildCameraPreview(), ...salePane]),
      ),
    );
  }
}

/// Four rounded corner brackets marking where the barcode should sit.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 30.0;
    const radius = 14.0;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final corners = [
      Path()
        ..moveTo(0, arm)
        ..lineTo(0, radius)
        ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
        ..lineTo(arm, 0),
      Path()
        ..moveTo(w - arm, 0)
        ..lineTo(w - radius, 0)
        ..arcToPoint(Offset(w, radius), radius: const Radius.circular(radius))
        ..lineTo(w, arm),
      Path()
        ..moveTo(w, h - arm)
        ..lineTo(w, h - radius)
        ..arcToPoint(Offset(w - radius, h), radius: const Radius.circular(radius))
        ..lineTo(w - arm, h),
      Path()
        ..moveTo(arm, h)
        ..lineTo(radius, h)
        ..arcToPoint(Offset(0, h - radius), radius: const Radius.circular(radius))
        ..lineTo(0, h - arm),
    ];
    for (final corner in corners) {
      canvas.drawPath(corner, paint);
    }
    canvas.drawLine(
      Offset(w * 0.08, h / 2),
      Offset(w * 0.92, h / 2),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) => false;
}
