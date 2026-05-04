import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
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
    final docs = [...(snapshot?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])];

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
    final value = item['stock'] ?? item['quantity'] ?? 0;

    if (value is num) return value.toInt();

    return int.tryParse(value.toString()) ?? 0;
  }

  int _minStockFrom(Map<String, dynamic> item) {
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

    if (stock <= 0) return Colors.red;
    if (stock <= minStock) return Colors.orange;

    return Colors.black87;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<String?> _scanBarcode() async {
    String? scannedCode;

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 420,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
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
                      fontWeight: FontWeight.bold,
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

  void _showProductDialog({String? docId, Map<String, dynamic>? product}) {
    final nameController =
        TextEditingController(text: product?['name']?.toString() ?? '');
    final categoryController =
        TextEditingController(text: product?['category']?.toString() ?? '');
    final priceController =
        TextEditingController(text: product?['price']?.toString() ?? '');
    final stockController =
        TextEditingController(text: product?['stock']?.toString() ?? '');
    final minStockController = TextEditingController(
      text: (product?['minStock'] ??
              product?['minQuantity'] ??
              product?['minimumStock'] ??
              5)
          .toString(),
    );
    final barcodeController =
        TextEditingController(text: product?['barcode']?.toString() ?? '');
    final imageController =
        TextEditingController(text: product?['image']?.toString() ?? '');

    final bool isEdit = docId != null;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
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
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildField(nameController, 'Product Name'),
                  _buildField(categoryController, 'Category'),
                  _buildField(
                    priceController,
                    'Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _buildField(
                    stockController,
                    'Stock',
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(
                    minStockController,
                    'Low Stock Alert Limit',
                    keyboardType: TextInputType.number,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          barcodeController,
                          'Barcode',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F9FD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: Color(0xFF05C5F5),
                            ),
                            onPressed: () async {
                              final result = await _scanBarcode();
                              if (result != null) {
                                barcodeController.text = result;
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildField(imageController, 'Image URL'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final String name = nameController.text.trim();
                            final String category =
                                categoryController.text.trim();
                            final double? price =
                                double.tryParse(priceController.text.trim());
                            final int? stock =
                                int.tryParse(stockController.text.trim());
                            final int minStock =
                                int.tryParse(minStockController.text.trim()) ??
                                    5;
                            final String barcode =
                                barcodeController.text.trim();
                            final String image = imageController.text.trim();

                            if (storeCode.isEmpty) {
                              _showMessage('Store code not found');
                              return;
                            }

                            if (name.isEmpty ||
                                category.isEmpty ||
                                price == null ||
                                stock == null ||
                                minStock < 0 ||
                                barcode.isEmpty) {
                              _showMessage(
                                'Please fill all required fields correctly',
                              );
                              return;
                            }

                            final duplicateBarcodeQuery = await _firestore
                                .collection('products')
                                .where('barcode', isEqualTo: barcode)
                                .get();

                            final bool barcodeExists =
                                duplicateBarcodeQuery.docs.any((doc) {
                              final data = doc.data();
                              final productStoreCode =
                                  (data['storeCode'] ?? '').toString().trim();

                              return doc.id != docId &&
                                  productStoreCode == storeCode;
                            });

                            if (barcodeExists) {
                              _showMessage('This barcode already exists');
                              return;
                            }

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

                            try {
                              if (isEdit) {
                                await _firestore
                                    .collection('products')
                                    .doc(docId)
                                    .update(productData);

                                if (!mounted) return;
                                Navigator.pop(context);
                                _showMessage('Product updated successfully');
                              } else {
                                await _firestore.collection('products').add({
                                  ...productData,
                                  'createdAt': FieldValue.serverTimestamp(),
                                });

                                if (!mounted) return;
                                Navigator.pop(context);
                                _showMessage('Product added successfully');
                              }
                            } catch (e) {
                              debugPrint('Product save error: $e');
                              _showMessage('Something went wrong');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF05C5F5),
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            isEdit ? 'Save' : 'Add Product',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
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
        );
      },
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF6F8FC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
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

                if (!mounted) return;

                Navigator.pop(context);
                _showMessage('Product deleted successfully');
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
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
                color: Color(0xFFF6F8FC),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D5DD),
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
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2A44),
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
                              ? Colors.green.withOpacity(0.12)
                              : Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${lowStockDocs.length}',
                          style: TextStyle(
                            color:
                                lowStockDocs.isEmpty ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w800,
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
                                color: Color(0xFF98A2B3),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: lowStockDocs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = lowStockDocs[index];
                              final item = doc.data();

                              final name = (item['name'] ?? '').toString();
                              final image = (item['image'] ?? '').toString();
                              final stock = _stockFrom(item);
                              final minStock = _minStockFrom(item);
                              final status =
                                  stock <= 0 ? 'Out of stock' : 'Low stock';

                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
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
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFEFF3F8),
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
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF1F2A44),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '$status · $stock left · minimum $minStock',
                                                style: TextStyle(
                                                  color: stock <= 0
                                                      ? Colors.red
                                                      : Colors.orange,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF98A2B3),
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
                  color: count > 0 ? Colors.red : Colors.black87,
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
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
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
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 199, 235, 245),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.inventory_2,
                  color: Color.fromARGB(255, 5, 197, 245),
                  size: 22,
                );
              },
            )
          : const Icon(
              Icons.inventory_2,
              color: Color.fromARGB(255, 5, 197, 245),
              size: 22,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    final int columns = screenWidth >= 900
        ? 6
        : screenWidth >= 650
            ? 5
            : screenWidth >= 450
                ? 4
                : 3;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F8FC),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Products',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          _buildNotificationButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: storeCode.isEmpty ? null : () => _showProductDialog(),
        backgroundColor: const Color(0xFF05C5F5),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: isLoadingStore
            ? const Center(child: CircularProgressIndicator())
            : storeCode.isEmpty
                ? const Center(child: Text('Store code not found'))
                : Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
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
                                final String category =
                                    (item['category'] ?? '')
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

                              return GridView.builder(
                                padding: const EdgeInsets.only(bottom: 90),
                                itemCount: filteredDocs.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 0.82,
                                ),
                                itemBuilder: (context, index) {
                                  final doc = filteredDocs[index];
                                  final item = doc.data();
                                  final String docId = doc.id;

                                  final String name =
                                      (item['name'] ?? '').toString();
                                  final String image =
                                      (item['image'] ?? '').toString();

                                  final stock = _stockFrom(item);
                                  final stockText = _stockText(item);
                                  final stockColor = _stockColor(item);

                                  return Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _productImage(image),
                                            const Spacer(),
                                            InkWell(
                                              onTap: () {
                                                _showProductDialog(
                                                  docId: docId,
                                                  product: item,
                                                );
                                              },
                                              child: const Icon(
                                                Icons.edit,
                                                color: Colors.teal,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () {
                                                _showDeleteDialog(docId, name);
                                              },
                                              child: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '\$${item['price']}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          stockText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: stockColor,
                                            fontWeight: stock <=
                                                    _minStockFrom(item)
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
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
