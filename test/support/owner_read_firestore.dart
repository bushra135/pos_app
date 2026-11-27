import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

/// Holds individual Firestore reads so tests inspect every initialization phase.
class OwnerReadFirestore extends FakeFirebaseFirestore {
  Future<void> Function(String path, GetOptions? options)? beforeRead;
  bool fromCache = false;
  bool emptyCachedQueries = false;
  final reads = <String>[];
  CollectionReference<Map<String, dynamic>> seed(String path) => super.collection(path);
  Future<void> read(String path, GetOptions? options) async {
    reads.add(path);
    await beforeRead?.call(path, options);
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(super.collection(path), this, path);
}

class _Metadata implements SnapshotMetadata {
  _Metadata(this.isFromCache);
  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK sealed interfaces are implemented only by these controlled test doubles.
// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.inner, this.db);
  final DocumentReference<Map<String, dynamic>> inner;
  final OwnerReadFirestore db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    await db.read(inner.path, options);
    return _DocumentSnapshot(await inner.get(options), db.fromCache);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK sealed interfaces are implemented only by these controlled test doubles.
// ignore: subtype_of_sealed_class
class _DocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _DocumentSnapshot(this.inner, bool cached) : metadata = _Metadata(cached);
  final DocumentSnapshot<Map<String, dynamic>> inner;
  @override
  final SnapshotMetadata metadata;
  @override
  bool get exists => inner.exists;
  @override
  Map<String, dynamic>? data() => inner.data();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK sealed interfaces are implemented only by these controlled test doubles.
// ignore: subtype_of_sealed_class
class _Query implements Query<Map<String, dynamic>> {
  _Query(this.inner, this.db, this.path);
  final Query<Map<String, dynamic>> inner;
  final OwnerReadFirestore db;
  final String path;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    await db.read(path, options);
    return _QuerySnapshot(
      await inner.get(options),
      db.fromCache,
      db.fromCache && db.emptyCachedQueries,
    );
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _Query(
    inner.where(
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    ),
    db,
    path,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK sealed interfaces are implemented only by these controlled test doubles.
// ignore: subtype_of_sealed_class
class _Collection extends _Query implements CollectionReference<Map<String, dynamic>> {
  _Collection(CollectionReference<Map<String, dynamic>> super.inner, super.db, super.path);
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document((inner as CollectionReference<Map<String, dynamic>>).doc(path), db);
}

class _QuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.inner, bool cached, this.empty) : metadata = _Metadata(cached);
  final QuerySnapshot<Map<String, dynamic>> inner;
  final bool empty;
  @override
  final SnapshotMetadata metadata;
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => empty ? [] : inner.docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
