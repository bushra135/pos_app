import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/sale_sync_service.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:sembast/sembast_memory.dart';

/// Any server call fails, proving cache hits do not wait for Firestore.
class NoServerAccess implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected server access');
}

class UnusedSaleGateway implements SaleGateway {
  @override
  Future<void> commit(SaleRecord sale) async =>
      throw StateError('Scanning must not submit a sale');
}

void main() {
  test(
    'Warm catalogue scans avoid server access and still enforce cart stock',
    () async {
      final database = await databaseFactoryMemory.openDatabase('fast-scan');
      final store = LocalPosStore(database);
      final service = SaleSyncService(
        store: store,
        gateway: UnusedSaleGateway(),
        currentUserId: () => 'cashier',
        firestore: NoServerAccess(),
      );
      addTearDown(() async {
        service.dispose();
        CartManager.clearCart();
        await database.close();
      });
      await store.saveContext('cashier', {
        'storeCode': 'A',
        'role': 'cashier',
      }, {});
      await store.cacheProducts('A', [
        {
          'id': 'p1',
          'storeCode': 'A',
          'barcode': '123',
          'name': 'Tea',
          'price': 1.5,
          'stock': 1,
        },
      ]);
      service.online = true;
      final product = await service.findProduct('123', preferCache: true);
      expect(product['name'], 'Tea');
      expect(service.online, isTrue);
      CartManager.addItem(
        name: 'Tea',
        price: 1.5,
        barcode: '123',
        image: '',
        productId: 'p1',
        storeCode: 'A',
      );
      await expectLater(
        service.findProduct('123', preferCache: true),
        throwsStateError,
      );
    },
  );

  test(
    'Warm catalogue lookup subtracts durable pending stock reservations',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'fast-scan-reservations',
      );
      final store = LocalPosStore(database);
      final service = SaleSyncService(
        store: store,
        gateway: UnusedSaleGateway(),
        currentUserId: () => 'cashier',
        firestore: NoServerAccess(),
      );
      addTearDown(() async {
        service.dispose();
        CartManager.clearCart();
        await database.close();
      });
      CartManager.clearCart();
      await store.saveContext('cashier', {'storeCode': 'A'}, {});
      await store.cacheProducts('A', [
        {
          'id': 'p1',
          'storeCode': 'A',
          'barcode': '123',
          'name': 'Tea',
          'price': 1.5,
          'stock': 1,
        },
      ]);
      await store.enqueueChecked(
        SaleRecord(
          id: 'paid',
          storeCode: 'A',
          storeName: 'Shop',
          cashierUid: 'cashier',
          cashierName: 'Cashier',
          paymentMethod: 'Cash',
          createdAt: DateTime.now(),
          items: [
            const SaleLine(
              productId: 'p1',
              barcode: '123',
              name: 'Tea',
              price: 1.5,
              quantity: 1,
            ),
          ],
        ),
      );
      service.online = true;
      await expectLater(
        service.findProduct('123', preferCache: true),
        throwsStateError,
      );
    },
  );
}
