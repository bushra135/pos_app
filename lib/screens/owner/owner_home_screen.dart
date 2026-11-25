import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'offers_screen.dart';
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
import '../../app/app_language.dart';
import '../../app/money.dart';
import '../../utils/receipt_audit.dart';
import '../../utils/today_summary.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/receipt_card.dart';

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

  /// For the first-run checklist: whether BenefitPay payments are set up.
  bool hasBenefitNumber = true;
  int activeCashierCount = 0;

  /// Today's receipts that look unusual (see ReceiptAudit), for the owner to check.
  int receiptsToReview = 0;

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
      final storeData = (await _firestore.collection('stores').doc(code).get(options)).data();
      final benefitReady = (storeData?['benefitNumber'] ?? '').toString().trim().isNotEmpty;
      // Count only users with the cashier role in this store.
      final cashiersSnapshot = await _firestore
          .collection('users')
          .where('storeCode', isEqualTo: code)
          .where('role', isEqualTo: 'cashier')
          .get(options);

      final totalCashiers = cashiersSnapshot.docs.length;
      // An invite the cashier has not accepted yet is not an active cashier.
      final activeCashiers = cashiersSnapshot.docs.where((doc) {
        final data = doc.data();
        return (data['isActive'] ?? false) == true && data['status'] != 'invited';
      }).length;

      final productsSnapshot = await _firestore
          .collection('products')
          .where('storeCode', isEqualTo: code)
          .get(options);

      int lowStock = 0;
      final total = productsSnapshot.docs.length;
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

        if (quantity <= minQty) lowStock++;
      }

      // Use the device's local day, excluding the start of tomorrow.
      final now = DateTime.now();
      final startOfYesterday = DateTime(now.year, now.month, now.day - 1);

      // Today and yesterday are all this screen needs.
      final salesDocs = await SalesQuery.since(
        _firestore,
        storeCode: code,
        from: startOfYesterday,
        options: options,
      );

      // Orders exclude refund receipts; the best seller comes from today's receipts
      // (after refunds), the same data the sales card uses.
      final today = TodaySummary.fromReceipts([
        for (final sale in salesDocs)
          if (sale.data()['createdAt'] is Timestamp)
            (date: (sale.data()['createdAt'] as Timestamp).toDate(), data: sale.data()),
      ], now);
      final prices = {
        for (final doc in productsSnapshot.docs)
          if (doc.data()['price'] is num) doc.id: (doc.data()['price'] as num).toDouble(),
      };
      final startOfToday = DateTime(now.year, now.month, now.day);
      final reviewCount = salesDocs.where((sale) {
        final created = sale.data()['createdAt'];
        if (created is! Timestamp || created.toDate().isBefore(startOfToday)) return false;
        return ReceiptAudit.issues(sale.data(), catalogPrices: prices).isNotEmpty;
      }).length;

      if (!mounted) return;

      setState(() {
        todaySales = today.sales;
        todayOrders = today.orders;
        yesterdaySales = today.yesterdaySales;
        lowStockCount = lowStock;
        bestSellerName = today.bestSeller;
        bestSellerSold = today.bestSellerUnits;
        totalProducts = total;
        cashierCount = totalCashiers;
        hasBenefitNumber = benefitReady;
        activeCashierCount = activeCashiers;
        stockCorrections = corrections;
        receiptsToReview = reviewCount;
      });
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
    }
  }

  void _copyStoreCode() {
    if (storeCode.isEmpty) return;

    Clipboard.setData(ClipboardData(text: storeCode));

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Store code copied'.tr)));
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

    return AdaptiveNavScaffold(
      selectedIndex: _selectedIndex,
      onSelected: (index) => setState(() => _selectedIndex = index),
      items: [
        (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'.tr),
        (
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2_rounded,
          label: 'Products'.tr,
        ),
        (
          icon: Icons.space_dashboard_outlined,
          selectedIcon: Icons.space_dashboard_rounded,
          label: 'Dashboard'.tr,
        ),
        (icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome, label: 'AI'.tr),
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
          // Urgent alerts first, then the first-run checklist.
          if (stockCorrections.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildCorrectionsAlert(),
          ],
          if (receiptsToReview > 0) ...[const SizedBox(height: 14), _buildReviewAlert()],
          if (totalProducts == 0 || cashierCount == 0 || !hasBenefitNumber) ...[
            const SizedBox(height: 14),
            _buildSetupChecklist(),
          ],
          const SizedBox(height: 26),
          Text(
            'Overview'.tr,
            style: TextStyle(
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          // Four separate cards with space between them.
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
                label: 'Low stock'.tr,
                value: '$lowStockCount',
                caption: lowStockCount == 1
                    ? 'item needs restocking'.tr
                    : 'items need restocking'.tr,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _OverviewTile(
                icon: Icons.inventory_2_outlined,
                color: AppColors.primaryDark,
                label: 'Products'.tr,
                value: '$totalProducts',
                caption: 'in your catalogue'.tr,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _OverviewTile(
                icon: Icons.local_fire_department_outlined,
                color: AppColors.danger,
                label: 'Best seller'.tr,
                value: bestSellerName.isEmpty ? 'No sales yet'.tr : bestSellerName,
                caption: bestSellerName.isEmpty
                    ? 'record a sale to see it'.tr
                    : '{n} sold today'.trArgs({'n': bestSellerSold}),
                smallValue: true,
                onTap: _openTopCashiers,
              ),
              _OverviewTile(
                icon: Icons.people_alt_outlined,
                color: AppColors.success,
                label: 'Cashiers'.tr,
                value: '$activeCashierCount/$cashierCount',
                caption: 'active right now'.tr,
                onTap: _openCashiersManagement,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The doctor's idea: help slow stock sell by pairing it with best sellers.
          Material(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OffersScreen(
                    firestore: widget.firestore,
                    currentUserId: widget.currentUserId,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.local_offer_outlined, color: AppColors.primaryDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offers & tips'.tr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            'Sell slow items with your best sellers'.tr,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openTopCashiers,
              icon: const Icon(Icons.emoji_events_outlined, size: 18),
              label: Text('Top cashiers'.tr),
            ),
          ),
        ],
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning'.tr;
    if (hour < 18) return 'Good afternoon'.tr;
    return 'Good evening'.tr;
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '{greeting}, {name}'.trArgs({
                  'greeting': _greeting,
                  'name': firstName.isEmpty ? 'Owner'.tr : firstName,
                }),
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
        Tooltip(
          message: 'Switch to cashier'.tr,
          child: FilledButton.icon(
            onPressed: isLoading ? null : _switchToCashier,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            label: Text('Cashier'.tr),
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
          SnackBar(content: Text('Could not update. Check your connection and try again.'.tr)),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewingCorrections = false);
    }
  }

  /// Owner alert: items sold although the records said they were out of stock.
  /// First-run steps for a new store; each opens the screen where it is done and the
  /// card disappears once all three are complete.
  Widget _buildSetupChecklist() {
    final steps = [
      (
        done: totalProducts > 0,
        icon: Icons.inventory_2_outlined,
        title: 'Add your first product',
        hint: 'Scan its barcode; the name and photo are filled in for you',
        open: () => setState(() => _selectedIndex = 1),
      ),
      (
        done: cashierCount > 0,
        icon: Icons.person_add_alt_1_outlined,
        title: 'Invite a cashier',
        hint: 'Share your store code or send an invite',
        open: _openCashiersManagement,
      ),
      (
        done: hasBenefitNumber,
        icon: Icons.qr_code_2_rounded,
        title: 'Set up BenefitPay',
        hint: 'Add your BenefitPay number and QR in Profile',
        open: () => setState(() => _selectedIndex = 4),
      ),
    ];
    final left = steps.where((step) => !step.done).length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get your store ready'.tr,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppTypography.subtitle),
          ),
          Text(
            (left == 1 ? '1 step left' : '{n} steps left').trArgs({'n': left}),
            style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
          ),
          const SizedBox(height: 4),
          for (final step in steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 52,
              onTap: step.done ? null : step.open,
              leading: Icon(
                step.done ? Icons.check_circle_rounded : step.icon,
                color: step.done ? AppColors.success : AppColors.primaryDark,
              ),
              title: Text(
                step.title.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: step.done ? TextDecoration.lineThrough : null,
                  color: step.done ? AppColors.muted : AppColors.text,
                ),
              ),
              subtitle: step.done
                  ? null
                  : Text(step.hint.tr, style: const TextStyle(fontSize: AppTypography.caption)),
              trailing: step.done ? null : const Icon(Icons.chevron_right_rounded),
            ),
        ],
      ),
    );
  }

  /// Today's receipts flagged for review, with a direct way to open them.
  Widget _buildReviewAlert() {
    return Material(
      color: AppColors.warningSoft,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SalesHistoryScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (receiptsToReview == 1
                          ? '1 receipt today needs a look'
                          : '{n} receipts today need a look')
                      .trArgs({'n': receiptsToReview}),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text),
                ),
              ),
              Text(
                'Open history'.tr,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: AppTypography.caption,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primaryDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorrectionsAlert() {
    final shown = stockCorrections.take(3).toList();
    final more = stockCorrections.length - shown.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
                      ? '1 stock count was corrected'.tr
                      : '{n} stock counts were corrected'.trArgs({'n': stockCorrections.length}),
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
                '{name}: records showed {recorded}, cashier sold {sold}'.trArgs({
                  'name': item.name,
                  'recorded': item.recorded,
                  'sold': item.sold,
                }),
                style: const TextStyle(color: AppColors.text, fontSize: AppTypography.body),
              ),
            ),
          if (more > 0)
            Text(
              '+{n} more'.trArgs({'n': more}),
              style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _reviewingCorrections ? null : _markCorrectionsReviewed,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A4E06)),
              child: Text('Mark as reviewed'.tr),
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
      change = '{change}% vs yesterday'.trArgs({
        'change': '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(0)}',
      });
      changeColor = percent >= 0 ? AppColors.success : AppColors.danger;
    } else {
      change = null;
      changeColor = AppColors.onHeroMuted;
    }

    return ReceiptCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Today's sales".tr,
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
                    borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
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
              Money.format(todaySales),
              style: const TextStyle(
                color: AppColors.onHero,
                fontSize: AppTypography.hero,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const ReceiptRule(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  todayOrders == 0
                      ? 'No orders yet today'.tr
                      : (todayOrders == 1 ? '1 order · avg BD {avg}' : '{n} orders · avg BD {avg}')
                            .trArgs({'n': todayOrders, 'avg': average.toStringAsFixed(3)}),
                  style: const TextStyle(
                    color: AppColors.onHeroMuted,
                    fontSize: AppTypography.body,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Copy store code for new cashiers'.tr,
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
                  // Says what the code is, so the owner knows to share it with cashiers.
                  label: Text(
                    storeCode.isEmpty
                        ? 'No code'.tr
                        : 'Store code {code}'.trArgs({'code': storeCode}),
                  ),
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
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
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
                        fontSize: AppTypography.body,
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
                  fontSize: smallValue ? AppTypography.headline : AppTypography.title,
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
