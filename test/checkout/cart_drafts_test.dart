import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/screens/cart/cart_screen.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/utils/cart_manager.dart';

class FaultyStore extends LocalPosStore {
  FaultyStore(super.database);
  bool fail = false;
  @override
  Future<void> saveCartState(String uid, String code, Map<String, Object?> state) {
    if (fail) throw StateError('Simulated device storage failure');
    return super.saveCartState(uid, code, state);
  }
}

// UI timing is tested separately from the real Sembast/disk cases above.
class UiCartStore extends LocalPosStore {
  UiCartStore(super.database);
  Map<String, Object?>? state;
  @override
  Future<Map<String, Object?>?> cartState(String uid, String code) => Future.value(state);
  @override
  Future<void> saveCartState(String uid, String code, Map<String, Object?> value) {
    state = value;
    return Future.value();
  }
}

void add(String name, {String store = 'A'}) => CartManager.addItem(
  name: name,
  price: 2.125,
  barcode: name,
  image: '',
  productId: name,
  storeCode: store,
);
void main() {
  late Database db;
  late FaultyStore store;
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });
  setUp(() async {
    CartManager.detach();
    db = await databaseFactoryMemory.openDatabase('draft-${DateTime.now().microsecondsSinceEpoch}');
    store = FaultyStore(db);
    await CartManager.bind(store, 'cashier', 'A');
  });
  tearDown(() async {
    try {
      await CartManager.flush();
    } catch (_) {}
    CartManager.detach();
    await db.close();
  });
  test('autosave serializes rapid changes and isolates users and stores', () async {
    add('Pen');
    add('Pen');
    CartManager.increaseQuantity(0);
    await CartManager.bind(store, 'other', 'B');
    expect(CartManager.items, isEmpty);
    add('Book', store: 'B');
    await CartManager.flush();
    await CartManager.bind(store, 'cashier', 'A');
    expect(CartManager.items.single.name, 'Pen');
    expect(CartManager.items.single.quantity, 3);
    expect(CartManager.total, 6.375);
    await CartManager.bind(store, 'cashier', 'B');
    expect(CartManager.items, isEmpty);
  });
  test('holding and resuming atomically swaps active carts without changing stock', () async {
    await store.cacheProducts('A', [
      {'id': 'Pen', 'storeCode': 'A', 'name': 'Pen', 'barcode': 'Pen', 'price': 2.125, 'stock': 4},
    ]);
    add('Pen');
    await CartManager.hold('Customer one');
    expect(CartManager.items, isEmpty);
    final first = CartManager.heldSales.single['id'].toString();
    add('Book');
    await CartManager.resume(first);
    expect(CartManager.items.single.name, 'Pen');
    expect(CartManager.heldSales, hasLength(1));
    expect((CartManager.heldSales.single['items'] as List).single['name'], 'Book');
    final next = CartManager.heldSales.single['id'].toString();
    await CartManager.resume(next);
    expect(CartManager.items.single.name, 'Book');
    expect((await store.productById('A', 'Pen'))!['stock'], 4);
    CartManager.detach();
    await CartManager.bind(store, 'cashier', 'A');
    expect(CartManager.items.single.name, 'Book');
    expect(CartManager.heldSales, hasLength(1));
  });
  test('cart snapshots reuse cached photos instead of copying them on each scan', () async {
    const image = 'data:image/png;base64,AA==';
    await store.cacheProducts('A', [
      {
        'id': 'Photo',
        'storeCode': 'A',
        'name': 'Photo',
        'barcode': 'Photo',
        'price': 2.125,
        'stock': 4,
        'image': image,
      },
    ]);
    CartManager.addItem(
      name: 'Photo',
      price: 2.125,
      barcode: 'Photo',
      image: image,
      productId: 'Photo',
      storeCode: 'A',
    );
    await CartManager.flush();
    final snapshot = await store.cartState('cashier', 'A');
    expect((snapshot!['active'] as List).single['image'], '');
    CartManager.detach();
    await CartManager.bind(store, 'cashier', 'A');
    expect(CartManager.items.single.image, image);
    await CartManager.hold('Photo cart');
    await CartManager.resume(CartManager.heldSales.single['id'].toString());
    expect(CartManager.items.single.image, image);
  });

  test('failed save keeps the active cart and retry makes it durable', () async {
    store.fail = true;
    add('Pen');
    await expectLater(CartManager.flush(), throwsStateError);
    expect(CartManager.saveError, isNotNull);
    await expectLater(CartManager.hold('No loss'), throwsStateError);
    expect(CartManager.items.single.name, 'Pen');
    expect(CartManager.heldSales, isEmpty);
    store.fail = false;
    await CartManager.flush();
    expect(CartManager.saveError, isNull);
    CartManager.detach();
    await CartManager.bind(store, 'cashier', 'A');
    expect(CartManager.items.single.name, 'Pen');
  });
  test('accepting payment retires only active draft in the receipt transaction', () async {
    add('Held');
    await CartManager.hold('Waiting customer');
    add('Pen');
    await CartManager.flush();
    await store.cacheProducts('A', [
      {'id': 'Pen', 'storeCode': 'A', 'name': 'Pen', 'barcode': 'Pen', 'price': 2.125, 'stock': 4},
    ]);
    final sale = SaleRecord(
      id: 'paid',
      storeCode: 'A',
      storeName: 'Store',
      cashierUid: 'cashier',
      cashierName: 'Cashier',
      paymentMethod: 'Cash',
      createdAt: DateTime(2026),
      items: const [
        SaleLine(productId: 'Pen', barcode: 'Pen', name: 'Pen', price: 2.125, quantity: 1),
      ],
    );
    await store.enqueueChecked(sale);
    // Simulate closing before checkout can clear the in-memory cart.
    CartManager.detach();
    await CartManager.bind(store, 'cashier', 'A');
    expect(CartManager.items, isEmpty);
    expect(CartManager.heldSales, hasLength(1));
    expect((await store.pendingSales('cashier', 'A')).single.sale.id, 'paid');
  });
  test('disk reopen restores unpaid active and held carts', () async {
    final dir = await Directory.systemTemp.createTemp('shoppad-drafts-');
    final path = '${dir.path}${Platform.pathSeparator}drafts.db';
    var disk = await databaseFactoryIo.openDatabase(path);
    try {
      await CartManager.bind(LocalPosStore(disk), 'owner', 'A');
      add('Held');
      await CartManager.hold('Later');
      add('Active');
      await CartManager.flush();
      CartManager.detach();
      await disk.close();
      disk = await databaseFactoryIo.openDatabase(path);
      await CartManager.bind(LocalPosStore(disk), 'owner', 'A');
      expect(CartManager.items.single.name, 'Active');
      expect(CartManager.heldSales.single['label'], 'Later');
    } finally {
      CartManager.detach();
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
  testWidgets('hold and resume controls work on a narrow phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      await CartManager.bind(UiCartStore(db), 'cashier', 'A');
      add('Pen');
      await CartManager.flush();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CartScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hold sale').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Waiting customer');
    await tester.tap(find.widgetWithText(FilledButton, 'Hold sale'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(CartManager.items, isEmpty);
    await tester.tap(find.text('Held sales (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waiting customer'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(CartManager.items.single.name, 'Pen');
    expect(CartManager.heldSales, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
