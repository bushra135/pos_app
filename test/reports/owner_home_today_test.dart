import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';

void main() {
  testWidgets('owner home: best seller from real sales, refunds not counted as orders', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({
      'role': 'owner',
      'storeCode': 'S',
      'storeName': 'Shop',
      'fullName': 'Aisha',
    });
    await db.collection('stores').doc('S').set({'ownerUid': 'owner', 'storeName': 'Shop'});
    // No soldCount on the product: the tile must not depend on it.
    await db.collection('products').doc('p1').set({
      'storeCode': 'S',
      'name': 'Blue pen',
      'price': 0.5,
      'stock': 40,
      'minStock': 5,
    });
    final today = DateTime.now();
    Future<void> sale(
      String id,
      double total,
      List<Map<String, Object>> items, {
      bool refund = false,
    }) => db.collection('sales').doc(id).set({
      'storeCode': 'S',
      'cashierUid': 'c1',
      'total': total,
      'status': 'completed',
      'type': refund ? 'refund' : 'sale',
      'createdAt': Timestamp.fromDate(today),
      'items': items,
    });
    await sale('s1', 2.85, [
      {'productId': 'p1', 'name': 'Blue pen', 'quantity': 2, 'price': 0.5},
      {'productId': 'p2', 'name': 'Notebook A4', 'quantity': 1, 'price': 1.85},
    ]);
    await sale('s2', 1.98, [
      {'productId': 'p3', 'name': 'Orange juice', 'quantity': 1, 'price': 0.35},
      {'productId': 'p2', 'name': 'Notebook A4', 'quantity': 1, 'price': 1.85},
    ]);
    await sale('r1', -0.5, [
      {'productId': 'p1', 'name': 'Blue pen', 'quantity': 1, 'price': 0.5},
    ], refund: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OwnerHomeScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 orders · avg BD 2.165'), findsOneWidget);
    expect(find.text('BD 4.330'), findsOneWidget);
    expect(find.text('Notebook A4'), findsOneWidget);
    expect(find.text('2 sold today'), findsOneWidget);
    expect(find.text('No sales yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
