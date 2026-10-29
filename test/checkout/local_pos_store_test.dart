import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late Database database;
  late LocalPosStore store;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'pos-${DateTime.now().microsecondsSinceEpoch}',
    );
    store = LocalPosStore(database);
  });

  tearDown(() => database.close());

  test(
    'physical stock correction policy stays durable and permits all five units',
    () async {
      await store.cacheProducts('A', [
        {..._product('A', 'product', '123'), 'stock': 3},
      ]);
      final corrected = SaleRecord(
        id: 'physical',
        storeCode: 'A',
        storeName: 'Test',
        cashierUid: 'cashier',
        cashierName: 'Cashier',
        paymentMethod: 'Cash',
        createdAt: DateTime.utc(2026),
        correctStockShortages: true,
        items: const [
          SaleLine(
            productId: 'product',
            barcode: '123',
            name: 'Pen',
            price: 1,
            quantity: 5,
          ),
        ],
      );
      await store.enqueueChecked(corrected);
      await store.enqueueChecked(corrected);
      final pending = await store.pendingSales('cashier', 'A');
      expect(pending, hasLength(1));
      expect(pending.single.sale.correctStockShortages, isTrue);
      expect(pending.single.sale.total, 5);
      expect(await store.reservedQuantity('cashier', 'A', 'product'), 5);
    },
  );
  test(
    'checked receipts reserve stock atomically and retries are idempotent',
    () async {
      await store.cacheProducts('A', [_product('A', 'product', '123')]);
      final results = await Future.wait([
        store
            .enqueueChecked(_sale('first', quantity: 6))
            .then((_) => true, onError: (Object _) => false),
        store
            .enqueueChecked(_sale('second', quantity: 6))
            .then((_) => true, onError: (Object _) => false),
      ]);
      expect(results.where((result) => result), hasLength(1));
      final saved = (await store.pendingSales('cashier', 'A')).single.sale;
      await store.markConflict(saved.id, 'Review');
      await store.enqueueChecked(saved);
      expect(
        (await store.pendingSales('cashier', 'A')).single.isConflict,
        isTrue,
      );
      await expectLater(
        store.enqueueChecked(_sale('excess', quantity: 5)),
        throwsStateError,
      );
      await store.enqueueChecked(_sale('remaining', quantity: 4));
      expect(await store.reservedQuantity('cashier', 'A', 'product'), 10);
    },
  );

  test(
    'checked receipts reject missing products and invalid quantities',
    () async {
      await expectLater(
        store.enqueueChecked(_sale('missing')),
        throwsStateError,
      );
      await store.cacheProducts('A', [_product('A', 'product', '123')]);
      await expectLater(
        store.enqueueChecked(_sale('zero', quantity: 0)),
        throwsStateError,
      );
      expect(await store.pendingSales('cashier', 'A'), isEmpty);
    },
  );

  test(
    'receipt IDs are stable and re-enqueue cannot erase a conflict',
    () async {
      final sale = _sale('one');
      await store.enqueue(sale);
      await store.markConflict(sale.id, 'Stock is no longer available');
      await store.enqueue(sale);
      final queued = await store.pendingSales('cashier', 'A');
      expect(queued, hasLength(1));
      expect(queued.single.sale.id, sale.id);
      expect(queued.single.isConflict, isTrue);
      await expectLater(
        store.enqueue(_sale('one', quantity: 2)),
        throwsStateError,
      );
    },
  );

  test(
    'reservations include conflicts and isolate cashier/store/product',
    () async {
      await store.enqueue(_sale('a', quantity: 2));
      await store.enqueue(_sale('b', quantity: 3));
      await store.markConflict('b', 'Reconcile stock');
      await store.enqueue(_sale('c', uid: 'other', quantity: 4));
      await store.enqueue(_sale('d', storeCode: 'B', quantity: 5));
      await store.enqueue(_sale('e', productId: 'different', quantity: 6));
      expect(await store.reservedQuantity('cashier', 'A', 'product'), 5);
      expect(await store.reservedQuantity('other', 'A', 'product'), 4);
      expect(await store.reservedQuantity('cashier', 'B', 'product'), 5);
      await store.retry('b');
      final queued = await store.pendingSales('cashier', 'A');
      expect(
        queued.firstWhere((row) => row.sale.id == 'b').isConflict,
        isFalse,
      );
      expect(await store.reservedQuantity('cashier', 'A', 'product'), 5);
      await store.remove('b');
      expect(await store.reservedQuantity('cashier', 'A', 'product'), 2);
    },
  );

  test(
    'queue stream reports durable changes within its current scope',
    () async {
      final events = <List<PendingSale>>[];
      final subscription = store.watchSales('cashier', 'A').listen(events.add);
      await store.enqueue(_sale('a'));
      await store.enqueue(_sale('b', uid: 'other'));
      await store.markConflict('a', 'Review required');
      await Future<void>.delayed(Duration.zero);
      expect(events.last, hasLength(1));
      expect(events.last.single.sale.id, 'a');
      expect(events.last.single.isConflict, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'product lookup scopes barcode and rejects an ambiguous store barcode',
    () async {
      await store.cacheProducts('A', [_product('A', 'a', '123')]);
      await store.cacheProducts('B', [_product('B', 'b', '123')]);
      expect((await store.productByBarcode('A', '123'))!['id'], 'a');
      expect((await store.productByBarcode('B', '123'))!['id'], 'b');
      expect(await store.productById('A', 'b'), isNull);
      expect(await store.productByBarcode('A', 'missing'), isNull);
      await store.cacheProducts('A', [
        _product('A', 'a', '123'),
        _product('A', 'duplicate', '123'),
      ]);
      await expectLater(store.productByBarcode('A', '123'), throwsStateError);
      expect((await store.productByBarcode('B', '123'))!['id'], 'b');
      await expectLater(
        store.cacheProducts('A', [_product('B', 'b', '123')]),
        throwsArgumentError,
      );
      expect(await store.productById('A', 'a'), isNotNull);
    },
  );

  test('cached context is isolated by authenticated user', () async {
    await store.saveContext(
      'cashier',
      {'storeCode': 'A', 'fullName': 'Cashier'},
      {'storeName': 'Store A'},
    );
    await store.saveContext(
      'other',
      {'storeCode': 'B', 'fullName': 'Other'},
      {'storeName': 'Store B'},
    );
    expect((await store.contextFor('cashier'))!['profile']['storeCode'], 'A');
    expect((await store.contextFor('other'))!['store']['storeName'], 'Store B');
    expect(await store.contextFor('new-user'), isNull);
  });

  test(
    'disk reopen preserves paid sales, conflicts, product cache and context',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shoppad-store-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}pos.db';
      var disk = await databaseFactoryIo.openDatabase(path);
      try {
        final initial = LocalPosStore(disk);
        await initial.enqueue(_sale('disk-sale', quantity: 2));
        await initial.markConflict('disk-sale', 'Insufficient stock');
        await initial.cacheProducts('A', [_product('A', 'product', '123')]);
        await initial.saveContext(
          'cashier',
          {'storeCode': 'A'},
          {'storeName': 'Cached store'},
        );
        await disk.close();
        disk = await databaseFactoryIo.openDatabase(path);
        final reopened = LocalPosStore(disk);
        final rows = await reopened.pendingSales('cashier', 'A');
        expect(rows.single.sale.id, 'disk-sale');
        expect(rows.single.conflictMessage, 'Insufficient stock');
        expect(await reopened.reservedQuantity('cashier', 'A', 'product'), 2);
        expect((await reopened.productByBarcode('A', '123'))!['id'], 'product');
        expect(
          (await reopened.contextFor('cashier'))!['store']['storeName'],
          'Cached store',
        );
        await reopened.retry('disk-sale');
        await reopened.remove('disk-sale');
        await disk.close();
        disk = await databaseFactoryIo.openDatabase(path);
        expect(await LocalPosStore(disk).pendingSales('cashier', 'A'), isEmpty);
      } finally {
        await disk.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

SaleRecord _sale(
  String id, {
  String uid = 'cashier',
  String storeCode = 'A',
  String productId = 'product',
  int quantity = 1,
}) => SaleRecord(
  id: id,
  storeCode: storeCode,
  storeName: 'Store $storeCode',
  cashierUid: uid,
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime.utc(2026, 10, 6, 12),
  items: [
    SaleLine(
      productId: productId,
      barcode: '123',
      name: 'Product',
      price: 2.5,
      quantity: quantity,
    ),
  ],
);

Map<String, dynamic> _product(String storeCode, String id, String barcode) => {
  'id': id,
  'storeCode': storeCode,
  'barcode': barcode,
  'name': 'Product',
  'price': 2.5,
  'stock': 10,
};
