import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/sale_record.dart';
import '../utils/cart_manager.dart';
import 'local_pos_store.dart';
import 'sale_gateway.dart';

enum SaleSubmissionStatus { synced, queued, conflict }

class SaleSubmission {
  const SaleSubmission(this.status, [this.message]);
  final SaleSubmissionStatus status;
  final String? message;
}

/// Durably records accepted payments before sending them to the server.
/// A retry always uses the same receipt, including after a lost acknowledgement.
class SaleSyncService extends ChangeNotifier {
  SaleSyncService({
    required this.store,
    required this.gateway,
    required this.currentUserId,
    FirebaseFirestore? firestore,
    this.requestTimeout = const Duration(seconds: 4),
  }) : _firestore = firestore;

  static SaleSyncService? maybeInstance;
  final LocalPosStore store;
  final SaleGateway gateway;
  final String? Function() currentUserId;
  final FirebaseFirestore? _firestore;
  final Duration requestTimeout;
  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;

  List<PendingSale> _pending = [];
  List<PendingSale> get pendingSales => List.unmodifiable(_pending);
  bool syncing = false;
  bool online = false;
  bool offlineMode = false;
  String? lastError;
  String? _uid;
  String? _storeCode;
  StreamSubscription<List<PendingSale>>? _queueSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _productSubscription;
  Timer? _timer;
  Future<void>? _syncFuture;
  Future<void> _submissionTail = Future<void>.value();
  bool _disposed = false;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(synchronize());
    });
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void clearSession() {
    _uid = null;
    _storeCode = null;
    _pending = [];
    online = false;
    _queueSubscription?.cancel();
    _productSubscription?.cancel();
    _queueSubscription = null;
    _productSubscription = null;
    CartManager.clearCart();
    _changed();
  }

  Future<void> bind(String uid, String storeCode) async {
    if (_uid == uid && _storeCode == storeCode) return;
    await _queueSubscription?.cancel();
    await _productSubscription?.cancel();
    if (_uid != uid || _storeCode != storeCode) CartManager.clearCart();
    _uid = uid;
    _storeCode = storeCode;
    _pending = await store.pendingSales(uid, storeCode);
    _queueSubscription = store
        .watchSales(uid, storeCode)
        .listen(
          (rows) {
            if (_uid != uid || _storeCode != storeCode) return;
            _pending = rows;
            _changed();
          },
          onError: (Object error) {
            lastError = 'Could not read saved sales: $error';
            _changed();
          },
        );
    _productSubscription = firestore
        .collection('products')
        .where('storeCode', isEqualTo: storeCode)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) async {
            if (_uid != uid || _storeCode != storeCode) return;
            online = !offlineMode && !snapshot.metadata.isFromCache;
            // An empty cache event at startup must not erase the durable catalogue.
            if (!snapshot.metadata.isFromCache || snapshot.docs.isNotEmpty) {
              try {
                await store.cacheProducts(
                  storeCode,
                  snapshot.docs
                      .map((doc) => {...doc.data(), 'id': doc.id})
                      .toList(),
                );
              } catch (error) {
                lastError = 'Could not save the offline catalogue: $error';
              }
            }
            _changed();
          },
          onError: (Object error) {
            online = false;
            lastError = 'Could not refresh products: $error';
            _changed();
          },
        );
    _changed();
    unawaited(synchronize());
  }

  Future<Map<String, dynamic>> loadContext(String uid) async {
    Map<String, dynamic>? cached;
    try {
      if (offlineMode) throw TimeoutException('Offline mode');
      final profileDoc = await firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(requestTimeout);
      final profile = profileDoc.data();
      if (profile == null) {
        throw StateError('Your store account was not found.');
      }
      final code = (profile['storeCode'] ?? '').toString().trim();
      if (code.isEmpty) throw StateError('Store code not found.');
      final storeDoc = await firestore
          .collection('stores')
          .doc(code)
          .get(const GetOptions(source: Source.server))
          .timeout(requestTimeout);
      await store.saveContext(uid, profile, storeDoc.data() ?? {});
      online = true;
      lastError = null;
      cached = await store.contextFor(uid);
    } on TimeoutException {
      online = false;
      cached = await store.contextFor(uid);
    } on FirebaseException catch (error) {
      if (!_temporary(error)) rethrow;
      online = false;
      cached = await store.contextFor(uid);
    }
    if (cached == null) {
      throw StateError(
        'Connect once to prepare this account for offline sales.',
      );
    }
    if (currentUserId() != uid) throw StateError('Your account has changed.');
    final profile = Map<String, dynamic>.from(cached['profile'] as Map);
    if (profile['isActive'] == false || profile['status'] == 'disabled') {
      throw StateError('This cashier account is disabled.');
    }
    await bind(uid, profile['storeCode'].toString());
    return cached;
  }

  /// Camera checkout can use the live local catalogue without a network round trip.
  /// Server submission still validates stock; a cache miss uses the server path.
  Future<Map<String, dynamic>> findProduct(
    String barcode, {
    bool preferCache = false,
  }) async {
    final uid = currentUserId();
    if (uid == null) throw StateError('Sign in before scanning products.');
    final context = await store.contextFor(uid) ?? await loadContext(uid);
    final profile = Map<String, dynamic>.from(context['profile'] as Map);
    final code = profile['storeCode'].toString();
    Map<String, dynamic>? product = preferCache
        ? await store.productByBarcode(code, barcode)
        : null;
    if (product == null && online && !offlineMode) {
      try {
        final result = await firestore
            .collection('products')
            .where('storeCode', isEqualTo: code)
            .where('barcode', isEqualTo: barcode)
            .limit(2)
            .get(const GetOptions(source: Source.server))
            .timeout(requestTimeout);
        if (result.docs.length > 1) {
          throw StateError('Multiple products in this store use this barcode.');
        }
        if (result.docs.isNotEmpty) {
          product = {...result.docs.single.data(), 'id': result.docs.single.id};
        } else {
          throw StateError('Product not found in your store: $barcode');
        }
      } on TimeoutException {
        online = false;
      } on FirebaseException catch (error) {
        if (!_temporary(error)) rethrow;
        online = false;
      }
    }
    product ??= await store.productByBarcode(code, barcode);
    if (product == null) {
      throw StateError(
        'This product is not available in the offline catalogue.',
      );
    }
    final stock = _stock(product);
    final reserved = await store.reservedQuantity(
      uid,
      code,
      product['id'] as String,
    );
    final inCart = CartManager.items
        .where((item) => item.productId == product!['id'])
        .fold<int>(0, (totalQuantity, item) => totalQuantity + item.quantity);
    if (stock - reserved - inCart < 1) {
      throw StateError('No available stock for ${product['name']}.');
    }
    _changed();
    return product;
  }

  Future<SaleSubmission> submit(SaleRecord sale) {
    final result = _submissionTail.then((_) => _submit(sale));
    _submissionTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<SaleSubmission> _submit(SaleRecord sale) async {
    if (sale.cashierUid != currentUserId() ||
        sale.cashierUid != _uid ||
        sale.storeCode != _storeCode) {
      throw StateError('The cart belongs to a different account or store.');
    }
    if ((!online || offlineMode) && sale.paymentMethod != 'Cash') {
      throw StateError(
        'Offline checkout supports cash only. Reconnect for BenefitPay.',
      );
    }
    await store.enqueueChecked(sale);
    // Only a successful durable write permits checkout to clear the cart.
    if (!online || offlineMode) {
      _pending = await store.pendingSales(sale.cashierUid, sale.storeCode);
      _changed();
      return const SaleSubmission(SaleSubmissionStatus.queued);
    }
    return _send(sale);
  }

  Future<SaleSubmission> _send(SaleRecord sale) async {
    if (sale.cashierUid != currentUserId() ||
        sale.cashierUid != _uid ||
        sale.storeCode != _storeCode) {
      return const SaleSubmission(SaleSubmissionStatus.queued);
    }
    try {
      await gateway.commit(sale).timeout(requestTimeout);
      await store.remove(sale.id);
      online = true;
      lastError = null;
      return const SaleSubmission(SaleSubmissionStatus.synced);
    } on SaleConflictException catch (error) {
      await store.markConflict(sale.id, error.message);
      return SaleSubmission(SaleSubmissionStatus.conflict, error.message);
    } on TimeoutException {
      online = false;
      return const SaleSubmission(SaleSubmissionStatus.queued);
    } on FirebaseException catch (error) {
      if (_temporary(error)) {
        online = false;
        return const SaleSubmission(SaleSubmissionStatus.queued);
      }
      final message =
          'Server rejected this receipt (${error.code}). Review and retry.';
      await store.markConflict(sale.id, message);
      return SaleSubmission(SaleSubmissionStatus.conflict, message);
    } catch (error) {
      // An unknown outcome is retained; deleting it could lose a paid receipt.
      lastError = 'Could not confirm the saved receipt: $error';
      return const SaleSubmission(SaleSubmissionStatus.queued);
    } finally {
      if (_uid == sale.cashierUid && _storeCode == sale.storeCode) {
        _pending = await store.pendingSales(sale.cashierUid, sale.storeCode);
        _changed();
      }
    }
  }

  Future<void> synchronize() async {
    if (_syncFuture != null) return _syncFuture;
    final future = _synchronize();
    _syncFuture = future;
    try {
      await future;
    } finally {
      _syncFuture = null;
    }
  }

  Future<void> _synchronize() async {
    final uid = _uid;
    final code = _storeCode;
    if (uid == null || code == null || uid != currentUserId() || offlineMode) {
      return;
    }
    final pending = await store.pendingSales(uid, code);
    if (pending.isEmpty) return;
    syncing = true;
    _changed();
    try {
      for (final row in pending) {
        if (_uid != uid ||
            _storeCode != code ||
            currentUserId() != uid ||
            offlineMode) {
          break;
        }
        if (row.isConflict) continue;
        final result = await _send(row.sale);
        if (result.status == SaleSubmissionStatus.queued) break;
      }
    } catch (error) {
      lastError = 'Could not synchronize saved sales: $error';
    } finally {
      syncing = false;
      _changed();
    }
  }

  Future<void> retry(String saleId) async {
    if (!_pending.any((row) => row.sale.id == saleId)) return;
    await store.retry(saleId);
    await synchronize();
  }

  Future<void> setOffline(bool enabled) async {
    if (enabled) {
      await firestore.disableNetwork();
      offlineMode = true;
      online = false;
    } else {
      await firestore.enableNetwork();
      offlineMode = false;
      if (_uid != null) await loadContext(_uid!);
      await synchronize();
    }
    _changed();
  }

  static bool _temporary(FirebaseException error) => [
    'unavailable',
    'deadline-exceeded',
    'aborted',
    'cancelled',
    'network-request-failed',
  ].contains(error.code);

  static int _stock(Map<String, dynamic> product) {
    final value = product['stock'] ?? product['quantity'];
    final number = value is num ? value : num.tryParse(value.toString());
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        number != number.toInt()) {
      throw StateError('This product has invalid stock data.');
    }
    return number.toInt();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _queueSubscription?.cancel();
    _productSubscription?.cancel();
    super.dispose();
  }
}
