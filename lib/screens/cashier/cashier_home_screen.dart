import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../services/sale_sync_service.dart';
import '../../services/sales_query.dart';
import '../../utils/cart_manager.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/receipt_card.dart';
import '../../widgets/sale_sync_panel.dart';
import '../cart/cart_screen.dart';
import '../closing/end_of_day_screen.dart';
import '../products/products_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/scan_screen.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';

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

  /// Today's latest receipts by this cashier, newest first (read from the same query).
  List<_RecentReceipt> recentReceipts = const [];
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
      final recent = <_RecentReceipt>[];
      for (final doc in salesDocs) {
        final data = doc.data();
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final saleDate = createdAt.toDate();
          if (!saleDate.isBefore(startOfDay) && saleDate.isBefore(endOfDay)) {
            final amount = ((data['total'] ?? 0) as num).toDouble();
            total += amount;
            count++;
            recent.add(
              _RecentReceipt(
                time: saleDate,
                total: amount,
                items: data['items'] is List ? (data['items'] as List).length : 0,
                method: (data['paymentMethod'] ?? 'Cash').toString(),
                refund: data['type'] == 'refund',
              ),
            );
          }
        }
      }
      recent.sort((a, b) => b.time.compareTo(a.time));

      if (!mounted) return;
      setState(() {
        todaySales = total;
        todayTransactions = count;
        recentReceipts = recent.take(3).toList();
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
          // Paid straight from the scanner: stay ready for the next customer.
          onSaleCompleted: () async {
            final uid = _userId;
            if (uid != null) await _loadTodayStats(uid);
          },
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

    // F2 starts a sale from anywhere in the cashier workspace (counter keyboards).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (selectedIndex != 1) setState(() => selectedIndex = 1);
        },
      },
      child: Focus(
        autofocus: true,
        child: AdaptiveNavScaffold(
          // Screens: 0 home, 1 scanner, 2 cart, 3 profile. The scanner opens from
          // "Start sale" and belongs to Home in the navigation.
          selectedIndex: switch (selectedIndex) {
            2 => 1,
            3 => 2,
            _ => 0,
          },
          onSelected: (tab) async {
            final index = const [0, 2, 3][tab];
            setState(() => selectedIndex = index);
            if (index == 0) {
              final uid = _userId;
              if (uid != null) await _loadTodayStats(uid);
            }
          },
          items: [
            (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'.tr),
            (
              icon: Icons.shopping_cart_outlined,
              selectedIcon: Icons.shopping_cart_rounded,
              label: 'Cart'.tr,
            ),
            (
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: 'Profile'.tr,
            ),
          ],
          body: Column(
            children: [
              const SaleSyncPanel(),
              Expanded(
                child: isLoading ? const Center(child: CircularProgressIndicator()) : currentScreen,
              ),
            ],
          ),
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
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _homeChildren(cartCount),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _homeChildren(int cartCount) {
    return [
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
              label: 'Cart'.tr,
              caption: cartCount == 0
                  ? 'Empty'.tr
                  : (cartCount == 1 ? '1 item waiting' : '{n} items waiting').trArgs({
                      'n': cartCount,
                    }),
              onTap: () => setState(() => selectedIndex = 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionTile(
              icon: Icons.inventory_2_outlined,
              label: 'Products'.tr,
              caption: 'Prices and stock'.tr,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.cardRadius)),
        ),
        icon: const Icon(Icons.point_of_sale_outlined, color: AppColors.primaryDark),
        label: Text('End of day · close the drawer'.tr),
      ),
      if (recentReceipts.isNotEmpty) ...[
        const SizedBox(height: 26),
        Text(
          'Latest receipts'.tr,
          style: const TextStyle(
            fontSize: AppTypography.section,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < recentReceipts.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _buildReceiptRow(recentReceipts[i]),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  /// One line per recent receipt: time and item count, payment method, amount.
  Widget _buildReceiptRow(_RecentReceipt receipt) {
    final time = TimeOfDay.fromDateTime(receipt.time).format(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            receipt.method == 'Cash' ? Icons.payments_outlined : Icons.qr_code_2_rounded,
            color: AppColors.muted,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              (receipt.items == 1 ? '{time} · 1 item' : '{time} · {n} items').trArgs({
                'time': time,
                'n': receipt.items,
              }),
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.body),
            ),
          ),
          Text(
            Money.format(receipt.total),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: AppTypography.button,
              color: receipt.refund ? AppColors.danger : AppColors.text,
            ),
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
                'Hi, {name}'.trArgs({'name': cashierName.isEmpty ? 'Cashier'.tr : cashierName}),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                storeName.isEmpty ? 'My Store'.tr : storeName,
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
                message: 'Switch to owner'.tr,
                child: FilledButton.icon(
                  onPressed: widget.onSwitchToOwner,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: Text('Owner'.tr),
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
          message: isActive ? 'Tap to go off duty'.tr : 'Tap to go on duty'.tr,
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
                      isActive ? 'On duty'.tr : 'Off duty'.tr,
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
            fontSize: AppTypography.body,
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
              fontSize: AppTypography.display,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ],
    );

    return ReceiptCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(child: stat('My sales today'.tr, Money.format(todaySales))),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.heroLine,
            ),
            stat('Transactions'.tr, '$todayTransactions'),
          ],
        ),
      ),
    );
  }

  /// The cashier's main action: a large indigo tile that opens the scanner.
  Widget _buildStartSaleButton() {
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
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
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start sale'.tr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: AppTypography.headline,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Scan a barcode to add items'.tr,
                      style: TextStyle(color: Color(0xFFDCDAFB), fontSize: AppTypography.body),
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
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
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

/// A receipt summary for the cashier home list.
class _RecentReceipt {
  const _RecentReceipt({
    required this.time,
    required this.total,
    required this.items,
    required this.method,
    required this.refund,
  });
  final DateTime time;
  final double total;
  final int items;
  final String method;
  final bool refund;
}
