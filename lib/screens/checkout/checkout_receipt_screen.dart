import 'dart:convert';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../models/sale_record.dart';
import '../../services/sale_sync_service.dart';
import '../../utils/active_offers.dart';
import '../../utils/cart_manager.dart';
import '../../utils/vat_invoice.dart';
import '../../widgets/motion.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/receipt_card.dart';
import '../../widgets/sale_receipt_view.dart';
import '../../app/app_language.dart';
import '../../app/money.dart';

/// Reviews the receipt, confirms payment, saves the sale, and updates stock.
class CheckoutReceiptScreen extends StatefulWidget {
  const CheckoutReceiptScreen({super.key, this.firestore, this.currentUserId});
  final FirebaseFirestore? firestore;
  final String? Function()? currentUserId;

  @override
  State<CheckoutReceiptScreen> createState() => _CheckoutReceiptScreenState();
}

class _CheckoutReceiptScreenState extends State<CheckoutReceiptScreen> {
  String? get _uid => widget.currentUserId != null
      ? widget.currentUserId!()
      : FirebaseAuth.instance.currentUser?.uid;
  String selectedPaymentMethod = 'Cash';

  /// Discount the cashier entered: a percent of the subtotal or a fixed BD amount.
  double _discountValue = 0;
  bool _discountIsPercent = true;

  static double _fils(double value) => (value * 1000).roundToDouble() / 1000;
  double get _subtotal => _fils(CartManager.total);

  /// The cashier's own discount (percent of the subtotal or a fixed amount).
  double get _manualDiscountAmount {
    final raw = _discountIsPercent ? _subtotal * _discountValue / 100 : _discountValue;
    return _fils(raw.clamp(0, _subtotal).toDouble());
  }

  /// Bundle offers the owner switched on; applied automatically to complete pairs.
  List<ActiveOffer> _offers = const [];
  List<AppliedOffer> get _appliedOffers => OfferMath.apply([
    for (final item in CartManager.items)
      (productId: item.productId, price: item.price, quantity: item.quantity),
  ], _offers);
  double get _offerAmount => OfferMath.total(_appliedOffers);

  /// Everything taken off the subtotal: bundle offers plus the cashier's discount.
  double get _discountAmount =>
      _fils((_offerAmount + _manualDiscountAmount).clamp(0, _subtotal).toDouble());

  double get _total => _fils(_subtotal - _discountAmount);

  /// Cash the customer handed over (optional); used only to show the change.
  final _cashController = TextEditingController();
  double? get _cashReceived {
    final value = double.tryParse(_cashController.text.trim());
    return value == null ? null : _fils(value);
  }

  bool get _cashShort =>
      selectedPaymentMethod == 'Cash' && _cashReceived != null && _cashReceived! < _total;

  /// Note values a customer is likely to hand over for this total, smallest first.
  List<double> get _quickCash {
    final total = _total;
    final options = <double>{};
    for (final step in const [1.0, 5.0, 10.0, 20.0]) {
      final rounded = (total / step).ceil() * step;
      if (rounded > total) options.add(rounded);
    }
    return options.take(3).toList()..sort();
  }

  void _setCash(double amount) {
    setState(() => _cashController.text = amount.toStringAsFixed(3));
  }

  /// The store's VAT status; a store that is not registered collects no VAT.
  StoreVat _storeVat = StoreVat.fromStore(null);

  /// VAT contained in the VAT-inclusive total (0 when the store is not registered).
  double get _vat {
    final rate = _storeVat.rate;
    return rate <= 0 ? 0 : _fils(_total * rate / (100 + rate));
  }

  /// Customer details for a full tax invoice (registered stores, when asked for).
  ({String name, String address, String vatNumber})? _buyer;

  /// Taken once per checkout, so a retry never skips a number.
  String? _invoiceNumber;

  Future<void> _editBuyer() async {
    final result = await showDialog<({String name, String address, String vatNumber})>(
      context: context,
      builder: (_) => _BuyerDialog(initial: _buyer, total: _total),
    );
    if (result == null || !mounted) return;
    setState(() => _buyer = result.name.isEmpty ? null : result);
  }

  Future<void> _editDiscount() async {
    final result = await showDialog<({double value, bool percent})>(
      context: context,
      builder: (_) => _DiscountDialog(
        subtotal: _subtotal,
        initialValue: _discountValue,
        initialPercent: _discountIsPercent,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _discountValue = result.value;
      _discountIsPercent = result.percent;
    });
  }

