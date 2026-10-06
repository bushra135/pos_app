import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import '../../utils/cart_manager.dart';

/// Adds products to the cart using camera scans or manual barcode entry.
class ScanScreen extends StatefulWidget {
  final VoidCallback? onGoToCart;
  final VoidCallback? onBackToHome;

  const ScanScreen({super.key, this.onGoToCart, this.onBackToHome});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final AudioPlayer player = AudioPlayer();
  final TextEditingController manualBarcodeController = TextEditingController();

  bool isLoadingProduct = false;
  bool isTorchOn = false;

  String lastScannedCode = '';
  DateTime? lastScanTime;

  @override
  void dispose() {
    controller.dispose();
    player.dispose();
    manualBarcodeController.dispose();
    super.dispose();
  }

  Future<void> _playBeep() async {
    await player.play(AssetSource('sounds/beep.mp3'));
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty) return;

    final String? code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();

    // Ignore repeat detections of the same barcode within 900 milliseconds.
    if (lastScannedCode == code &&
        lastScanTime != null &&
        now.difference(lastScanTime!).inMilliseconds < 900) {
      return;
    }

    // Handle one lookup at a time to prevent duplicate additions while waiting.
    if (isLoadingProduct) return;

    setState(() {
      isLoadingProduct = true;
      lastScannedCode = code;
      lastScanTime = now;
    });

    await _fetchAndAddProductByBarcode(code);
  }

  Future<void> _manualAddBarcode() async {
    final code = manualBarcodeController.text.trim();

    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter barcode first')));
      return;
    }

    if (isLoadingProduct) return;

    setState(() {
      isLoadingProduct = true;
      lastScannedCode = code;
      lastScanTime = DateTime.now();
    });

    await _fetchAndAddProductByBarcode(code);
    manualBarcodeController.clear();
  }

  // Camera scans and manual entry share product lookup and result messages.
  Future<void> _fetchAndAddProductByBarcode(String code) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product not found: $code'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final productData = querySnapshot.docs.first.data();

      final String name = (productData['name'] ?? '').toString();
      final double price = ((productData['price'] ?? 0) as num).toDouble();
      final String barcode = (productData['barcode'] ?? '').toString();
      final String image = (productData['image'] ?? '').toString();

      CartManager.addItem(
        name: name,
        price: price,
        barcode: barcode,
        image: image,
      );

      await _playBeep();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name added to cart'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading product: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoadingProduct = false);
    }
  }

  int get cartItemsCount {
    // Count all units, including multiple quantities of the same product.
    int total = 0;
    for (final item in CartManager.items) {
      total += item.quantity;
    }
    return total;
  }

  void _goToCart() {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    widget.onGoToCart?.call();
  }

  Future<void> _toggleFlash() async {
    await controller.toggleTorch();

    setState(() {
      isTorchOn = !isTorchOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(controller: controller, onDetect: _onDetect),

            Container(color: Colors.black.withValues(alpha: 0.28)),

            Positioned(
              top: 18,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.45),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    widget.onBackToHome?.call();
                  },
                ),
              ),
            ),

            Positioned(
              top: 18,
              right: 16,
              child: CircleAvatar(
                backgroundColor: isTorchOn
                    ? AppColors.primary
                    : Colors.black.withValues(alpha: 0.45),
                child: IconButton(
                  icon: Icon(
                    isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: isTorchOn ? AppColors.onBrand : Colors.white,
                  ),
                  onPressed: _toggleFlash,
                ),
              ),
            ),

            Column(
              children: [
                const SizedBox(height: 70),

                const Text(
                  'Scan barcode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Scan item or enter barcode manually',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: AppTypography.body,
                  ),
                ),

                const Spacer(),

                Center(
                  child: Container(
                    width: 260,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.cardRadius,
                      ),
                      border: Border.all(color: AppColors.primary, width: 3),
                    ),
                    child: Center(
                      child: Container(height: 2, color: AppColors.primary),
                    ),
                  ),
                ),

                const Spacer(),

                if (isLoadingProduct)
                  const CircularProgressIndicator(color: Colors.white),

                const SizedBox(height: 18),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: manualBarcodeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Enter barcode',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.45),
                            prefixIcon: const Icon(
                              Icons.keyboard,
                              color: Colors.white70,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.controlRadius,
                              ),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _manualAddBarcode(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: isLoadingProduct ? null : _manualAddBarcode,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 17,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.controlRadius,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: AppTypography.button,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _goToCart,
                      icon: const Icon(
                        Icons.shopping_cart,
                        color: AppColors.onBrand,
                      ),
                      label: Text(
                        'Go to Cart ($cartItemsCount)',
                        style: const TextStyle(
                          color: AppColors.onBrand,
                          fontSize: AppTypography.button,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.controlRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
