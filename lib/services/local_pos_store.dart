import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:sembast/sembast.dart';

import '../models/sale_record.dart';
import 'local_pos_database.dart';

class PendingSale {
  const PendingSale({required this.sale, this.conflictMessage});

  final SaleRecord sale;
  final String? conflictMessage;
  bool get isConflict => conflictMessage != null;

  factory PendingSale.fromJson(Map<String, Object?> json) => PendingSale(
    sale: SaleRecord.fromJson(Map<String, dynamic>.from(json['sale'] as Map)),
    conflictMessage: json['conflictMessage'] as String?,
  );
}

/// A cash sale stays here until the server confirms it or the cashier resolves
/// it. Conflict rows also reserve stock because payment has already been taken.
class LocalPosStore {
  LocalPosStore(this.database);

  final Database database;
  final _sales = stringMapStoreFactory.store('pending_sales');
  final _contexts = stringMapStoreFactory.store('cashier_contexts');
  final _products = stringMapStoreFactory.store('products');

  static Future<LocalPosStore> open() async =>
      LocalPosStore(await openLocalPosDatabase());

  Finder _scope(String cashierUid, String storeCode) => Finder(
    filter: Filter.and([
      Filter.equals('sale.cashierUid', cashierUid),
      Filter.equals('sale.storeCode', storeCode),
    ]),
    sortOrders: [SortOrder('sale.createdAt'), SortOrder('sale.id')],
  );

  Stream<List<PendingSale>> watchSales(String cashierUid, String storeCode) =>
      _sales
          .query(finder: _scope(cashierUid, storeCode))
          .onSnapshots(database)
          .map(
            (rows) =>
                rows.map((row) => PendingSale.fromJson(row.value)).toList(),
          );

  Future<List<PendingSale>> pendingSales(
    String cashierUid,
    String storeCode,
  ) async {
    final rows = await _sales.find(
      database,
      finder: _scope(cashierUid, storeCode),
    );
    return rows.map((row) => PendingSale.fromJson(row.value)).toList();
  }

  Future<void> enqueue(SaleRecord sale) async {
    await database.transaction((transaction) async {
      final record = _sales.record(sale.id);
      final previous = await record.get(transaction);
      if (previous != null) {
        if (jsonEncode(previous['sale']) != jsonEncode(sale.toJson())) {
          throw StateError('A different sale already uses this receipt ID.');
        }
        return;
      }
      await record.put(transaction, {'sale': sale.toJson()});
    });
  }

  /// Check and reserve cached stock in the same transaction as the receipt.
  Future<void> enqueueChecked(SaleRecord sale) async {
    await database.transaction((transaction) async {
      final record = _sales.record(sale.id);
      final previous = await record.get(transaction);
      if (previous != null) {
        if (jsonEncode(previous['sale']) != jsonEncode(sale.toJson())) {
          throw StateError('A different sale already uses this receipt ID.');
        }
        return;
      }
      if (sale.items.isEmpty ||
          sale.storeCode.isEmpty ||
          sale.cashierUid.isEmpty) {
        throw StateError('A sale must have a store, cashier and items.');
      }
      final quantities = <String, int>{};
      for (final item in sale.items) {
        if (item.productId.isEmpty ||
            item.quantity <= 0 ||
            !item.price.isFinite ||
            item.price < 0 ||
            !item.subtotal.isFinite) {
          throw StateError('This receipt contains an invalid item.');
        }
        quantities.update(
          item.productId,
          (value) => value + item.quantity,
          ifAbsent: () => item.quantity,
        );
      }
      final pending = await _sales.find(
        transaction,
        finder: Finder(filter: Filter.equals('sale.storeCode', sale.storeCode)),
      );
      for (final entry in quantities.entries) {
        final product = await _products
            .record(_productKey(sale.storeCode, entry.key))
            .get(transaction);
        if (product == null) {
          throw StateError(
            'This product is not available in the offline catalogue.',
          );
        }
        final value = product['stock'] ?? product['quantity'];
        final stock = value is num ? value : num.tryParse(value.toString());
        if (stock == null ||
            !stock.isFinite ||
            stock < 0 ||
            stock != stock.toInt()) {
          throw StateError('This product has invalid stock data.');
        }
        final reserved = pending.fold<int>(
          0,
          (total, row) =>
              total +
              PendingSale.fromJson(row.value).sale.items
                  .where((item) => item.productId == entry.key)
                  .fold<int>(0, (sum, item) => sum + item.quantity),
        );
        if (!sale.correctStockShortages && entry.value > stock - reserved) {
          throw StateError('No available stock for ${product['name']}.');
        }
      }
      await record.put(transaction, {'sale': sale.toJson()});
    });
  }

