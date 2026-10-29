import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/sale_record.dart';

class SaleConflictException implements Exception {
  const SaleConflictException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class SaleGateway {
  Future<void> commit(SaleRecord sale);
}

/// Reads authoritative stock before atomically saving one sale and its changes.
class FirestoreSaleGateway implements SaleGateway {
  FirestoreSaleGateway({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? Function()? currentUserId,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth,
       _currentUserId = currentUserId;

  final FirebaseFirestore _firestore;
  final FirebaseAuth? _auth;
  final String? Function()? _currentUserId;

  String? _userId() => _currentUserId != null
      ? _currentUserId()
      : (_auth ?? FirebaseAuth.instance).currentUser?.uid;

  @override
  Future<void> commit(SaleRecord sale) async {
    final quantities = _validate(sale);
    final uid = _userId();
    if (uid == null || uid != sale.cashierUid) {
      throw const SaleConflictException(
        'Sign in as the cashier for this sale.',
      );
    }

    // References and the sale ID are fixed outside the retryable callback.
    final saleRef = _firestore.collection('sales').doc(sale.id);
    final userRef = _firestore.collection('users').doc(uid);
    final products = {
      for (final id in quantities.keys)
        id: _firestore.collection('products').doc(id),
    };

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(saleRef);
      final profile = await transaction.get(userRef);
      final profileData = profile.data();
      if (_userId() != uid ||
          profileData == null ||
          profileData['storeCode'] != sale.storeCode ||
          !['owner', 'cashier'].contains(profileData['role']) ||
          profileData['isActive'] == false ||
          profileData['status'] == 'disabled') {
        throw const SaleConflictException(
          'Your account is not authorized to sell for this store.',
        );
      }

      // A lost acknowledgement or restarted app must never deduct stock twice.
      if (existing.exists) {
        if (!_matches(existing.data()!, sale)) {
          throw const SaleConflictException(
            'This receipt ID already belongs to a different sale.',
          );
        }
        return;
      }

      final stock = <String, Map<String, dynamic>>{};
      for (final entry in products.entries) {
        final snapshot = await transaction.get(entry.value);
        final data = snapshot.data();
        if (data == null || data['storeCode'] != sale.storeCode) {
          throw const SaleConflictException(
            'A product was removed or belongs to another store.',
          );
        }
        stock[entry.key] = data;
      }

      final remaining = <String, int>{};
      final corrections = <String, Map<String, dynamic>>{};
      for (final entry in quantities.entries) {
        final data = stock[entry.key]!;
        final item = sale.items.firstWhere((i) => i.productId == entry.key);
        final available = data['stock'] ?? data['quantity'];
        if (data['barcode']?.toString() != item.barcode ||
            available is! num ||
            !available.isFinite ||
            available < 0 ||
            available != available.toInt()) {
          throw SaleConflictException('Invalid product data for ${item.name}.');
        }
        if (available < entry.value && !sale.correctStockShortages) {
          throw SaleConflictException(
            '${item.name}: only ${available.toInt()} left; '
            '${entry.value} requested. Review this sale before retrying.',
          );
        }
        final shortage = entry.value > available
            ? entry.value - available.toInt()
            : 0;
        if (shortage > 0) {
          corrections[entry.key] = {
            'productId': entry.key,
            'name': item.name,
            'barcode': item.barcode,
            'stockBefore': available.toInt(),
            'addedQuantity': shortage,
            'quantitySold': entry.value,
            'stockAfter': 0,
            'reason': 'physical_items_sold_exceed_recorded_stock',
            'cashierUid': sale.cashierUid,
          };
        }
        remaining[entry.key] = available.toInt() + shortage - entry.value;
      }

      // All reads and checks finish before the first write.
      transaction.set(saleRef, {
        ...sale.toJson(),
        'createdAt': Timestamp.fromDate(sale.createdAt),
        'syncedAt': FieldValue.serverTimestamp(),
        'subtotal': sale.total,
        'discount': 0.0,
        'refund': 0.0,
        'tax': 0.0,
        'status': 'completed',
        'type': 'sale',
        if (corrections.isNotEmpty)
          'stockCorrections': corrections.values.toList(),
        if (corrections.isNotEmpty)
          'stockCorrectionUnits': corrections.values.fold<int>(
            0,
            (totalUnits, row) => totalUnits + (row['addedQuantity'] as int),
          ),
      });
      for (final entry in remaining.entries) {
        transaction.update(products[entry.key]!, {
          'stock': entry.value,
          if (corrections.containsKey(entry.key))
            'lastStockCorrection': {
              ...corrections[entry.key]!,
              'saleId': sale.id,
              'recordedAt': FieldValue.serverTimestamp(),
            },
          if (stock[entry.key]!.containsKey('quantity'))
            'quantity': entry.value,
        });
      }
    });
  }

  Map<String, int> _validate(SaleRecord sale) {
    bool validId(String value) =>
        value.trim().isNotEmpty && !value.contains('/');
    if (!validId(sale.id) ||
        !validId(sale.cashierUid) ||
        sale.storeCode.trim().isEmpty ||
        !['Cash', 'BenefitPay'].contains(sale.paymentMethod) ||
        sale.items.isEmpty ||
        !sale.total.isFinite) {
      throw const SaleConflictException('The sale details are invalid.');
    }
    final quantities = <String, int>{};
    final lines = <String, SaleLine>{};
    for (final item in sale.items) {
      if (!validId(item.productId) ||
          item.barcode.trim().isEmpty ||
          item.name.trim().isEmpty ||
          item.quantity <= 0 ||
          !item.price.isFinite ||
          item.price < 0) {
        throw const SaleConflictException('A sale item has invalid details.');
      }
      final previous = lines[item.productId];
      if (previous != null &&
          (previous.barcode != item.barcode || previous.price != item.price)) {
        throw const SaleConflictException(
          'Duplicate product lines have inconsistent details.',
        );
      }
      lines[item.productId] = item;
      quantities.update(
        item.productId,
        (quantity) => quantity + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    return quantities;
  }

  bool _matches(Map<String, dynamic> data, SaleRecord sale) {
    try {
      final date = data['createdAt'];
      if (date is! Timestamp ||
          data['total'] != sale.total ||
          data['receiptNumber'] != sale.receiptNumber) {
        return false;
      }
      final stored = SaleRecord.fromJson({
        ...data,
        'createdAt': date.toDate().toUtc().toIso8601String(),
      });
      return jsonEncode(stored.toJson()) == jsonEncode(sale.toJson());
    } catch (_) {
      return false;
    }
  }
}
