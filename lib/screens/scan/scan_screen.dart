import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';

import '../cashier/cashier_home_screen.dart';
import '../cart/cart_screen.dart';
import '../../utils/cart_manager.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

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

  bool isLoadingProduct = false;

  String scannedCode = '';
  String lastScannedCode = '';
  String lastScannedProductName = '';
  DateTime? lastScanTime;

  @override
  void dispose() {
    controller.dispose();
    player.dispose();
    super.dispose();
  }

  // Play cashier beep sound after successful scan
  Future<void> _playBeep() async {
    await player.play(AssetSource('sounds/beep.mp3'));
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final DateTime now = DateTime.now();

    // Prevent instant duplicate scan from the same camera frame
    if (lastScannedCode == code &&
        lastScanTime != null &&
        now.difference(lastScanTime!).inMilliseconds < 700) {
      return;
    }

    if (isLoadingProduct) return;

    setState(() {
      isLoadingProduct = true;
      scannedCode = code;
      lastScannedCode = code;
      lastScanTime = now;
    });

    await _fetchAndAddProductByBarcode(code);
  }

  Future<void> _fetchAndAddProductByBarcode(String code) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
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
          lastScannedProductName = name;
          isLoadingProduct = false;
        });
      } else {
        if (!mounted) return;

        setState(() {
          lastScannedProductName = 'Product not found';
          isLoadingProduct = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product not found'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        lastScannedProductName = 'Error loading product';
        isLoadingProduct = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading product: $e'),
          duration: const Duration(seconds: 1),
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
        const SnackBar(
          content: Text('Cart is empty'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CartScreen(),
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(
              controller: controller,
              onDetect: _onDetect,
            ),

            Container(
              color: Colors.black.withOpacity(0.35),
            ),

            Column(
              children: [
                const SizedBox(height: 20),

                const Text(
                  'Scan barcode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Scan all customer items, then go to cart',
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
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            height: 2,
                            color: const Color.fromARGB(255, 164, 235, 213),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (scannedCode.isNotEmpty)
                          Text(
                            'Last barcode: $scannedCode',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (scannedCode.isNotEmpty)
                          const SizedBox(height: 8),
                        Text(
                          lastScannedProductName.isEmpty
                              ? 'Ready to scan'
                              : 'Last item: $lastScannedProductName',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Items in cart: $cartItemsCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (isLoadingProduct)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _goToCart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color.fromARGB(255, 70, 223, 175),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Go to Cart',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),

            Positioned(
              top: 18,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.45),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CashierHomeScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),

            Positioned(
              top: 18,
              right: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.45),
                child: IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.white),
                  onPressed: () => controller.toggleTorch(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}