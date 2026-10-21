import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// The package fake does not retry transactions. This test-only adapter buffers
/// writes and retries when another transaction changes a document it read.
/// It models optimistic concurrency; it is not a Firebase emulator.
class OptimisticFirestore extends FakeFirebaseFirestore {
  final _versions = <String, int>{};
  Future<void> _commitTail = Future.value();
  int retryCount = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final transaction = _BufferedTransaction(this);
      final result = await transactionHandler(transaction);
      final previous = _commitTail;
      final release = Completer<void>();
      _commitTail = release.future;
      await previous;
      try {
        final unchanged = transaction.readVersions.entries.every(
          (read) => (_versions[read.key] ?? 0) == read.value,
        );
        if (!unchanged) {
          retryCount++;
          continue;
        }
        for (final write in transaction.writes) {
          await write();
        }
        for (final path in transaction.writtenPaths) {
          _versions.update(path, (version) => version + 1, ifAbsent: () => 1);
        }
        return result;
      } finally {
        release.complete();
      }
    }
    throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted');
  }
}

class _BufferedTransaction implements Transaction {
  _BufferedTransaction(this.firestore);
  final OptimisticFirestore firestore;
  final readVersions = <String, int>{};
  final writtenPaths = <String>{};
  final writes = <Future<void> Function()>[];

  @override
  Future<DocumentSnapshot<T>> get<T>(DocumentReference<T> documentReference) {
    if (writes.isNotEmpty) {
      throw StateError('All transaction reads must precede all writes.');
    }
    readVersions.putIfAbsent(
      documentReference.path,
      () => firestore._versions[documentReference.path] ?? 0,
    );
    return documentReference.get();
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    writtenPaths.add(documentReference.path);
    writes.add(() => documentReference.set(data, options));
    return this;
  }

  @override
  Transaction update(
    DocumentReference documentReference,
    Map<String, dynamic> data,
  ) {
    writtenPaths.add(documentReference.path);
    writes.add(() => documentReference.update(data));
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
