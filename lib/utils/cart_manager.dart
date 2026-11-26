import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../services/local_pos_store.dart';

/// One unpaid cart and held carts, scoped to the signed-in user and store.
/// Paid receipts are persisted separately by SaleSyncService.
abstract final class CartManager {
  static final List<CartItem> items = [];
  static final revision = ValueNotifier<int>(0);
  static LocalPosStore? _store;
  static String? _uid, _code;
  static List<Map<String, Object?>> _held = [];
  static Future<void> _writes = Future<void>.value();
  static int _pendingWrites = 0, _generation = 0;
  static bool switching = false;
  static String? saveError;
  static bool get saving => _pendingWrites > 0;
  static bool get canSave => _store != null;

  /// Whether the cart currently belongs to this device store, user and shop.
  static bool isBoundTo(LocalPosStore store, String? uid, String? code) =>
      _store == store && _uid == uid && _code == code;
  static List<Map<String, Object?>> get heldSales => List.unmodifiable(_held);
  static void _changed() => revision.value++;

  /// Loads the saved active and held carts for a user and store from the device.
  /// [_generation] makes an older, slower load give way to a newer one.
  static Future<void> bind(LocalPosStore store, String uid, String code) async {
    if (_store == store && _uid == uid && _code == code) return;
    detach();
    final generation = _generation;
    await _writes;
    if (generation != _generation) return;
    final state = await store.cartState(uid, code);
    if (generation != _generation) return;
    final restored = await _withCachedImages(store, code, _readItems(state?['active'], code));
    if (generation != _generation) return;
    final held = (state?['held'] as List? ?? []).map((entry) {
      final row = Map<String, Object?>.from(entry as Map);
      _readItems(row['items'], code);
      return row;
    }).toList();
    _store = store;
    _uid = uid;
    _code = code;
    items
      ..clear()
      ..addAll(restored);
    _held = held;
    saveError = null;
    _changed();
  }

  /// Sign-out removes the in-memory view, preserving drafts on this device.
  static void detach() {
    _generation++;
    _store = null;
    _uid = _code = null;
    items.clear();
    _held = [];
    saveError = null;
    switching = false;
    _changed();
  }

  static Map<String, Object?> _snapshot({
    List<CartItem>? active,
    List<Map<String, Object?>>? held,
  }) => {
    // Photos already live in the local catalogue; avoid copying them on every scan.
    'active': (active ?? items).map((item) => item.toSaleData()).toList(),
    'held': held ?? _held,
  };

  /// Reads saved cart lines, refusing any that belong to another store or look invalid.
  static List<CartItem> _readItems(Object? value, String code) =>
      (value as List? ?? []).map((entry) {
        final row = Map<String, dynamic>.from(entry as Map);
        final price = row['price'];
        final quantity = row['quantity'];
        if (row['storeCode'] != code ||
            price is! num ||
            !price.isFinite ||
            price < 0 ||
            quantity is! int ||
            quantity <= 0 ||
            row['productId'] is! String) {
          throw StateError('This saved cart needs review before it can be restored.');
        }
        return CartItem(
          name: row['name'].toString(),
          price: price.toDouble(),
          quantity: quantity,
          barcode: row['barcode'].toString(),
          image: (row['image'] ?? '').toString(),
          productId: row['productId'],
          storeCode: code,
          cost: row['cost'] is num ? (row['cost'] as num).toDouble() : 0,
        );
      }).toList();

  /// Fills in missing product images from the device's product cache.
  static Future<List<CartItem>> _withCachedImages(
    LocalPosStore store,
    String code,
    List<CartItem> source,
  ) async {
    final restored = <CartItem>[];
    for (final item in source) {
      var image = item.image;
      if (image.isEmpty && item.productId.isNotEmpty) {
        final cached = await store.productById(code, item.productId);
        image = (cached?['image'] ?? '').toString();
      }
      restored.add(
        CartItem(
          name: item.name,
          price: item.price,
          barcode: item.barcode,
          image: image,
          productId: item.productId,
          storeCode: item.storeCode,
          quantity: item.quantity,
          cost: item.cost,
        ),
      );
    }
    return restored;
  }

