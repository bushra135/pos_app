import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  bool _isHandled = false;
  bool isLoadingProduct = false;
  String scannedCode = '';

  Map<String, dynamic>? scannedProduct;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isHandled) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() {
      _isHandled = true;
      scannedCode = code;
      isLoadingProduct = true;
      scannedProduct = null;
    });

    await _fetchProductByBarcode(code);
  }

  Future<void> _fetchProductByBarcode(String code) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('barcode', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final productData = querySnapshot.docs.first.data();

        setState(() {
          scannedProduct = productData;
          isLoadingProduct = false;
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Product found: ${productData['name'] ?? 'Unknown'}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          scannedProduct = null;
          isLoadingProduct = false;
        });

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product not found'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isLoadingProduct = false;
        scannedProduct = null;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading product: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetScanner() {
    setState(() {
      _isHandled = false;
      scannedCode = '';
      scannedProduct = null;
      isLoadingProduct = false;
    });
  }

  void _goToCart() {
    if (scannedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan a product first'),
        ),
      );
      return;
    }

    final String name = (scannedProduct!['name'] ?? '').toString();
    final double price =
        ((scannedProduct!['price'] ?? 0) as num).toDouble();
    final String barcode = (scannedProduct!['barcode'] ?? '').toString();
    final String image = (scannedProduct!['image'] ?? '').toString();

    CartManager.addItem(
      name: name,
      price: price,
      barcode: barcode,
      image: image,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CartScreen(),
      ),
    );
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
                  'Align the barcode inside the frame',
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
                if (scannedCode.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Scanned code: $scannedCode',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
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
                if (scannedProduct != null && !isLoadingProduct)
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
                          Text(
                            scannedProduct!['name'] ?? 'Unknown product',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Price: BD ${((scannedProduct!['price'] ?? 0) as num).toStringAsFixed(3)}',
                            style: const TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _resetScanner,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Scan Again',
                            style: TextStyle(color: Colors.white),
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