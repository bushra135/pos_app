import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../products/products_screen.dart';
import '../reports/reports_screen.dart';
import '../ai/ai_screen.dart';
import '../profile/profile_screen.dart';
import 'cashiers_management_screen.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int selectedIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String firstName = '';
  String storeName = '';
  String storeCode = '';
  bool isLoading = true;

  double todaySales = 0.0;
  int lowStockCount = 0;
  String bestSellerName = '';
  int bestSellerSold = 0;
  int totalProducts = 0;
  int cashierCount = 0;
  int activeCashierCount = 0;

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  Future<void> _loadOwnerData() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final data = doc.data()!;
      final fullName = data['fullName'] ?? '';
      final ownerStoreCode = data['storeCode'] ?? '';

      if (!mounted) return;

      setState(() {
        firstName = fullName.isNotEmpty ? fullName.split(' ')[0] : '';
        storeName = data['storeName'] ?? '';
        storeCode = ownerStoreCode;
        isLoading = false;
      });

      if (ownerStoreCode.isNotEmpty) {
        await _loadDashboardData(ownerStoreCode);
      }
    } catch (e) {
      debugPrint('Error loading owner data: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadDashboardData(String code) async {
    try {
      final cashiersSnapshot = await _firestore
          .collection('users')
          .where('storeCode', isEqualTo: code)
          .where('role', isEqualTo: 'cashier')
          .get();

      final totalCashiers = cashiersSnapshot.docs.length;
      final activeCashiers = cashiersSnapshot.docs.where((doc) {
        final data = doc.data();
        return (data['isActive'] ?? false) == true;
      }).length;

      final productsSnapshot = await _firestore
          .collection('products')
          .where('storeCode', isEqualTo: code)
          .get();

      int lowStock = 0;
      int total = productsSnapshot.docs.length;
      String topProduct = '';
      int topSold = 0;

      for (var doc in productsSnapshot.docs) {
        final data = doc.data();

        final quantity = ((data['quantity'] ?? 0) as num).toInt();
        final minQty = ((data['minQuantity'] ?? 0) as num).toInt();
        final sold = ((data['soldCount'] ?? 0) as num).toInt();

        if (quantity <= minQty) lowStock++;

        if (sold > topSold) {
          topSold = sold;
          topProduct = data['name'] ?? '';
        }
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final salesSnapshot = await _firestore
          .collection('sales')
          .where('storeCode', isEqualTo: code)
          .get();

      double totalSales = 0.0;

      for (var sale in salesSnapshot.docs) {
        final data = sale.data();
        final createdAt = data['createdAt'];

        if (createdAt is Timestamp) {
          final date = createdAt.toDate();

          if (!date.isBefore(startOfDay) && date.isBefore(endOfDay)) {
            totalSales += ((data['total'] ?? 0) as num).toDouble();
          }
        }
      }

      if (!mounted) return;

      setState(() {
        todaySales = totalSales;
        lowStockCount = lowStock;
        bestSellerName = topProduct;
        bestSellerSold = topSold;
        totalProducts = total;
        cashierCount = totalCashiers;
        activeCashierCount = activeCashiers;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }

  void _copyStoreCode() {
    if (storeCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: storeCode));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Store code copied')),
    );
  }

  Future<void> _openCashiersManagement() async {
    if (storeCode.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashiersManagementScreen(storeCode: storeCode),
      ),
    );

    await _loadDashboardData(storeCode);
  }

  @override
  Widget build(BuildContext context) {
    Widget currentScreen;

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
        onTap: (index) => setState(() => selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2F80FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: "Products",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: "Reports",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: "AI"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                _buildMetricCard(
                  icon: Icons.attach_money,
                  color: Colors.green,
                  title: "Today's Sales",
                  value: "\$${todaySales.toStringAsFixed(2)}",
                  subtitle: todaySales > 0
                      ? "+${(todaySales / 100).toStringAsFixed(1)}%"
                      : "+0%",
                ),
                _buildMetricCard(
                  icon: Icons.warning_amber,
                  color: Colors.orange,
                  title: "Low Stock",
                  value: "$lowStockCount Items",
                  subtitle: lowStockCount > 0 ? "Needs attention" : "All good",
                ),
                _buildMetricCard(
                  icon: Icons.inventory,
                  color: Colors.purple,
                  title: "Total Products",
                  value: "$totalProducts",
                  subtitle: "+0 this week",
                ),
                _buildMetricCard(
                  icon: Icons.trending_up,
                  color: Colors.blue,
                  title: "Best Seller",
                  value: bestSellerName.isEmpty ? "No data" : bestSellerName,
                  subtitle: "$bestSellerSold sold",
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildCashiersCard(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF8BE3D0),
            Color(0xFF18BFE8),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome back, ${firstName.isEmpty ? "Owner" : firstName}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  storeName.isEmpty ? "My Store" : storeName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _copyStoreCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    storeCode.isEmpty ? 'No Code' : storeCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEFF3F8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2940).withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2430),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D313A),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashiersCard() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: _openCashiersManagement,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEFF3F8)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B2940).withOpacity(0.07),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: Colors.teal,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$cashierCount Cashiers",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2430),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "$activeCashierCount active cashiers",
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.teal,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