  /// Writes the cart to the device in order, one write after another.
  static void _save() {
    final store = _store;
    final uid = _uid, code = _code;
    if (store == null || uid == null || code == null) {
      _changed();
      return;
    }
    final state = _snapshot();
    final generation = _generation;
    _pendingWrites++;
    _changed();
    _writes = _writes.then((_) async {
      try {
        await store.saveCartState(uid, code, state);
        if (generation == _generation) saveError = null;
      } catch (_) {
        if (generation == _generation) {
          saveError = 'Cart could not be saved on this device. Retry before leaving.';
        }
      } finally {
        _pendingWrites--;
        _changed();
      }
    });
  }

  static Future<void> flush() async {
    await _writes;
    if (saveError != null) {
      _save();
      await _writes;
    }
    if (saveError != null) throw StateError(saveError!);
  }

  /// Adds one unit of a product, or raises the quantity if it is already in the cart.
  static void addItem({
    required String name,
    required double price,
    required String barcode,
    required String image,
    String productId = '',
    String storeCode = '',
    double cost = 0,
  }) {
    if (switching) throw StateError('Wait for the cart to finish switching.');
    final index = items.indexWhere(
      (item) =>
          item.storeCode == storeCode &&
          (productId.isNotEmpty ? item.productId == productId : item.barcode == barcode),
    );
    if (index != -1) {
      items[index].quantity++;
    } else {
      items.add(
        CartItem(
          name: name,
          price: price,
          barcode: barcode,
          image: image,
          productId: productId,
          storeCode: storeCode,
          cost: cost,
        ),
      );
    }
    _save();
  }

  static void increaseQuantity(int index) {
    items[index].quantity++;
    _save();
  }

  static void decreaseQuantity(int index) {
    if (items[index].quantity > 1) {
      items[index].quantity--;
    } else {
      items.removeAt(index);
    }
    _save();
  }

  static void removeItem(int index) {
    items.removeAt(index);
    _save();
  }

  /// Puts a removed line back where it was (undo after a mistaken delete).
  static void restoreItem(int index, CartItem item) {
    items.insert(index.clamp(0, items.length), item);
    _save();
  }

  static double get total => items.fold(0, (value, item) => value + item.totalPrice);
  static void clearCart() {
    items.clear();
    _save();
  }

  static Map<String, Object?> _heldEntry(String note) {
    final now = DateTime.now();
    return {
      'id': '${now.microsecondsSinceEpoch}',
      'label': note.trim().isEmpty
          ? 'Sale ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'
          : note.trim(),
      'createdAt': now.toIso8601String(),
      'items': _snapshot()['active'],
      'total': total,
    };
  }

  static Future<void> hold(String note) async {
    if (switching || items.isEmpty) return;
    await _replace(active: [], held: [..._held, _heldEntry(note)]);
  }

  static Future<void> resume(String id) async {
    if (switching) return;
    final selected = _held.firstWhere((row) => row['id'] == id);
    final next = _held.where((row) => row['id'] != id).toList();
    if (items.isNotEmpty) next.add(_heldEntry(''));
    await _replace(active: _readItems(selected['items'], _code!), held: next);
  }

  /// Swaps the active and held carts (hold / resume a sale) and saves the result.
  static Future<void> _replace({
    required List<CartItem> active,
    required List<Map<String, Object?>> held,
  }) async {
    if (_store == null) {
      throw StateError('Sign in to save carts on this device.');
    }
    switching = true;
    _changed();
    final generation = _generation;
    try {
      await flush();
      final store = _store;
      final uid = _uid, code = _code;
      if (store == null || uid == null || code == null || generation != _generation) {
        throw StateError('Your account has changed.');
      }
      final restored = await _withCachedImages(store, code, active);
      if (generation != _generation) {
        throw StateError('Your account has changed.');
      }
      await store.saveCartState(uid, code, _snapshot(active: restored, held: held));
      if (generation != _generation) return;
      items
        ..clear()
        ..addAll(restored);
      _held = held;
      saveError = null;
    } finally {
      if (generation == _generation) switching = false;
      _changed();
    }
  }
}