  String storeName = '';
  String cashierName = '';
  String benefitNumber = '';
  String benefitQrBase64 = '';
  String storeCode = '';

  bool isLoading = true;
  bool isSavingSale = false;
  SaleRecord? completedSale;
  SaleSyncService? _receiptSync;
  String completedStatus = '';

  final AudioPlayer _successPlayer = AudioPlayer();
  late final String _saleId;
  late final DateTime _saleTime;

  @override
  void initState() {
    super.initState();
    _saleId = (widget.firestore ?? FirebaseFirestore.instance).collection('sales').doc().id;
    _saleTime = DateTime.now();
    _receiptSync = SaleSyncService.maybeInstance;
    _receiptSync?.addListener(_refreshReceiptSync);
    _successPlayer.setReleaseMode(ReleaseMode.stop);
    _loadStorePaymentData();
  }

  @override
  void dispose() {
    _receiptSync?.removeListener(_refreshReceiptSync);
    _successPlayer.dispose();
    _cashController.dispose();
    super.dispose();
  }

  void _refreshReceiptSync() {
    final sale = completedSale;
    final sync = _receiptSync;
    if (!mounted || sale == null || sync == null || _uid != sale.cashierUid) {
      return;
    }
    final rows = sync.pendingSales.where((row) => row.sale.id == sale.id);
    final next = rows.isEmpty && sync.online
        ? 'Synchronized'.tr
        : rows.isNotEmpty && rows.first.isConflict
        ? 'Saved on device — stock needs review'.tr
        : null;
    if (next != null && next != completedStatus) {
      setState(() => completedStatus = next);
    }
  }

  Future<void> _playPaymentSuccessSound() async {
    try {
      await HapticFeedback.lightImpact();
      await _successPlayer.stop();
      await _successPlayer.play(AssetSource('sounds/payment_success.mp3'), volume: 1);
    } catch (e) {
      // Audio failure must not undo a successfully saved sale.
      debugPrint('Error playing payment success sound: $e');
    }
  }

