import 'package:cloud_firestore/cloud_firestore.dart';

class BackupSummary {
  const BackupSummary(this.id, this.createdAt, this.products, this.sales);
  final String id;
  final DateTime createdAt;
  final int products;
  final int sales;
}

class RestoreResult {
  const RestoreResult(this.products, this.sales);
  final int products;
  final int sales;
}

/// Store-scoped recovery copies. Existing records are never rolled backwards.
/// Server security rules must also enforce owner-only access to backup paths.
class BackupService {
  BackupService({
    required this.db,
    required this.currentUid,
    required this.hasPendingSales,
  });
  final FirebaseFirestore db;
  final String? Function() currentUid;
  final Future<bool> Function() hasPendingSales;
  static const _server = GetOptions(source: Source.server);
  static const _settings = ['storeName', 'benefitNumber', 'benefitQrBase64'];

  Future<String> _requireStoreOwner(String storeCode) async {
    final uid = currentUid();
    if (uid == null || storeCode.isEmpty) {
      throw StateError('Sign in as the store owner.');
    }
    final profile = await db.collection('users').doc(uid).get(_server);
    if (profile.data()?['role']?.toString().toLowerCase() != 'owner' ||
        profile.data()?['storeCode'] != storeCode) {
      throw StateError('Only this store owner can manage backups.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _backupCollection(
    String storeCode,
  ) => db.collection('stores').doc(storeCode).collection('backups');

  Future<List<BackupSummary>> listBackups(String storeCode) async {
    await _requireStoreOwner(storeCode);
    final rows = await _backupCollection(
      storeCode,
    ).where('complete', isEqualTo: true).get(_server);
    final summaries = rows.docs
        .where(
          (row) =>
              row.data()['storeCode'] == storeCode &&
              row.data()['version'] == 1 &&
              row.data()['createdAt'] is Timestamp,
        )
        .map((row) {
          final data = row.data();
          return BackupSummary(
            row.id,
            (data['createdAt'] as Timestamp).toDate(),
            data['products'] as int,
            data['sales'] as int,
          );
        })
        .toList();
    summaries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return summaries;
  }

  Future<BackupSummary> createBackup(String storeCode) async {
    final uid = await _requireStoreOwner(storeCode);
    if (await hasPendingSales()) {
      throw StateError('Synchronize this device\'s pending sales first.');
    }
    final store = await db.collection('stores').doc(storeCode).get(_server);
    if (!store.exists) throw StateError('Store settings were not found.');
    final products = await db
        .collection('products')
        .where('storeCode', isEqualTo: storeCode)
        .get(_server);
    final sales = await db
        .collection('sales')
        .where('storeCode', isEqualTo: storeCode)
        .get(_server);
    final ref = _backupCollection(storeCode).doc();
    final now = DateTime.now();
    await ref.set({
      'storeCode': storeCode,
      'ownerUid': uid,
      'version': 1,
      'complete': false,
      'createdAt': Timestamp.fromDate(now),
      'products': products.docs.length,
      'sales': sales.docs.length,
      'settings': {
        for (final key in _settings)
          if (store.data()!.containsKey(key)) key: store.data()![key],
      },
    });
    // Copies remain invisible until every document has been acknowledged.
    for (final group in [products, sales]) {
      final collection = identical(group, products) ? 'products' : 'sales';
      for (var start = 0; start < group.docs.length; start += 100) {
        final batch = db.batch();
        for (final row in group.docs.skip(start).take(100)) {
          batch.set(ref.collection(collection).doc(row.id), row.data());
        }
        await batch.commit();
      }
    }
    await _requireStoreOwner(storeCode);
    if (await hasPendingSales()) {
      throw StateError(
        'Sales changed during backup. Retry after synchronization.',
      );
    }
    await ref.update({
      'complete': true,
      'completedAt': FieldValue.serverTimestamp(),
    });
    return BackupSummary(ref.id, now, products.docs.length, sales.docs.length);
  }

  Future<RestoreResult> restoreMissingRecords(
    String storeCode,
    String backupId, {
    bool restoreSettings = false,
  }) async {
    await _requireStoreOwner(storeCode);
    if (await hasPendingSales()) {
      throw StateError('Synchronize pending sales before restoring.');
    }
    final ref = _backupCollection(storeCode).doc(backupId);
    final manifest = (await ref.get(_server)).data();
    if (manifest == null ||
        manifest['complete'] != true ||
        manifest['version'] != 1 ||
        manifest['storeCode'] != storeCode) {
      throw StateError(
        'This backup is incomplete or belongs to another store.',
      );
    }
    final products = await ref.collection('products').get(_server);
    final sales = await ref.collection('sales').get(_server);
    if (products.docs.length != manifest['products'] ||
        sales.docs.length != manifest['sales']) {
      throw StateError('The backup is incomplete. No records were restored.');
    }
    for (final row in [...products.docs, ...sales.docs]) {
      if (row.data()['storeCode'] != storeCode) {
        throw StateError(
          'Invalid store data in backup. No records were restored.',
        );
      }
    }
    var recoveredProducts = 0;
    var recoveredSales = 0;
    for (final group in [products, sales]) {
      final isProduct = identical(group, products);
      for (final row in group.docs) {
        await _requireStoreOwner(storeCode);
        if (await hasPendingSales()) {
          throw StateError(
            'Restore stopped: pending sales detected. Completed records remain restored; retry safely after synchronization.',
          );
        }
        final target = db
            .collection(isProduct ? 'products' : 'sales')
            .doc(row.id);
        final inserted = await db.runTransaction<bool>((transaction) async {
          final existing = await transaction.get(target);
          if (existing.exists) return false;
          transaction.set(target, {
            ...row.data(),
            if (isProduct) ...{
              // Old stock cannot safely be replayed after subsequent sales.
              'stock': 0, 'quantity': 0, 'needsStockCount': true,
            },
          });
          return true;
        });
        if (inserted && isProduct) recoveredProducts++;
        if (inserted && !isProduct) recoveredSales++;
      }
    }
    if (restoreSettings) {
      await _requireStoreOwner(storeCode);
      final settings = Map<String, dynamic>.from(manifest['settings'] as Map);
      await db.collection('stores').doc(storeCode).set({
        for (final key in _settings)
          if (settings.containsKey(key)) key: settings[key],
      }, SetOptions(merge: true));
    }
    return RestoreResult(recoveredProducts, recoveredSales);
  }
}
