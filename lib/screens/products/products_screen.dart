import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  void _clearControllers({
    required TextEditingController nameController,
    required TextEditingController categoryController,
    required TextEditingController priceController,
    required TextEditingController stockController,
    required TextEditingController barcodeController,
    required TextEditingController imageController,
  }) {
    nameController.clear();
    categoryController.clear();
    priceController.clear();
    stockController.clear();
    barcodeController.clear();
    imageController.clear();
  }

  void _showProductDialog({String? docId, Map<String, dynamic>? product}) {
    final TextEditingController nameController =
        TextEditingController(text: product?['name']?.toString() ?? '');
    final TextEditingController categoryController =
        TextEditingController(text: product?['category']?.toString() ?? '');
    final TextEditingController priceController =
        TextEditingController(text: product?['price']?.toString() ?? '');
    final TextEditingController stockController =
        TextEditingController(text: product?['stock']?.toString() ?? '');
    final TextEditingController barcodeController =
        TextEditingController(text: product?['barcode']?.toString() ?? '');
    final TextEditingController imageController =
        TextEditingController(text: product?['image']?.toString() ?? '');

    final bool isEdit = docId != null;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEdit ? "Edit Product" : "Add Product",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildField(nameController, "Product Name"),
                  _buildField(categoryController, "Category"),
                  _buildField(
                    priceController,
                    "Price",
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _buildField(
                    stockController,
                    "Stock",
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(barcodeController, "Barcode"),
                  _buildField(imageController, "Image URL"),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
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
                                barcode.isEmpty ||
                                image.isEmpty) {
                              _showMessage(
                                'Please fill all fields correctly',
                              );
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

                              _clearControllers(
                                nameController: nameController,
                                categoryController: categoryController,
                                priceController: priceController,
                                stockController: stockController,
                                barcodeController: barcodeController,
                                imageController: imageController,
                              );
                            } catch (e) {
                              _showMessage('Something went wrong');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF05C5F5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(isEdit ? "Save" : "Add"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(),
        backgroundColor: const Color(0xFF05C5F5),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Products",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                onChanged: (value) {
                  setState(() {
                    searchText = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: "Search products...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('products')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (snapshot.hasError) {
                      return const Center(
                        child: Text('Something went wrong'),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    final filteredDocs = docs.where((doc) {
                      final item = doc.data() as Map<String, dynamic>;

                      final String name =
                          (item["name"] ?? '').toString().toLowerCase();
                      final String category =
                          (item["category"] ?? '').toString().toLowerCase();
                      final String barcode =
                          (item["barcode"] ?? '').toString().toLowerCase();

                      return searchText.isEmpty ||
                          name.contains(searchText) ||
                          category.contains(searchText) ||
                          barcode.contains(searchText);
                    }).toList();

                    if (filteredDocs.isEmpty) {
                      return const Center(
                        child: Text("No products found"),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final doc = filteredDocs[index];
                        final item = doc.data() as Map<String, dynamic>;
                        final String docId = doc.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 55,
                                height: 55,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(
                                    255,
                                    199,
                                    235,
                                    245,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: (item["image"] != null &&
                                        item["image"]
                                            .toString()
                                            .isNotEmpty)
                                    ? Image.network(
                                        item["image"],
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.inventory,
                                            color: Color.fromARGB(
                                              255,
                                              5,
                                              197,
                                              245,
                                            ),
                                          );
                                        },
                                      )
                                    : const Icon(
                                        Icons.inventory,
                                        color: Color.fromARGB(
                                          255,
                                          5,
                                          197,
                                          245,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (item["name"] ?? '').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      (item["category"] ?? '').toString(),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "\$${item["price"]}   •   ${item["stock"]} in stock",
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      "Barcode: ${(item["barcode"] ?? '').toString()}",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _showProductDialog(
                                    docId: docId,
                                    product: item,
                                  );
                                },
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.teal,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _showDeleteDialog(
                                    docId,
                                    (item["name"] ?? '').toString(),
                                  );
                                },
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
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