import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../products/products_screen.dart';
import '../reports/reports_screen.dart';
import '../ai/ai_screen.dart';
import '../profile/profile_screen.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int selectedIndex = 0;

  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // User data
  String firstName = '';
  String storeName = '';
  String storeCode = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  // Load user data from Firestore
  Future<void> _loadOwnerData() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final doc =
          await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data()!;

        // Extract first name from full name
        String fullName = data['fullName'] ?? '';
        String extractedFirstName =
            fullName.isNotEmpty ? fullName.split(' ')[0] : '';

        setState(() {
          firstName = extractedFirstName;
          storeName = data['storeName'] ?? '';
          storeCode = data['storeCode'] ?? '';
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Copy store code to clipboard
  void _copyStoreCode() {
    if (storeCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: storeCode));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Store code copied'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget currentScreen;

    // Handle bottom navigation
    switch (selectedIndex) {
      case 1:
        currentScreen = const ProductsScreen();
        break;
      case 2:
        currentScreen = const ReportsScreen();
        break;
      case 3:
        currentScreen = const AIScreen();
        break;
      case 4:
        currentScreen = const ProfileScreen();
        break;
      default:
        currentScreen = _buildHomeContent();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : currentScreen,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2F80FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "Products"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Reports"),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: "AI"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  // Build home UI
  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Left side (text)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome + owner name (small text)
                      Text(
                        "Welcome back, ${firstName.isEmpty ? "Owner" : firstName}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Store name (big text)
                      Text(
                        storeName.isEmpty ? "My Store" : storeName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right side (store code)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        storeCode.isEmpty ? 'No Code' : storeCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),

                      GestureDetector(
                        onTap: _copyStoreCode,
                        child: const Icon(
                          Icons.copy,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Dashboard cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _buildCard(
                  icon: Icons.attach_money,
                  color: Colors.green,
                  title: "Today's Sales",
                  value: "\$1,234.50",
                  subtitle: "+12.5%",
                ),
                _buildCard(
                  icon: Icons.warning_amber,
                  color: Colors.orange,
                  title: "Low Stock",
                  value: "5 Items",
                  subtitle: "Needs attention",
                ),
                _buildCard(
                  icon: Icons.trending_up,
                  color: Colors.blue,
                  title: "Best Seller",
                  value: "Chocolate Bar",
                  subtitle: "45 sold today",
                ),
                _buildCard(
                  icon: Icons.inventory,
                  color: Colors.purple,
                  title: "Total Products",
                  value: "142",
                  subtitle: "+8 this week",
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          // AI section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  "AI Insights",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text("View All", style: TextStyle(color: Colors.blue)),
              ],
            ),
          ),

          const SizedBox(height: 15),
        ],
      ),
    );
  }

  // Card widget
  Widget _buildCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(title),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}