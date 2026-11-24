import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../services/sale_sync_service.dart';
import '../../services/sales_query.dart';
import '../../utils/cart_manager.dart';
import '../../widgets/sale_sync_panel.dart';
import '../cart/cart_screen.dart';
import '../closing/end_of_day_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';

/// Hosts cashier navigation and daily statistics without changing the account role.
class CashierHomeScreen extends StatefulWidget {
  const CashierHomeScreen({super.key, this.onSwitchToOwner, this.firestore, this.currentUserId});

  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  // Supplied only by the authenticated owner workspace, never by cashier login.
  final VoidCallback? onSwitchToOwner;

  @override
  State<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends State<CashierHomeScreen> {
  int selectedIndex = 0;
  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
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
      String fetchedStoreName = store['storeName'] ?? userData['storeName'] ?? '';
      if (sync == null && storeCode.isNotEmpty) {
        final storeDoc = await _firestore.collection('stores').doc(storeCode).get();
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

      // Only today's receipts for this cashier.
      final salesDocs = await SalesQuery.since(
        _firestore,
        storeCode: _storeCode,
        cashierUid: cashierUid,
        from: startOfDay,
        options: SaleSyncService.maybeInstance?.online == false
            ? const GetOptions(source: Source.cache)
            : const GetOptions(),
      );

      double total = 0.0;
      int count = 0;
      for (final doc in salesDocs) {
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
      await _firestore.collection('users').doc(uid).update({'onDuty': newStatus});

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
              child: isLoading ? const Center(child: CircularProgressIndicator()) : currentScreen,
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) async {
            setState(() => selectedIndex = index);
            if (index == 0) {
              final uid = _userId;
              if (uid != null) await _loadTodayStats(uid);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined),
              selectedIcon: Icon(Icons.shopping_cart_rounded),
              label: 'Cart',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final cartCount = CartManager.items.length;
    return RefreshIndicator(
      color: AppColors.primaryDark,
      onRefresh: () async {
        final uid = _userId;
        if (uid != null) await _loadTodayStats(uid);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 24, AppSpacing.page, 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 18),
          _buildStatsCard(),
          const SizedBox(height: 14),
          _buildStartSaleButton(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Cart',
                  caption: cartCount == 0
                      ? 'Empty'
                      : '$cartCount ${cartCount == 1 ? 'item' : 'items'} waiting',
                  onTap: () => setState(() => selectedIndex = 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  caption: 'Prices and stock',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProductsScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EndOfDayScreen())),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.point_of_sale_outlined, color: AppColors.primaryDark),
            label: const Text('End of day · close the drawer'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final statusColor = isActive ? AppColors.success : AppColors.muted;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, ${cashierName.isEmpty ? 'Cashier' : cashierName}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                storeName.isEmpty ? 'My Store' : storeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: AppTypography.title,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (widget.onSwitchToOwner != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tooltip(
                message: 'Switch to owner',
                child: FilledButton.icon(
                  onPressed: widget.onSwitchToOwner,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: const Text('Owner'),
                ),
              ),
              const SizedBox(height: 8),
              _buildDutyChip(statusColor),
            ],
          )
        else
          _buildDutyChip(statusColor),
      ],
    );
  }

  Widget _buildDutyChip(Color statusColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isActive ? 'Tap to go off duty' : 'Tap to go on duty',
          child: Material(
            color: isActive ? AppColors.successSoft : AppColors.soft,
            shape: StadiumBorder(
              side: BorderSide(color: isActive ? const Color(0xFFCFE8DA) : AppColors.border),
            ),
            child: InkWell(
              onTap: _toggleUserStatus,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isActive ? 'On duty' : 'Off duty',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    Widget stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.onHeroMuted,
            fontSize: AppTypography.caption + 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.onHero,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(24)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: stat('My sales today', 'BD ${todaySales.toStringAsFixed(3)}')),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.heroLine,
            ),
            stat('Transactions', '$todayTransactions'),
          ],
        ),
      ),
    );
  }

  /// The cashier's main action: a large indigo tile that opens the scanner.
  Widget _buildStartSaleButton() {
    final radius = BorderRadius.circular(22);
    return Material(
      color: AppColors.primaryDark,
      borderRadius: radius,
      child: InkWell(
        onTap: () => setState(() => selectedIndex = 1),
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start sale',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Scan a barcode to add items',
                      style: TextStyle(
                        color: Color(0xFFDCDAFB),
                        fontSize: AppTypography.caption + 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required String caption,
    required VoidCallback onTap,
  }) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 24),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: AppTypography.button,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
