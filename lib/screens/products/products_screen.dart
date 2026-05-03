import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController searchController = TextEditingController();

  String searchText = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
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
                            final String barcode =
                                barcodeController.text.trim();
                            final String image = imageController.text.trim();

                            if (name.isEmpty ||
                                category.isEmpty ||
                                price == null ||
                                stock == null ||
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
                                duplicateBarcodeQuery.docs.any(
                              (doc) => doc.id != docId,
                            );

                            if (barcodeExists) {
                              _showMessage('This barcode already exists');
                              return;
                            }

                            final Map<String, dynamic> productData = {
                              'name': name,
                              'category': category,
                              'price': price,
                              'stock': stock,
                              'barcode': barcode,
                              'image': image,
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(),
        backgroundColor: const Color(0xFF05C5F5),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('products')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return const Center(child: Text('Something went wrong'));
                    }

                    final docs = snapshot.data?.docs ?? [];

                    final filteredDocs = docs.where((doc) {
                      final item = doc.data() as Map<String, dynamic>;

                      final String name =
                          (item['name'] ?? '').toString().toLowerCase();
                      final String category =
                          (item['category'] ?? '').toString().toLowerCase();
                      final String barcode =
                          (item['barcode'] ?? '').toString().toLowerCase();

                      return searchText.isEmpty ||
                          name.contains(searchText) ||
                          category.contains(searchText) ||
                          barcode.contains(searchText);
                    }).toList();

                    if (filteredDocs.isEmpty) {
                      return const Center(child: Text('No products found'));
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: filteredDocs.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.82,
                      ),
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final item = doc.data() as Map<String, dynamic>;
                        final String docId = doc.id;

                        final String name = (item['name'] ?? '').toString();
                        final String image = (item['image'] ?? '').toString();
                        final int stock =
                            ((item['stock'] ?? 0) as num).toInt();

                        String stockText;
                        Color stockColor;

                        if (stock <= 0) {
                          stockText = 'Out';
                          stockColor = Colors.red;
                        } else if (stock <= 5) {
                          stockText = 'Low $stock';
                          stockColor = Colors.orange;
                        } else {
                          stockText = '$stock left';
                          stockColor = Colors.black87;
                        }

                        return Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                  fontWeight: stock <= 5
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