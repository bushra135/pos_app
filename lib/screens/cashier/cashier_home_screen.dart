import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../services/sale_sync_service.dart';
import '../../widgets/sale_sync_panel.dart';
import '../cart/cart_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';

class CashierHomeScreen extends StatefulWidget {
  const CashierHomeScreen({
    super.key,
    this.onSwitchToOwner,
    this.firestore,
    this.currentUserId,
  });

  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  // Supplied only by the authenticated owner workspace, never by cashier login.
  final VoidCallback? onSwitchToOwner;

  @override
  State<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends State<CashierHomeScreen> {
  int selectedIndex = 0;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;
  String? get _userId => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;

  String cashierName = '';
  String storeName = '';
  String _storeCode = '';
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
      final uid = _userId;
      if (uid == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final sync = SaleSyncService.maybeInstance;
      Map<String, dynamic> userData;
      Map<String, dynamic> store = {};
      if (sync != null) {
        final cachedContext = await sync.loadContext(uid);
        userData = Map<String, dynamic>.from(cachedContext['profile'] as Map);
        store = Map<String, dynamic>.from(cachedContext['store'] as Map);
      } else {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (!userDoc.exists) {
          if (!mounted) return;
          setState(() => isLoading = false);
          return;
        }
        userData = userDoc.data()!;
      }

      final fullName = userData['fullName'] ?? '';
      final firstName = fullName.isNotEmpty ? fullName.split(' ')[0] : '';

      final storeCode = userData['storeCode'] ?? '';
      String fetchedStoreName =
          store['storeName'] ?? userData['storeName'] ?? '';
      if (sync == null && storeCode.isNotEmpty) {
        final storeDoc = await _firestore
            .collection('stores')
            .doc(storeCode)
            .get();
        if (storeDoc.exists) {
          fetchedStoreName = storeDoc.data()?['storeName'] ?? '';
        }
      }

      if (!mounted) return;

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        _storeCode = storeCode;
        isActive = userData['onDuty'] ?? true;
        isLoading = false;
      });
      await _loadTodayStats(uid);
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

      final snapshot = await _firestore
          .collection('sales')
          .where('cashierUid', isEqualTo: cashierUid)
          .where('storeCode', isEqualTo: _storeCode)
          .get(
            SaleSyncService.maybeInstance?.online == false
                ? const GetOptions(source: Source.cache)
                : const GetOptions(),
          );

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
      final uid = _userId;
      if (uid == null) return;

      // Availability is separate from owner-controlled account approval.
      final newStatus = !isActive;
      await _firestore.collection('users').doc(uid).update({
        'onDuty': newStatus,
      });

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
            setState(() => selectedIndex = 1);
            final uid = _userId;
            if (uid != null) {
              await _loadTodayStats(uid);
              // Keep the next sale camera open while refreshing statistics.
            }
          },
        );
        break;
      case 3:
        currentScreen = ProfileScreen(
          onSwitchMode: widget.onSwitchToOwner,
          cashierMode: widget.onSwitchToOwner != null,
        );
        break;
      default:
        currentScreen = _buildHomeContent();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SaleSyncPanel(),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : currentScreen,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) async {
          setState(() => selectedIndex = index);
          if (index == 0) {
            final uid = _userId;
            if (uid != null) await _loadTodayStats(uid);
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
              color: AppColors.primary,
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

          if (widget.onSwitchToOwner != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onSwitchToOwner,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Switch to owner'),
                ),
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
                        label: "Start sale",
                        highlighted: true,
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
        color: AppColors.surface,
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
    bool highlighted = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primary : AppColors.surface,
          border: highlighted ? null : Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: highlighted ? AppColors.onBrand : AppColors.primaryDark,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? AppColors.onBrand : AppColors.text,
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
