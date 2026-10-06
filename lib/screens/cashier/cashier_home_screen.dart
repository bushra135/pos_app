import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';
import '../cart/cart_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';

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
  bool isActive = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;
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
      if (!mounted) return;

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        isActive = userData['isActive'] == true;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadTodayStats(String cashierUid) async {
    try {
      // Include this cashier's sales for the local day, excluding tomorrow.
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
          if (!saleDate.isBefore(startOfDay) && saleDate.isBefore(endOfDay)) {
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

      // Cashier management shares this field; update the UI after Firestore saves it.
      final newStatus = !isActive;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'isActive': newStatus},
      );

      if (!mounted) return;
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.muted,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: "Scan",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: "Cart",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: AppColors.brandGradient,
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
                          style: TextStyle(
                            color: AppColors.onBrand,
                            fontSize: AppTypography.body,
                          ),
                        ),
                        Text(
                          cashierName.isEmpty ? "Cashier" : cashierName,
                          style: const TextStyle(
                            color: AppColors.onBrand,
                            fontSize: AppTypography.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _toggleUserStatus,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          // Keep status readable over the colored header.
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.cardRadius,
                          ),
                          border: Border.all(
                            color: isActive
                                ? AppColors.success
                                : AppColors.danger,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.check_circle_rounded
                                  : Icons.pause_circle_filled_rounded,
                              size: 16,
                              color: isActive
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isActive
                                  ? "Active • Ready"
                                  : "Inactive • Offline",
                              style: TextStyle(
                                color: isActive
                                    ? AppColors.success
                                    : AppColors.danger,
                                fontWeight: FontWeight.w700,
                                fontSize: AppTypography.caption,
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
                    color: AppColors.onBrand,
                    fontSize: AppTypography.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.attach_money,
                    iconColor: AppColors.success,
                    value: "BD ${todaySales.toStringAsFixed(3)}",
                    label: "My Sales Today",
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.receipt,
                    iconColor: AppColors.primaryDark,
                    value: todayTransactions.toString(),
                    label: "Transactions",
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Quick Actions",
                  style: TextStyle(
                    fontSize: AppTypography.section,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.qr_code_scanner,
                        label: "QR Scan",
                        gradient: true,
                        onTap: () => setState(() => selectedIndex = 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionButton(
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
                      child: _buildActionButton(
                        icon: Icons.inventory_2,
                        label: "Products",
                        subtitle: "Manage items",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProductsScreen(),
                            ),
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
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTypography.metric,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: AppTypography.label)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    String? subtitle,
    bool gradient = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: gradient ? null : Colors.white,
          gradient: gradient ? AppColors.brandGradient : null,
          border: gradient ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: gradient ? AppColors.onBrand : AppColors.primaryDark,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: gradient ? AppColors.onBrand : AppColors.text,
                  fontSize: AppTypography.button,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: AppTypography.caption,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
