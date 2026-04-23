import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/cart_manager.dart';
import '../cashier/cashier_home_screen.dart';

class CheckoutReceiptScreen extends StatefulWidget {
  const CheckoutReceiptScreen({super.key});

  @override
  State<CheckoutReceiptScreen> createState() => _CheckoutReceiptScreenState();
}

class _CheckoutReceiptScreenState extends State<CheckoutReceiptScreen> {
  String selectedPaymentMethod = 'Cash';

  String storeName = '';
  String cashierName = '';
  String benefitNumber = '';
  String benefitQr = '';
  String storeCode = '';

  bool isLoading = true;
  bool isSavingSale = false;

  @override
  void initState() {
    super.initState();
    _loadStorePaymentData();
  }

  Future<void> _loadStorePaymentData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userData = userDoc.data()!;
      final String fullName = userData['fullName'] ?? '';
      final String firstName =
          fullName.isNotEmpty ? fullName.split(' ')[0] : '';
      final String fetchedStoreCode = userData['storeCode'] ?? '';

      String fetchedStoreName = userData['storeName'] ?? '';
      String fetchedBenefitNumber = '';
      String fetchedBenefitQr = '';

      if (fetchedStoreCode.isNotEmpty) {
        final storeDoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(fetchedStoreCode)
            .get();

        if (storeDoc.exists) {
          final storeData = storeDoc.data()!;
          fetchedStoreName = storeData['storeName'] ?? fetchedStoreName;
          fetchedBenefitNumber = storeData['benefitNumber'] ?? '';
          fetchedBenefitQr = storeData['benefitQr'] ?? '';
        }
      }

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        storeCode = fetchedStoreCode;
        benefitNumber = fetchedBenefitNumber;
        benefitQr = fetchedBenefitQr;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  String get receiptNumber {
    final now = DateTime.now();
    return 'RCPT${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmPayment() async {
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty'),
        ),
      );
      return;
    }

    setState(() {
      isSavingSale = true;
    });

    try {
      final items = CartManager.items.map((item) {
        return {
          'name': item.name,
          'price': item.price,
          'quantity': item.quantity,
          'barcode': item.barcode,
          'image': item.image,
          'subtotal': item.totalPrice,
        };
      }).toList();

      await FirebaseFirestore.instance.collection('sales').add({
        'storeCode': storeCode,
        'storeName': storeName,
        'cashierUid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'cashierName': cashierName,
        'paymentMethod': selectedPaymentMethod,
        'total': CartManager.total,
        'receiptNumber': receiptNumber,
        'items': items,
        'createdAt': FieldValue.serverTimestamp(),
      });

      CartManager.clearCart();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale saved successfully'),
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const CashierHomeScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save sale: $e'),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        isSavingSale = false;
      });
    }
  }

  Widget _buildPaymentOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color.fromARGB(255, 230, 248, 255)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? const Color.fromARGB(255, 5, 197, 245)
                  : Colors.grey.shade300,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color.fromARGB(255, 5, 197, 245)
                    : Colors.grey,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? const Color.fromARGB(255, 5, 197, 245)
                      : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptItem({
    required String name,
    required int quantity,
    required double price,
    required double subtotal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            'x$quantity',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Text(
            'BD ${subtotal.toStringAsFixed(3)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = CartManager.items;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.fromARGB(255, 164, 235, 213),
                          Color.fromARGB(255, 5, 197, 245),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white.withOpacity(0.25),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Payment & Receipt',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Review payment and invoice details',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payment Method',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _buildPaymentOption(
                                    title: 'Cash',
                                    icon: Icons.payments_outlined,
                                    isSelected:
                                        selectedPaymentMethod == 'Cash',
                                    onTap: () {
                                      setState(() {
                                        selectedPaymentMethod = 'Cash';
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  _buildPaymentOption(
                                    title: 'BenefitPay',
                                    icon: Icons.qr_code,
                                    isSelected:
                                        selectedPaymentMethod == 'BenefitPay',
                                    onTap: () {
                                      setState(() {
                                        selectedPaymentMethod = 'BenefitPay';
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F8FC),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total Amount',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'BD ${CartManager.total.toStringAsFixed(3)}',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color.fromARGB(255, 5, 197, 245),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selectedPaymentMethod == 'BenefitPay') ...[
                                const SizedBox(height: 18),
                                if (benefitNumber.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F8FC),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'BenefitPay Number',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          benefitNumber,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (benefitQr.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F8FC),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      children: [
                                        const Text(
                                          'Scan to pay',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: Image.network(
                                            benefitQr,
                                            height: 180,
                                            width: 180,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                height: 180,
                                                width: 180,
                                                color: Colors.grey.shade200,
                                                child: const Icon(
                                                  Icons.qr_code,
                                                  size: 70,
                                                  color: Colors.grey,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Receipt',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Store',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    storeName.isEmpty ? 'My Store' : storeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Cashier',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    cashierName.isEmpty
                                        ? 'Cashier'
                                        : cashierName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Receipt No.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  Text(
                                    receiptNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Divider(color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              ...cartItems.map(
                                (item) => _buildReceiptItem(
                                  name: item.name,
                                  quantity: item.quantity,
                                  price: item.price,
                                  subtotal: item.totalPrice,
                                ),
                              ),
                              Divider(color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'BD ${CartManager.total.toStringAsFixed(3)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color.fromARGB(255, 5, 197, 245),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSavingSale ? null : _confirmPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color.fromARGB(255, 70, 223, 175),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSavingSale
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    selectedPaymentMethod == 'Cash'
                                        ? 'Confirm Cash Payment'
                                        : 'Payment Received',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}