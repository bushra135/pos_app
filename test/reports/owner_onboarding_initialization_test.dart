import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';
import '../support/owner_read_firestore.dart';

Future<OwnerReadFirestore> configuredStore() async {
  final db = OwnerReadFirestore();
  await db.seed('users').doc('owner').set({
    'role': 'owner',
    'storeCode': 'READY',
    'fullName': 'Owner',
  });
  await db.seed('stores').doc('READY').set({
    'ownerUid': 'owner',
    'storeCode': 'READY',
    'storeName': 'Ready store',
    'benefitNumber': '33000000',
    'vatRegistered': false,
  });
  await db.seed('products').doc('p').set({
    'storeCode': 'READY',
    'name': 'Pen',
    'stock': 20,
    'minStock': 1,
    'price': 1,
  });
  await db.seed('users').doc('cashier').set({
    'role': 'cashier',
    'storeCode': 'READY',
    'status': 'invited',
    'isActive': false,
  });
  return db;
}

Widget app(OwnerReadFirestore db, {String? Function()? uid}) => MaterialApp(
  theme: AppTheme.light,
  home: OwnerHomeScreen(firestore: db, currentUserId: uid ?? () => 'owner'),
);
void noChecklist(WidgetTester tester) =>
    expect(find.text('Get your store ready', skipOffstage: false), findsNothing);
void main() {
  testWidgets('configured store never renders checklist while dashboard reads are pending', (
    tester,
  ) async {
    final db = await configuredStore();
    final gate = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'stores/READY') await gate.future;
    };
    await tester.pumpWidget(app(db));
    await tester.pump();
    expect(db.reads, contains('stores/READY'));
    noChecklist(tester);
    gate.complete();
    await tester.pumpAndSettle();
    noChecklist(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('five cold widget mounts never render checklist in any loading phase', (
    tester,
  ) async {
    final db = await configuredStore();
    for (var start = 0; start < 5; start++) {
      final gates = {
        for (final path in ['users/owner', 'stores/READY', 'users', 'products', 'sales'])
          path: Completer<void>(),
      };
      db.beforeRead = (path, _) async {
        await gates[path]?.future;
      };
      await tester.pumpWidget(app(db));
      noChecklist(tester);
      for (final path in gates.keys) {
        gates[path]!.complete();
        await tester.pump();
        await tester.pump();
        noChecklist(tester);
      }
      await tester.pumpAndSettle();
      noChecklist(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('new store checklist appears only after confirmed setup reads, before sales finish', (
    tester,
  ) async {
    final db = OwnerReadFirestore();
    await db.seed('users').doc('owner').set({
      'role': 'owner',
      'storeCode': 'NEW',
      'fullName': 'Owner',
    });
    await db.seed('stores').doc('NEW').set({'ownerUid': 'owner', 'storeCode': 'NEW'});
    final products = Completer<void>(), sales = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'products') await products.future;
      if (path == 'sales') await sales.future;
    };
    await tester.pumpWidget(app(db));
    await tester.pump();
    noChecklist(tester);
    products.complete();
    await tester.pumpAndSettle();
    expect(find.text('Get your store ready'), findsOneWidget);
    expect(find.text('4 steps left'), findsOneWidget);
    sales.complete();
    await tester.pumpAndSettle();
    expect(find.text('Get your store ready'), findsOneWidget);
  });
  testWidgets('stale cache with empty counts is unknown, not incomplete', (tester) async {
    final db = await configuredStore();
    db.fromCache = true;
    db.emptyCachedQueries = true;
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    noChecklist(tester);
    db.fromCache = false;
    db.emptyCachedQueries = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    noChecklist(tester);
    expect(db.reads.where((p) => p == 'stores/READY'), hasLength(2));
  });
  testWidgets('failed or missing store reads never create an incomplete checklist', (tester) async {
    final db = await configuredStore();
    db.beforeRead = (path, _) async {
      if (path == 'stores/READY') throw StateError('offline');
    };
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    noChecklist(tester);
    await tester.pumpWidget(const SizedBox());
    db.beforeRead = null;
    await db.seed('stores').doc('READY').delete();
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    noChecklist(tester);
  });
  testWidgets('late reads from a previous account cannot replace current store readiness', (
    tester,
  ) async {
    final db = await configuredStore();
    await db.seed('users').doc('new-owner').set({
      'role': 'owner',
      'storeCode': 'NEW',
      'fullName': 'New',
    });
    await db.seed('stores').doc('NEW').set({'ownerUid': 'new-owner', 'storeCode': 'NEW'});
    final ready = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'stores/READY') await ready.future;
    };
    var uid = 'owner';
    await tester.pumpWidget(app(db, uid: () => uid));
    await tester.pump();
    noChecklist(tester);
    uid = 'new-owner';
    await tester.pumpWidget(app(db, uid: () => uid));
    await tester.pumpAndSettle();
    expect(find.text('4 steps left'), findsOneWidget);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('4 steps left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile storeCode is the lookup key, never uid or a stale store name', (
    tester,
  ) async {
    final db = await configuredStore();
    await db.seed('stores').doc('owner').set({'storeName': 'Wrong store'});
    await db.seed('users').doc('owner').update({'storeName': 'Stale profile name'});
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
    noChecklist(tester);
    expect(db.reads, contains('stores/READY'));
    expect(db.reads, isNot(contains('stores/owner')));
  });
}
