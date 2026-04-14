import 'package:flutter/material.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final List<Map<String, dynamic>> products = [
    {
      "name": "Organic Milk 1L",
      "price": 3.50,
      "stock": 45,
      "category": "Dairy"
    },
    {
      "name": "Whole Wheat Bread",
      "price": 3.00,
      "stock": 28,
      "category": "Bakery"
    },
    {
      "name": "Fresh Eggs (12pc)",
      "price": 4.00,
      "stock": 18,
      "category": "Dairy"
    },
    {
      "name": "Olive Oil 500ml",
      "price": 6.50,
      "stock": 12,
      "category": "Grocery"
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [

              //Title
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

              //Search
              TextField(
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

              //List
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final item = products[index];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [

                          //Icon
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F7F3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.inventory,
                              color: Color(0xFF27BFA2),
                            ),
                          ),

                          const SizedBox(width: 12),

                          //Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item["name"],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  item["category"],
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  "\$${item["price"]}   •   ${item["stock"]} in stock",
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                          //Edit
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.teal,
                            ),
                          ),

                          //Delete
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
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