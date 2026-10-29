import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/services/backup_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late BackupService service;
  var pending = false;
  String? uid = 'owner';

  setUp(() async {
    db = FakeFirebaseFirestore();
    pending = false;
    uid = 'owner';
    service = BackupService(
      db: db,
      currentUid: () => uid,
      hasPendingSales: () async => pending,
    );
    await db.doc('users/owner').set({'role': 'owner', 'storeCode': 'A'});
    await db.doc('stores/A').set({
      'storeName': 'Original',
      'benefitNumber': '123',
      'ownerUid': 'owner',
    });
    await db.doc('products/p1').set({
      'storeCode': 'A',
      'barcode': '123',
      'name': 'Tea',
      'stock': 8,
      'price': 1.5,
    });
    await db.doc('products/other').set({'storeCode': 'B', 'stock': 20});
    await db.doc('sales/s1').set({
      'storeCode': 'A',
      'total': 3,
      'receiptNumber': 'RCPT-s1',
    });
  });

  test(
    'Completed cloud copy includes only this store, and survives a new service instance',
    () async {
      final backup = await service.createBackup('A');
      expect(backup.products, 1);
      expect(backup.sales, 1);
      final reopened = BackupService(
        db: db,
        currentUid: () => uid,
        hasPendingSales: () async => false,
      );
      expect((await reopened.listBackups('A')).single.id, backup.id);
      expect(
        (await db.collection('stores/A/backups/${backup.id}/products').get())
            .docs
            .single
            .id,
        'p1',
      );
    },
  );

  test(
    'Recovery is repeatable, preserves newer records and never replays stock deductions',
    () async {
      final backup = await service.createBackup('A');
      await db.doc('products/p1').update({'stock': 4});
      await db.doc('sales/s1').delete();
      final result = await service.restoreMissingRecords('A', backup.id);
      expect(result.products, 0);
      expect(result.sales, 1);
      expect((await db.doc('products/p1').get()).data()!['stock'], 4);
      expect(
        (await db.doc('sales/s1').get()).data()!['receiptNumber'],
        'RCPT-s1',
      );
      final retried = await service.restoreMissingRecords('A', backup.id);
      expect(retried.products + retried.sales, 0);
    },
  );

  test(
    'Missing product is recovered at zero stock with a count flag; settings are opt in',
    () async {
      final backup = await service.createBackup('A');
      await db.doc('products/p1').delete();
      await db.doc('stores/A').update({
        'storeName': 'New',
        'benefitNumber': '999',
      });
      await service.restoreMissingRecords('A', backup.id);
      final product = (await db.doc('products/p1').get()).data()!;
      expect(product['stock'], 0);
      expect(product['needsStockCount'], true);
      expect((await db.doc('stores/A').get()).data()!['storeName'], 'New');
      await service.restoreMissingRecords(
        'A',
        backup.id,
        restoreSettings: true,
      );
      final store = (await db.doc('stores/A').get()).data()!;
      expect(store['storeName'], 'Original');
      expect(store['benefitNumber'], '123');
      expect(store['ownerUid'], 'owner');
    },
  );

  test('Pending sales block backup and restoration', () async {
    final backup = await service.createBackup('A');
    pending = true;
    await expectLater(service.createBackup('A'), throwsStateError);
    await expectLater(
      service.restoreMissingRecords('A', backup.id),
      throwsStateError,
    );
  });

  test(
    'Wrong store, cashier and signed out sessions cannot manage backups',
    () async {
      await expectLater(service.createBackup('B'), throwsStateError);
      await db.doc('users/owner').update({'role': 'cashier'});
      await expectLater(service.listBackups('A'), throwsStateError);
      uid = null;
      await expectLater(service.createBackup('A'), throwsStateError);
    },
  );

  test(
    'Incomplete or cross-store content is rejected before any restore writes',
    () async {
      final backup = await service.createBackup('A');
      await db.doc('products/p1').delete();
      final parent = db.doc('stores/A/backups/${backup.id}');
      await parent.update({'complete': false});
      expect(await service.listBackups('A'), isEmpty);
      await expectLater(
        service.restoreMissingRecords('A', backup.id),
        throwsStateError,
      );
      await parent.update({'complete': true});
      await db.doc('stores/A/backups/${backup.id}/products/p1').update({
        'storeCode': 'B',
      });
      await expectLater(
        service.restoreMissingRecords('A', backup.id),
        throwsStateError,
      );
      expect((await db.doc('products/p1').get()).exists, false);
    },
  );

  test(
    'More than one write batch preserves every product before marking complete',
    () async {
      for (var i = 0; i < 110; i++) {
        await db.doc('products/bulk-$i').set({'storeCode': 'A', 'stock': 1});
      }
      final backup = await service.createBackup('A');
      expect(backup.products, 111);
      expect((await service.listBackups('A')).single.products, 111);
      expect(
        (await db.collection('stores/A/backups/${backup.id}/products').get())
            .docs
            .length,
        111,
      );
    },
  );
}