  // Load store payment settings and cashier context.
  Future<void> _loadStorePaymentData() async {
    try {
      final uid = _uid;

      if (uid == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final sync = SaleSyncService.maybeInstance;
      if (sync == null) throw StateError('The sales service is not ready.');
      final contextData = await sync.loadContext(uid);
      final userData = Map<String, dynamic>.from(contextData['profile'] as Map);
      final String fullName = (userData['fullName'] ?? '').toString();
      final String firstName = fullName.split(' ').first;
      final String fetchedStoreCode = (userData['storeCode'] ?? '').toString().trim();

      final storeData = Map<String, dynamic>.from(contextData['store'] as Map);
      final fetchedStoreName = (storeData['storeName'] ?? userData['storeName'] ?? '').toString();
      final fetchedBenefitNumber = (storeData['benefitNumber'] ?? '').toString();
      final fetchedBenefitQrBase64 = (storeData['benefitQrBase64'] ?? '').toString();
      final storeVat = StoreVat.fromStore(storeData);
      // Offers come from the offline catalogue; without them the sale simply has none.
      var offers = const <ActiveOffer>[];
      try {
        offers = await sync.activeOffers();
      } catch (e) {
        debugPrint('Offers not loaded: $e');
      }

      if (!mounted) return;

      setState(() {
        cashierName = firstName;
        storeName = fetchedStoreName;
        storeCode = fetchedStoreCode;
        benefitNumber = fetchedBenefitNumber;
        benefitQrBase64 = fetchedBenefitQrBase64;
        _storeVat = storeVat;
        _offers = offers;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading payment data: $e');

      if (!mounted) return;

      setState(() => isLoading = false);
    }
  }

  String get receiptNumber => 'RCPT-$_saleId';

  /// Short form for the screen; the last six characters are enough to find it.
  String get _shortReceiptNumber {
    final id = _saleId.toUpperCase();
    return '#${id.length > 6 ? id.substring(id.length - 6) : id}';
  }

  // Create one stable receipt and submit it once.
  Future<void> _confirmPayment() async {
    if (isSavingSale || completedSale != null) return;
    if (CartManager.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cart is empty'.tr)));
      return;
    }

    if (storeCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Store code not found'.tr)));
      return;
    }

    setState(() {
      isSavingSale = true;
    });

    try {
      final uid = _uid;
      final sync = SaleSyncService.maybeInstance;
      if (uid == null || sync == null) {
        throw StateError('Sign in before checkout.');
      }
      final items = <SaleLine>[];
      for (final item in CartManager.items) {
        if (item.productId.isEmpty || item.storeCode != storeCode) {
          throw StateError('Remove this cart item and scan it again for your store.');
        }
        items.add(
          SaleLine(
            productId: item.productId,
            barcode: item.barcode,
            name: item.name,
            price: item.price,
            quantity: item.quantity,
            cost: item.cost,
          ),
        );
      }
      // The counter lives on this device; if its storage is unavailable the sale still
      // goes through, numbered from its own id instead of the sequence.
      _invoiceNumber ??= await SharedPreferences.getInstance()
          .then((prefs) => InvoiceNumbers(prefs).next(storeCode))
          .timeout(const Duration(seconds: 3))
          .catchError((Object e) {
            debugPrint('Invoice counter unavailable: $e');
            return 'INV-${_shortReceiptNumber.substring(1)}';
          });
      final buyer = _storeVat.issuesTaxInvoices ? _buyer : null;
      final sale = SaleRecord(
        id: _saleId,
        storeCode: storeCode,
        storeName: storeName,
        cashierUid: uid,
        cashierName: cashierName,
        paymentMethod: selectedPaymentMethod,
        createdAt: _saleTime,
        items: items,
        correctStockShortages: true,
        discount: _discountAmount,
        vatRate: _storeVat.rate,
        invoiceNumber: _invoiceNumber!,
        invoiceKind: InvoiceKind.forSale(vat: _storeVat, buyerDetails: buyer != null),
        storeVatNumber: _storeVat.issuesTaxInvoices ? _storeVat.number : '',
        storeAddress: _storeVat.address,
        buyerName: buyer?.name ?? '',
        buyerAddress: buyer?.address ?? '',
        buyerVatNumber: buyer?.vatNumber ?? '',
        offerDiscount: _offerAmount.clamp(0, _discountAmount).toDouble(),
        offerNames: [
          for (final applied in _appliedOffers)
            '${applied.offer.anchorName} + ${applied.offer.slowName} ${applied.offer.percent}%',
        ],
      );
      final result = await sync.submit(sale);

      // Queued and conflicted receipts are already durably saved on this device.
      CartManager.clearCart();

      if (!mounted) return;
      // The durable receipt is ready; neither audio nor an informational dialog
      // should leave the payment button spinning or allow a second submission.
      setState(() {
        isSavingSale = false;
        completedSale = sale;
        completedStatus = result.status == SaleSubmissionStatus.synced
            ? 'Synchronized'.tr
            : result.status == SaleSubmissionStatus.conflict
            ? 'Saved on device — stock needs review'.tr
            : 'Saved on device — synchronization pending'.tr;
      });
      _refreshReceiptSync();
      unawaited(_playPaymentSuccessSound());

      if (result.status == SaleSubmissionStatus.synced) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sale confirmed and stock updated'.tr)));
      } else {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(
              result.status == SaleSubmissionStatus.conflict
                  ? 'Receipt needs review'.tr
                  : 'Receipt saved — sync pending'.tr,
            ),
            content: Text(
              '$receiptNumber\n\n${(result.message ?? 'Stock and reports will update when this receipt is confirmed online.').tr}\n\n'
              '${'No need to submit this sale again. It will retry automatically. Keep this browser data until synchronization completes; check Sales status for progress.'.tr}',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'.tr))],
          ),
        );
      }
    } catch (e) {
      // Details go to the debug log only; the cashier sees a friendly message.
      debugPrint('Sale save failed: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_saleErrorMessage(e))));

      setState(() {
        isSavingSale = false;
      });
    }
  }

  /// Checkout's own instructions (sign in, rescan, out of stock) are shown as written;
  /// any other error gets a generic message so internal details never reach the screen.
  static const _checkoutInstructions = {
    'Sign in before checkout.',
    'Remove this cart item and scan it again for your store.',
  };

  static String _saleErrorMessage(Object error) {
    if (error is OutOfStockException) {
      return 'No available stock for {name}.'.trArgs({'name': error.productName});
    }
    if (error is StateError && _checkoutInstructions.contains(error.message)) {
      return error.message.tr;
    }
    return 'Could not save the sale. Check your connection and try again.'.tr;
  }

  // Payment and receipt presentation.
  Widget _buildPaymentOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: isSavingSale ? null : onTap,
        child: Container(
          height: 74,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isSelected ? AppColors.primaryDark : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? AppColors.onBrand : AppColors.muted),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTypography.label,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.onBrand : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptItem({
    required String name,
    required int quantity,
    required double subtotal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text('x$quantity', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          Text(Money.format(subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Cash received and change, so the cashier never works the change out by hand.
  Widget _buildCashPanel() {
    final received = _cashReceived;
    final change = received == null ? null : _fils(received - _total);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A heading above the field, so the amount never sits on top of a label.
          Text(
            'Cash received (optional)'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cashController,
            enabled: !isSavingSale,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (!isSavingSale && !_cashShort) _confirmPayment();
            },
            decoration: InputDecoration(
              hintText: '0.000',
              suffixText: Money.symbol,
              filled: true,
              fillColor: AppColors.surface,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: Text('Exact amount'.tr),
                onPressed: isSavingSale ? null : () => _setCash(_total),
              ),
              for (final amount in _quickCash)
                ActionChip(
                  label: Text(Money.format(amount)),
                  onPressed: isSavingSale ? null : () => _setCash(amount),
                ),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    change >= 0
                        ? 'Change'.tr
                        : 'Short by {amount}'.trArgs({'amount': Money.format(-change)}),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: change >= 0 ? AppColors.text : AppColors.danger,
                    ),
                  ),
                ),
                if (change >= 0)
                  Text(
                    Money.format(change),
                    style: const TextStyle(
                      fontSize: AppTypography.metric,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Payment beside the receipt on wide screens; one column, at a readable width, on phones.
  /// The amount to take, large and first: what the cashier says to the customer.
  Widget _buildTotalHero() {
    final units = CartManager.items.fold<int>(0, (n, item) => n + item.quantity);
    final details = [
      (units == 1 ? '1 item' : '{n} items').trArgs({'n': units}),
      if (_storeVat.rate > 0)
        'VAT {rate}% included: {amount}'.trArgs({
          'rate': _storeVat.rate.toStringAsFixed(0),
          'amount': Money.format(_vat),
        }),
      if (_discountAmount > 0) 'Saved {amount}'.trArgs({'amount': Money.format(_discountAmount)}),
    ];
    return FadeSlideIn(
      child: ReceiptCard(
        gradient: AppColors.heroGradient,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total to pay'.tr,
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
              child: CountUpText(
                value: _total,
                format: Money.format,
                style: const TextStyle(
                  color: AppColors.onHero,
                  fontSize: AppTypography.hero + 6,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const ReceiptRule(),
            const SizedBox(height: 8),
            Text(
              details.join('  ·  '),
              style: const TextStyle(color: AppColors.onHeroMuted, fontSize: AppTypography.caption),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkoutBody({required Widget payment, required Widget receipt}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AdaptiveNavScaffold.railBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [_buildTotalHero(), const SizedBox(height: 16), payment],
                ),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(16), children: [receipt]),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTotalHero(),
                  const SizedBox(height: 16),
                  payment,
                  const SizedBox(height: 16),
                  receipt,
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQrPlaceholder() {
    return Container(
      height: 180,
      width: 180,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: const Icon(Icons.qr_code, size: 70, color: AppColors.muted),
    );
  }

  Widget _buildQrPreview() {
    if (benefitQrBase64.isEmpty) return _buildQrPlaceholder();

    try {
      final Uint8List bytes = base64Decode(benefitQrBase64);

      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        child: Image.memory(
          bytes,
          height: 180,
          width: 180,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildQrPlaceholder();
          },
        ),
      );
    } catch (_) {
      // Show a placeholder when the stored Base64 data is invalid.
      return _buildQrPlaceholder();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (completedSale != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SaleReceiptView(
          sale: completedSale!,
          status: completedStatus,
          onNewSale: () => Navigator.pop(context, true),
        ),
      );
    }
    final cartItems = CartManager.items;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!isSavingSale && !isLoading && !_cashShort) _confirmPayment();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!isSavingSale) Navigator.maybePop(context);
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: !isSavingSale,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          decoration: const BoxDecoration(color: AppColors.background),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppColors.surface,
                                child: IconButton(
                                  onPressed: isSavingSale ? null : () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back, color: AppColors.text),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Payment and receipt'.tr,
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: AppTypography.metric,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Review payment and invoice details'.tr,
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: AppTypography.body,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _checkoutBody(
                            payment: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Payment method'.tr,
                                    style: TextStyle(
                                      fontSize: AppTypography.section,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _buildPaymentOption(
                                        title: 'Cash'.tr,
                                        icon: Icons.payments_outlined,
                                        isSelected: selectedPaymentMethod == 'Cash',
                                        onTap: () {
                                          setState(() {
                                            selectedPaymentMethod = 'Cash';
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      _buildPaymentOption(
                                        title: 'BenefitPay',
                                        icon: Icons.qr_code,
                                        isSelected: selectedPaymentMethod == 'BenefitPay',
                                        onTap: () {
                                          setState(() {
                                            selectedPaymentMethod = 'BenefitPay';
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(
                                    onPressed: isSavingSale ? null : _editDiscount,
                                    icon: Icon(
                                      _manualDiscountAmount > 0
                                          ? Icons.edit_outlined
                                          : Icons.local_offer_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _manualDiscountAmount > 0
                                          ? (_discountIsPercent
                                                ? 'Discount {value}% · Edit'.trArgs({
                                                    'value': _discountValue.toStringAsFixed(
                                                      _discountValue % 1 == 0 ? 0 : 1,
                                                    ),
                                                  })
                                                : 'Discount BD {amount} · Edit'.trArgs({
                                                    'amount': _manualDiscountAmount.toStringAsFixed(
                                                      3,
                                                    ),
                                                  }))
                                          : 'Add discount'.tr,
                                    ),
                                  ),
                                  if (_storeVat.issuesTaxInvoices) ...[
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: isSavingSale ? null : _editBuyer,
                                      icon: Icon(
                                        _buyer == null
                                            ? Icons.receipt_long_outlined
                                            : Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _buyer == null
                                            ? 'Full tax invoice for the customer'.tr
                                            : 'Tax invoice: {name} · Edit'.trArgs({
                                                'name': _buyer!.name,
                                              }),
                                      ),
                                    ),
                                  ],
                                  if (selectedPaymentMethod == 'Cash') ...[
                                    const SizedBox(height: 14),
                                    _buildCashPanel(),
                                  ],
                                  if (selectedPaymentMethod == 'BenefitPay') ...[
                                    const SizedBox(height: 18),
                                    if (benefitNumber.isNotEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.controlRadius,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'BenefitPay Number'.tr,
                                              style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: AppTypography.body,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              benefitNumber,
                                              style: const TextStyle(
                                                fontSize: AppTypography.section,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (benefitQrBase64.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.controlRadius,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'Scan to pay'.tr,
                                              style: TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 12),
                                            _buildQrPreview(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            receipt: ReceiptCard(
                              color: AppColors.surface,
                              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Receipt'.tr,
                                    style: TextStyle(
                                      fontSize: AppTypography.section,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Store'.tr,
                                          style: TextStyle(color: AppColors.muted),
                                        ),
                                      ),
                                      Text(
                                        storeName.isEmpty ? 'My Store'.tr : storeName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Cashier'.tr,
                                          style: TextStyle(color: AppColors.muted),
                                        ),
                                      ),
                                      Text(
                                        cashierName.isEmpty ? 'Cashier'.tr : cashierName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Receipt No.'.tr,
                                          style: TextStyle(color: AppColors.muted),
                                        ),
                                      ),
                                      Text(
                                        // The full number stays on the saved receipt and PDF.
                                        _shortReceiptNumber,
                                        // A code reads left to right in both languages.
                                        textDirection: TextDirection.ltr,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const ReceiptRule(color: AppColors.border),
                                  const SizedBox(height: 14),
                                  ...cartItems.map(
                                    (item) => _buildReceiptItem(
                                      name: item.name,
                                      quantity: item.quantity,
                                      subtotal: item.totalPrice,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const ReceiptRule(color: AppColors.border),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Subtotal'.tr,
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        Money.format(_subtotal),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  for (final applied in _appliedOffers) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_offer_rounded,
                                          size: 16,
                                          color: AppColors.success,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Offer: {slow} {percent}% off with {anchor}'.trArgs({
                                              'slow': applied.offer.slowName,
                                              'percent': applied.offer.percent,
                                              'anchor': applied.offer.anchorName,
                                            }),
                                            style: const TextStyle(
                                              color: AppColors.success,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '− ${Money.format(applied.amount)}',
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Discount'.tr,
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _manualDiscountAmount > 0
                                            ? '− ${Money.format(_manualDiscountAmount)}'
                                            : Money.format(0),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _manualDiscountAmount > 0
                                              ? AppColors.success
                                              : AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_storeVat.rate > 0) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Long in Arabic: wraps instead of pushing the amount off screen.
                                        Expanded(
                                          child: Text(
                                            'VAT {rate}% (included)'.trArgs({
                                              'rate': _storeVat.rate.toStringAsFixed(0),
                                            }),
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          Money.format(_vat),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  const ReceiptRule(color: AppColors.border),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Total'.tr,
                                          style: TextStyle(
                                            fontSize: AppTypography.section,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        Money.format(_total),
                                        style: const TextStyle(
                                          fontSize: AppTypography.display,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Pinned so the cashier never scrolls to find it.
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            border: Border(top: BorderSide(color: AppColors.border)),
                          ),
                          child: ContentWidth(
                            maxWidth: 720,
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isSavingSale || _cashShort ? null : _confirmPayment,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                                child: isSavingSale
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: AppColors.onBrand,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        selectedPaymentMethod == 'Cash'
                                            ? 'Confirm cash payment'.tr
                                            : 'Payment received'.tr,
                                        style: const TextStyle(
                                          color: AppColors.onBrand,
                                          fontWeight: FontWeight.w700,
                                          fontSize: AppTypography.button,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the cashier enter a discount as a percent or a BD amount, or remove it.
class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({
    required this.subtotal,
    required this.initialValue,
    required this.initialPercent,
  });

  final double subtotal;
  final double initialValue;
  final bool initialPercent;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late bool _percent = widget.initialPercent;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue > 0 ? _trim(widget.initialValue) : '',
  );

  static String _trim(double value) => value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _value => double.tryParse(_controller.text.trim()) ?? 0;

  String? get _error {
    if (_controller.text.trim().isEmpty) return null;
    final value = _value;
    if (value <= 0) return 'Enter a value above 0.'.tr;
    if (_percent && value > 100) return 'A percent discount cannot exceed 100%.'.tr;
    if (!_percent && value > widget.subtotal) {
      return 'Cannot exceed the subtotal of BD {amount}.'.trArgs({
        'amount': widget.subtotal.toStringAsFixed(3),
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final valid = value > 0 && _error == null;
    final amount = valid ? (_percent ? widget.subtotal * value / 100 : value) : 0.0;
    return AlertDialog(
      title: Text('Discount'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: true, label: Text('%')),
                ButtonSegment(value: false, label: Text(Money.symbol)),
              ],
              selected: {_percent},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _percent = selection.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _percent ? 'Discount percent'.tr : 'Discount amount (BD)'.tr,
                suffixText: _percent ? '%' : Money.symbol,
                errorText: _error,
              ),
            ),
            if (valid) ...[
              const SizedBox(height: 10),
              Text(
                'Customer pays BD {amount}'.trArgs({
                  'amount': (widget.subtotal - amount).toStringAsFixed(3),
                }),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.initialValue > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, (value: 0.0, percent: _percent)),
            child: Text('Remove'.tr, style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, (value: value, percent: _percent)) : null,
          child: Text('Apply'.tr),
        ),
      ],
    );
  }
}

/// Customer details for a full tax invoice (NBR): name and address, plus the
/// customer's VAT account number when they are VAT-registered.
class _BuyerDialog extends StatefulWidget {
  const _BuyerDialog({required this.initial, required this.total});

  final ({String name, String address, String vatNumber})? initial;
  final double total;

  @override
  State<_BuyerDialog> createState() => _BuyerDialogState();
}

class _BuyerDialogState extends State<_BuyerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _vat = TextEditingController(text: widget.initial?.vatNumber ?? '');

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _vat.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (
      name: _name.text.trim(),
      address: _address.text.trim(),
      vatNumber: VatChecks.digits(_vat.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Full tax invoice'.tr),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                (widget.total > InvoiceKind.simplifiedLimit
                        ? 'Above BD 500 a VAT-registered customer needs a full tax invoice.'
                        : 'For customers who ask for a tax invoice with their details.')
                    .tr,
                style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Customer name'.tr),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the customer name'.tr : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                decoration: InputDecoration(labelText: 'Customer address'.tr),
                validator: (v) => VatChecks.address(v ?? '', required: true)?.tr,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vat,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Customer VAT number (if registered)'.tr),
                validator: (v) => VatChecks.vatNumber(v ?? '', required: false)?.tr,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (name: '', address: '', vatNumber: '')),
            child: Text('Remove'.tr),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
        FilledButton(onPressed: _save, child: Text('Save'.tr)),
      ],
    );
  }
}
