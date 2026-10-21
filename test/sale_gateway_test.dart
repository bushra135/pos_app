import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/sale_gateway.dart';

import 'support/optimistic_firestore.dart';

SaleLine line({
  String productId = 'product-a',
  String barcode = '123',
  double price = 2.5,
  int quantity = 1,
}) => SaleLine(
  productId: productId,
  barcode: barcode,
  name: productId,
  price: price,
  quantity: quantity,
);

SaleRecord sale({
  String id = 'sale-a',
  String storeCode = 'STORE-A',
  String cashierUid = 'cashier-a',
  List<SaleLine>? items,
}) => SaleRecord(
  id: id,
  storeCode: storeCode,
  storeName: 'Store A',
  cashierUid: cashierUid,
  cashierName: cashierUid,
  paymentMethod: 'Cash',
  createdAt: DateTime.utc(2026, 10, 6, 12, 30, 1, 200, 300),
  items: items ?? [line()],
);

void main() {
  late OptimisticFirestore firestore;
  late FirestoreSaleGateway gateway;

  setUp(() async {
    firestore = OptimisticFirestore();
    gateway = FirestoreSaleGateway(
      firestore: firestore,
      currentUserId: () => 'cashier-a',
    );
    for (final uid in ['cashier-a', 'cashier-b']) {
      await firestore.collection('users').doc(uid).set({
        'storeCode': 'STORE-A',
        'role': 'cashier',
      });
    }
    await firestore.collection('products').doc('product-a').set({
      'storeCode': 'STORE-A',
      'barcode': '123',
      'stock': 5,
      'quantity': 5,
      'price': 2.5,
    });
  });

  Future<Map<String, dynamic>> product([String id = 'product-a']) async =>
      (await firestore.collection('products').doc(id).get()).data()!;

  Future<void> expectNoSale() async {
    expect((await firestore.collection('sales').get()).docs, isEmpty);
    expect((await product())['stock'], 5);
  }

  test('durable record round trip preserves receipt and fixed cart copy', () {
    final items = [line(quantity: 2)];
    final record = sale(items: items);
    items.clear();
    final restored = SaleRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())),
    );

    expect(restored.toJson(), record.toJson());
    expect(restored.total, 5);
    expect(restored.receiptNumber, record.receiptNumber);
    expect(() => record.items.add(line()), throwsUnsupportedError);
  });

  test('saves receipt time and sale with both stock fields', () async {
    final record = sale(items: [line(quantity: 2)]);
    await gateway.commit(record);
    final data = (await firestore.collection('sales').doc(record.id).get())
        .data()!;

    expect(data['total'], 5);
    expect(data['receiptNumber'], record.receiptNumber);
    expect(
      (data['createdAt'] as Timestamp).toDate().toUtc(),
      record.createdAt.toUtc(),
    );
    expect(data['syncedAt'], isA<Timestamp>());
    expect(data['status'], 'completed');
    expect((await product())['stock'], 3);
    expect((await product())['quantity'], 3);
  });

  test('stable ID replay cannot deduct stock twice', () async {
    final record = sale(items: [line(quantity: 2)]);
    await gateway.commit(record);
    await gateway.commit(SaleRecord.fromJson(record.toJson()));

    expect((await firestore.collection('sales').get()).docs, hasLength(1));
    expect((await product())['stock'], 3);
  });

  test('already saved sale stays idempotent after product deletion', () async {
    final record = sale();
    await gateway.commit(record);
    await firestore.collection('products').doc('product-a').delete();
    await gateway.commit(record);
    expect((await firestore.collection('sales').get()).docs, hasLength(1));
  });

  test('same receipt ID with changed data is rejected', () async {
    await gateway.commit(sale());
    await expectLater(
      gateway.commit(sale(items: [line(quantity: 2)])),
      throwsA(isA<SaleConflictException>()),
    );
    expect((await product())['stock'], 4);
    expect((await firestore.collection('sales').get()).docs, hasLength(1));
  });

  test(
    'wrong-store product does not modify any stock or save a sale',
    () async {
      await firestore.collection('products').doc('product-b').set({
        'storeCode': 'STORE-B',
        'barcode': '123',
        'stock': 10,
      });
      await expectLater(
        gateway.commit(
          sale(
            items: [
              line(),
              line(productId: 'product-b'),
            ],
          ),
        ),
        throwsA(isA<SaleConflictException>()),
      );
      await expectNoSale();
      expect((await product('product-b'))['stock'], 10);
    },
  );

  test('profile store must match sale store', () async {
    await expectLater(
      gateway.commit(sale(storeCode: 'STORE-B')),
      throwsA(isA<SaleConflictException>()),
    );
    await expectNoSale();
  });

  test('authenticated UID must match cashier UID', () async {
    await expectLater(
      gateway.commit(sale(cashierUid: 'cashier-b')),
      throwsA(isA<SaleConflictException>()),
    );
    await expectNoSale();
  });

  test('disabled profile cannot sell', () async {
    await firestore.collection('users').doc('cashier-a').update({
      'isActive': false,
    });
    await expectLater(
      gateway.commit(sale()),
      throwsA(isA<SaleConflictException>()),
    );
    await expectNoSale();
  });

  test(
    'insufficient second item leaves every item and sale unchanged',
    () async {
      await firestore.collection('products').doc('product-b').set({
        'storeCode': 'STORE-A',
        'barcode': '456',
        'stock': 0,
      });
      await expectLater(
        gateway.commit(
          sale(
            items: [
              line(),
              line(productId: 'product-b', barcode: '456'),
            ],
          ),
        ),
        throwsA(isA<SaleConflictException>()),
      );
      await expectNoSale();
      expect((await product('product-b'))['stock'], 0);
    },
  );

  test(
    'duplicate quantities aggregate before checking available stock',
    () async {
      await expectLater(
        gateway.commit(sale(items: [line(quantity: 3), line(quantity: 3)])),
        throwsA(isA<SaleConflictException>()),
      );
      await expectNoSale();
      await gateway.commit(sale(items: [line(quantity: 2), line(quantity: 3)]));
      expect((await product())['stock'], 0);
    },
  );

  test(
    'legacy quantity-only product gets consistent stock and quantity',
    () async {
      await firestore.collection('products').doc('product-a').set({
        'storeCode': 'STORE-A',
        'barcode': '123',
        'quantity': 4,
      });
      await gateway.commit(sale());
      expect((await product())['stock'], 3);
      expect((await product())['quantity'], 3);
    },
  );

  for (final entry in {
    'zero quantity': line(quantity: 0),
    'negative quantity': line(quantity: -1),
    'negative price': line(price: -1),
    'NaN price': line(price: double.nan),
    'infinite price': line(price: double.infinity),
    'missing product ID': line(productId: ''),
    'changed barcode': line(barcode: 'wrong-barcode'),
  }.entries) {
    test('rejects ${entry.key} without writes', () async {
      await expectLater(
        gateway.commit(sale(items: [entry.value])),
        throwsA(isA<SaleConflictException>()),
      );
      await expectNoSale();
    });
  }

  test('duplicate product metadata must agree', () async {
    await expectLater(
      gateway.commit(sale(items: [line(), line(price: 8)])),
      throwsA(isA<SaleConflictException>()),
    );
    await expectNoSale();
  });

  test(
    'simulated concurrent cashiers selling last unit have one winner',
    () async {
      await firestore.collection('products').doc('product-a').update({
        'stock': 1,
        'quantity': 1,
      });
      final other = FirestoreSaleGateway(
        firestore: firestore,
        currentUserId: () => 'cashier-b',
      );
      Future<Object?> outcome(Future<void> operation) async {
        try {
          await operation;
          return null;
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        outcome(gateway.commit(sale())),
        outcome(other.commit(sale(id: 'sale-b', cashierUid: 'cashier-b'))),
      ]);

      expect(results.where((result) => result == null), hasLength(1));
      expect(results.whereType<SaleConflictException>(), hasLength(1));
      expect(firestore.retryCount, greaterThanOrEqualTo(1));
      expect((await product())['stock'], 0);
      expect((await product())['quantity'], 0);
      expect((await firestore.collection('sales').get()).docs, hasLength(1));
    },
  );
}
