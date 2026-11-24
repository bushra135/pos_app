import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../services/sale_sync_service.dart';
import '../../services/sales_query.dart';
import '../../widgets/sale_sync_panel.dart';
import '../ai/ai_assistant_screen.dart';
import '../cashier/cashier_home_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_screen.dart';
import '../reports/sales_history_screen.dart';
import 'cashiers_management_screen.dart';

/// Hosts management pages; cashier mode changes the workspace, not stored permissions.
class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key, this.firestore, this.currentUserId});

  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  int _selectedIndex = 0;
  bool _cashierMode = false;

  FirebaseFirestore get _firestore => widget.firestore ?? FirebaseFirestore.instance;
  String? get _userId => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;

  String firstName = '';
  String storeName = '';
  String storeCode = '';
  bool isLoading = true;

  double todaySales = 0.0;
  int todayOrders = 0;
  double yesterdaySales = 0.0;
  int lowStockCount = 0;
  String bestSellerName = '';
  int bestSellerSold = 0;
  int totalProducts = 0;
  int cashierCount = 0;
  int activeCashierCount = 0;

  /// Products whose stock a cashier corrected while selling a miscounted item.
  List<({DocumentReference<Map<String, dynamic>> ref, String name, int recorded, int sold})>
  stockCorrections = const [];
  bool _reviewingCorrections = false;

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  Future<void> _loadOwnerData() async {
    try {
      final uid = _userId;

      if (uid == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final sync = SaleSyncService.maybeInstance;
      Map<String, dynamic> data;
      Map<String, dynamic> store = {};
      if (sync != null) {
        final cachedContext = await sync.loadContext(uid);
        data = Map<String, dynamic>.from(cachedContext['profile'] as Map);
        store = Map<String, dynamic>.from(cachedContext['store'] as Map);
      } else {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (!doc.exists) {
          if (!mounted) return;
          setState(() => isLoading = false);
          return;
        }
        data = doc.data()!;
      }

      final fullName = data['fullName'] ?? '';
      final ownerStoreCode = data['storeCode'] ?? '';

      if (!mounted) return;

      setState(() {
        firstName = fullName.isNotEmpty ? fullName.split(' ')[0] : '';
        storeName = store['storeName'] ?? data['storeName'] ?? '';
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
      final options = SaleSyncService.maybeInstance?.online == false
          ? const GetOptions(source: Source.cache)
          : const GetOptions();
      // Count only users with the cashier role in this store.
      final cashiersSnapshot = await _firestore
          .collection('users')
          .where('storeCode', isEqualTo: code)
          .where('role', isEqualTo: 'cashier')
          .get(options);

      final totalCashiers = cashiersSnapshot.docs.length;
      final activeCashiers = cashiersSnapshot.docs.where((doc) {
        final data = doc.data();
        return (data['isActive'] ?? false) == true;
      }).length;

      final productsSnapshot = await _firestore
          .collection('products')
          .where('storeCode', isEqualTo: code)
          .get(options);

      int lowStock = 0;
      final total = productsSnapshot.docs.length;
      String topProduct = '';
      int topSold = 0;
      final corrections =
          <({DocumentReference<Map<String, dynamic>> ref, String name, int recorded, int sold})>[];

      for (final doc in productsSnapshot.docs) {
        final data = doc.data();

        final correction = data['lastStockCorrection'];
        if (correction is Map && correction['reviewed'] != true) {
          int whole(Object? value) => value is num ? value.toInt() : 0;
          corrections.add((
            ref: doc.reference,
            name: (data['name'] ?? correction['name'] ?? 'Product').toString(),
            recorded: whole(correction['stockBefore']),
            sold: whole(correction['quantitySold']),
          ));
        }

        // Products are saved with `stock`/`minStock`; older records used `quantity`/`minQuantity`.
        final quantity = ((data['stock'] ?? data['quantity'] ?? 0) as num).toInt();
        final minQty = ((data['minStock'] ?? data['minQuantity'] ?? 5) as num).toInt();
        final sold = ((data['soldCount'] ?? 0) as num).toInt();

        if (quantity <= minQty) lowStock++;

        if (sold > topSold) {
          topSold = sold;
          topProduct = data['name'] ?? '';
        }
      }

      // Use the device's local day, excluding the start of tomorrow.
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final startOfYesterday = startOfDay.subtract(const Duration(days: 1));

      // Today and yesterday are all this screen needs.
      final salesDocs = await SalesQuery.since(
        _firestore,
        storeCode: code,
        from: startOfYesterday,
        options: options,
      );

      double totalSales = 0.0;
      int orders = 0;
      double yesterdayTotal = 0.0;

      for (final sale in salesDocs) {
        final data = sale.data();
        final createdAt = data['createdAt'];

        if (createdAt is Timestamp) {
          final date = createdAt.toDate();

          final amount = ((data['total'] ?? 0) as num).toDouble();
          if (!date.isBefore(startOfDay) && date.isBefore(endOfDay)) {
            totalSales += amount;
            orders++;
          } else if (!date.isBefore(startOfYesterday) && date.isBefore(startOfDay)) {
            yesterdayTotal += amount;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        todaySales = totalSales;
        todayOrders = orders;
        yesterdaySales = yesterdayTotal;
        lowStockCount = lowStock;
        bestSellerName = topProduct;
        bestSellerSold = topSold;
        totalProducts = total;
        cashierCount = totalCashiers;
        activeCashierCount = activeCashiers;
        stockCorrections = corrections;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }

  void _copyStoreCode() {
    if (storeCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: storeCode));

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store code copied')));
  }

  // Keep performance navigation alongside cashier management on the home card.
  void _openTopCashiers() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SalesHistoryScreen(showTopCashiers: true)));
  }

  Future<void> _openCashiersManagement() async {
    if (storeCode.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CashiersManagementScreen(storeCode: storeCode)),
    );

    await _loadDashboardData(storeCode);
  }

  // Mode changes presentation only; the authenticated owner role is immutable.
  void _switchToCashier() => setState(() => _cashierMode = true);

  void _switchToOwner() {
    setState(() => _cashierMode = false);
    _loadOwnerData();
  }

  @override
  Widget build(BuildContext context) {
    if (_cashierMode) {
      return CashierHomeScreen(
        onSwitchToOwner: _switchToOwner,
        firestore: widget.firestore,
        currentUserId: widget.currentUserId,
      );
    }
    final currentScreen = switch (_selectedIndex) {
      1 => const ProductsScreen(),
      2 => const ReportsScreen(),
      3 => const AiAssistantScreen(),
      4 => ProfileScreen(onSwitchMode: _switchToCashier),
      _ => _buildHomeContent(),
    };

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
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Products',
            ),
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome),
              label: 'AI',
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
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return RefreshIndicator(
      color: AppColors.primaryDark,
      onRefresh: () async {
        if (storeCode.isNotEmpty) await _loadDashboardData(storeCode);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 24, AppSpacing.page, 24),
        children: [
          _buildHeader(),
          const SizedBox(height: 18),
          _buildSalesCard(),
          if (stockCorrections.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildCorrectionsAlert(),
          ],
          const SizedBox(height: 26),
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: wide ? 4 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            // Taller tiles when the system text size is increased.
            childAspectRatio: 1.35 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _OverviewTile(
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                label: 'Low stock',
                value: '$lowStockCount',
                caption: lowStockCount == 1 ? 'item needs restocking' : 'items need restocking',
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _OverviewTile(
                icon: Icons.inventory_2_outlined,
                color: AppColors.primaryDark,
                label: 'Products',
                value: '$totalProducts',
                caption: 'in your catalogue',
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _OverviewTile(
                icon: Icons.local_fire_department_outlined,
                color: AppColors.danger,
                label: 'Best seller',
                value: bestSellerName.isEmpty ? 'No sales yet' : bestSellerName,
                caption: bestSellerName.isEmpty
                    ? 'record a sale to see it'
                    : '$bestSellerSold sold',
                smallValue: true,
                onTap: _openTopCashiers,
              ),
              _OverviewTile(
                icon: Icons.people_alt_outlined,
                color: AppColors.success,
                label: 'Cashiers',
                value: '$activeCashierCount/$cashierCount',
                caption: 'active right now',
                onTap: _openCashiersManagement,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openTopCashiers,
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: const Text('Top cashiers'),
            ),
          ),
        ],
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting, ${firstName.isEmpty ? 'Owner' : firstName}',
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
        Tooltip(
          message: 'Switch to cashier',
          child: FilledButton.icon(
            onPressed: isLoading ? null : _switchToCashier,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            label: const Text('Cashier'),
          ),
        ),
      ],
    );
  }

  /// Ink card with today's revenue, the change against yesterday and the store code.
  /// Marks every listed correction as seen; the audit record on each sale is unchanged.
  Future<void> _markCorrectionsReviewed() async {
    setState(() => _reviewingCorrections = true);
    try {
      final batch = _firestore.batch();
      for (final correction in stockCorrections) {
        batch.update(correction.ref, {'lastStockCorrection.reviewed': true});
      }
      await batch.commit();
      if (!mounted) return;
      setState(() => stockCorrections = const []);
    } catch (e) {
      debugPrint('Could not mark corrections reviewed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update. Check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewingCorrections = false);
    }
  }

  /// Owner alert: items sold although the records said they were out of stock.
  Widget _buildCorrectionsAlert() {
    final shown = stockCorrections.take(3).toList();
    final more = stockCorrections.length - shown.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3D9B4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stockCorrections.length == 1
                      ? '1 stock count was corrected'
                      : '${stockCorrections.length} stock counts were corrected',
                  style: const TextStyle(
                    color: Color(0xFF8A4E06),
                    fontWeight: FontWeight.w800,
                    fontSize: AppTypography.body,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${item.name}: records showed ${item.recorded}, cashier sold ${item.sold}',
                style: const TextStyle(color: AppColors.text, fontSize: AppTypography.caption + 1),
              ),
            ),
          if (more > 0)
            Text(
              '+$more more',
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _reviewingCorrections ? null : _markCorrectionsReviewed,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A4E06)),
              child: const Text('Mark as reviewed'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesCard() {
    final average = todayOrders == 0 ? 0.0 : todaySales / todayOrders;
    final String? change;
    final Color changeColor;
    if (yesterdaySales > 0) {
      final percent = (todaySales - yesterdaySales) / yesterdaySales * 100;
      change = '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(0)}% vs yesterday';
      changeColor = percent >= 0 ? AppColors.success : AppColors.danger;
    } else {
      change = null;
      changeColor = AppColors.onHeroMuted;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(color: AppColors.hero, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's sales",
                  style: TextStyle(
                    color: AppColors.onHeroMuted,
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    change,
                    style: TextStyle(
                      color: changeColor,
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'BD ${todaySales.toStringAsFixed(3)}',
              style: const TextStyle(
                color: AppColors.onHero,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  todayOrders == 0
                      ? 'No orders yet today'
                      : '$todayOrders ${todayOrders == 1 ? 'order' : 'orders'} · avg BD ${average.toStringAsFixed(3)}',
                  style: const TextStyle(
                    color: AppColors.onHeroMuted,
                    fontSize: AppTypography.caption + 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Copy store code for new cashiers',
                child: OutlinedButton.icon(
                  onPressed: storeCode.isEmpty ? null : _copyStoreCode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onHero,
                    side: const BorderSide(color: AppColors.heroLine),
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text(storeCode.isEmpty ? 'No code' : storeCode),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One white overview tile: coloured icon and label, a large value and a short caption.
class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
    this.onTap,
    this.smallValue = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String caption;
  final VoidCallback? onTap;

  /// Names are longer than numbers, so they use a slightly smaller size.
  final bool smallValue;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: AppTypography.caption + 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: smallValue ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