  Future<void> markConflict(String id, String message) async {
    await database.transaction((transaction) async {
      final record = _sales.record(id);
      if (await record.exists(transaction)) {
        await record.update(transaction, {'conflictMessage': message});
      }
    });
  }

  Future<void> remove(String id) async {
    await _sales.record(id).delete(database);
  }

  Future<void> retry(String id) async {
    await database.transaction((transaction) async {
      final record = _sales.record(id);
      final row = await record.get(transaction);
      if (row == null) return;
      final updated = Map<String, Object?>.from(row);
      updated.remove('conflictMessage');
      await record.put(transaction, updated);
    });
  }

  Future<int> reservedQuantity(
    String cashierUid,
    String storeCode,
    String productId,
  ) async {
    final sales = await pendingSales(cashierUid, storeCode);
    return sales.fold<int>(
      0,
      (sum, pending) =>
          sum +
          pending.sale.items
              .where((item) => item.productId == productId)
              .fold<int>(0, (total, item) => total + item.quantity),
    );
  }

  Future<void> saveContext(
    String uid,
    Map<String, dynamic> profile,
    Map<String, dynamic> store,
  ) async {
    await _contexts.record(uid).put(database, {
      'profile': _jsonValue(profile),
      'store': _jsonValue(store),
    });
  }

  Future<Map<String, dynamic>?> contextFor(String uid) async {
    final value = await _contexts.record(uid).get(database);
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  /// Replace one store's snapshot atomically; another store's cache is untouched.
  Future<void> cacheProducts(
    String storeCode,
    List<Map<String, dynamic>> products,
  ) async {
    if (storeCode.isEmpty ||
        products.any(
          (product) =>
              product['storeCode'] != storeCode ||
              product['id'] is! String ||
              (product['id'] as String).isEmpty,
        )) {
      throw ArgumentError('Cached products must belong to the selected store.');
    }
    await database.transaction((transaction) async {
      await _products.delete(
        transaction,
        finder: Finder(filter: Filter.equals('storeCode', storeCode)),
      );
      for (final product in products) {
        await _products
            .record(_productKey(storeCode, product['id'] as String))
            .put(
              transaction,
              Map<String, Object?>.from(_jsonValue(product) as Map),
            );
      }
    });
  }

  Future<Map<String, dynamic>?> productByBarcode(
    String storeCode,
    String barcode,
  ) async {
    final products = await _products.find(
      database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('storeCode', storeCode),
          Filter.equals('barcode', barcode),
        ]),
        limit: 2,
      ),
    );
    if (products.length > 1) {
      throw StateError('Multiple products in this store use this barcode.');
    }
    return products.isEmpty
        ? null
        : Map<String, dynamic>.from(products.single.value);
  }

  Future<Map<String, dynamic>?> productById(String storeCode, String id) async {
    final product = await _products
        .record(_productKey(storeCode, id))
        .get(database);
    return product == null ? null : Map<String, dynamic>.from(product);
  }

  static String _productKey(String storeCode, String id) =>
      jsonEncode([storeCode, id]);

  // Firestore timestamps cannot be saved in the JSON-based local database.
  static Object? _jsonValue(Object? value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry(key.toString(), _jsonValue(entry)),
      );
    }
    if (value is Iterable) return value.map(_jsonValue).toList();
    return value;
  }
}
