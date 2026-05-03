import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../utils/cart_manager.dart';

class ScanScreen extends StatefulWidget {
  final VoidCallback? onGoToCart;
  final VoidCallback? onBackToHome;

  const ScanScreen({
    super.key,
    this.onGoToCart,
    this.onBackToHome,
  });

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
  final TextEditingController manualBarcodeController =
      TextEditingController();

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

    if (lastScannedCode == code &&
        lastScanTime != null &&
        now.difference(lastScanTime!).inMilliseconds < 900) {
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter barcode first')),
      );
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

  Future<void> _fetchAndAddProductByBarcode(String code) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (!mounted) return;

        setState(() {
          isLoadingProduct = false;
        });

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

      setState(() {
        isLoadingProduct = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name added to cart'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoadingProduct = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading product: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  int get cartItemsCount {
    int total = 0;
    for (final item in CartManager.items) {
      total += item.quantity;
    }
    return total;
  }

  void _goToCart() {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
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
            MobileScanner(
              controller: controller,
              onDetect: _onDetect,
            ),

            Container(color: Colors.black.withOpacity(0.28)),

            Positioned(
              top: 18,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.45),
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
                backgroundColor:
                    isTorchOn ? const Color.fromARGB(255, 70, 223, 175) : Colors.black.withOpacity(0.45),
                child: IconButton(
                  icon: Icon(
                    isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
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
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Scan item or enter barcode manually',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),

                const Spacer(),

                Center(
                  child: Container(
                    width: 260,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color.fromARGB(255, 164, 235, 213),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        height: 2,
                        color: const Color.fromARGB(255, 164, 235, 213),
                      ),
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
                            fillColor: Colors.black.withOpacity(0.45),
                            prefixIcon: const Icon(
                              Icons.keyboard,
                              color: Colors.white70,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
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
                          backgroundColor:
                              const Color.fromARGB(255, 70, 223, 175),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 17,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            color: Colors.white,
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
                        color: Colors.white,
                      ),
                      label: Text(
                        'Go to Cart ($cartItemsCount)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color.fromARGB(255, 70, 223, 175),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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