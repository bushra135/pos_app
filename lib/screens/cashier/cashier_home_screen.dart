import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../products/products_screen.dart';
import '../scan/scan_screen.dart';
import '../cart/cart_screen.dart';
import '../profile/profile_screen.dart';

class CashierHomeScreen extends StatefulWidget {
  const CashierHomeScreen({super.key});

  @override
  State<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends State<CashierHomeScreen> {
  int selectedIndex = 0;

  String cashierName = '';
  String storeName = '';
  bool isLoading = true;

  double todaySales = 0.0;
  int todayTransactions = 0;
  bool isActive = false; // 🔹 حالة المستخدم

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() => isLoading = false);
        return;
      }

      final userData = userDoc.data()!;
      final fullName = userData['fullName'] ?? '';
      final firstName = fullName.isNotEmpty ? fullName.split(' ')[0] : '';

      final storeCode = userData['storeCode'] ?? '';
      String fetchedStoreName = '';
      if (storeCode.isNotEmpty) {
        final storeDoc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeCode)
            .get();
        if (storeDoc.exists) {
          fetchedStoreName = storeDoc.data()?['storeName'] ?? '';
        }
      }

      await _loadTodayStats(user.uid);

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        isActive = userData['isActive'] == true; // 🔹 تحميل الحالة الحقيقية
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadTodayStats(String cashierUid) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await FirebaseFirestore.instance
          .collection('sales')
          .where('cashierUid', isEqualTo: cashierUid)
          .get();

      double total = 0.0;
      int count = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final saleDate = createdAt.toDate();
          if (saleDate.isAfter(startOfDay) && saleDate.isBefore(endOfDay)) {
            total += ((data['total'] ?? 0) as num).toDouble();
            count++;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        todaySales = total;
        todayTransactions = count;
      });
    } catch (e) {
      debugPrint('Error loading today stats: $e');
    }
  }

  Future<void> _toggleUserStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final newStatus = !isActive;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'isActive': newStatus});

      setState(() => isActive = newStatus);
    } catch (e) {
      debugPrint('Error toggling user status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget currentScreen;
    switch (selectedIndex) {
      case 1:
        currentScreen = ScanScreen(
          onGoToCart: () => setState(() => selectedIndex = 2),
          onBackToHome: () => setState(() => selectedIndex = 0),
        );
        break;
      case 2:
        currentScreen = CartScreen(
          onBackToHome: () => setState(() => selectedIndex = 0),
          onSaleCompleted: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await _loadTodayStats(user.uid);
              if (mounted) setState(() => selectedIndex = 0);
            }
          },
        );
        break;
      case 3:
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
        onTap: (index) async {
          setState(() => selectedIndex = index);
          if (index == 0) {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) await _loadTodayStats(user.uid);
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2F80FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: "Scan"),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Cart"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // ===== HEADER =====
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFA4EBD5), Color(0xFF05C5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Welcome back, ",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          cashierName.isEmpty ? "Cashier" : cashierName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _toggleUserStatus, // 🔹 الضغط لتبديل الحالة
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                isActive ? Colors.green : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 6,
                              backgroundColor:
                                  isActive ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isActive
                                  ? "Active • Ready"
                                  : "Inactive • Offline",
                              style: TextStyle(
                                color: isActive
                                    ? Colors.green[900]
                                    : Colors.red[900],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  storeName.isEmpty ? "My Store" : storeName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ===== STATS =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.attach_money,
                    iconColor: Colors.green,
                    value: "BD ${todaySales.toStringAsFixed(3)}",
                    label: "My Sales Today",
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.receipt,
                    iconColor: Colors.blue,
                    value: todayTransactions.toString(),
                    label: "Transactions",
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          // ===== QUICK ACTIONS =====
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Quick Actions",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildGradientButton(
                        icon: Icons.qr_code_scanner,
                        label: "QR Scan",
                        onTap: () => setState(() => selectedIndex = 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildOutlinedButton(
                        icon: Icons.shopping_cart,
                        label: "Cart",
                        onTap: () => setState(() => selectedIndex = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildOutlinedButton(
                        icon: Icons.inventory_2,
                        label: "Products",
                        subtitle: "Manage items",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ProductsScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: SizedBox(height: 100)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
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
          Icon(icon, color: iconColor),
          const SizedBox(height: 10),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFA4EBD5), Color(0xFF05C5F5)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutlinedButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Text(subtitle,
                    style: const TextStyle(color: Colors.blue, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
