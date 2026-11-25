import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';

void main() {
  testWidgets('the bell counts low stock and lists it, out of stock first', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'role': 'owner', 'storeCode': 'A'});
    await db.collection('stores').doc('A').set({'ownerUid': 'owner', 'storeName': 'Test'});
    for (final p in [('pen', 'Blue pen', 40), ('book', 'Notebook', 2), ('juice', 'Juice', 0)]) {
      await db.collection('products').doc(p.$1).set({
        'storeCode': 'A',
        'name': p.$2,
        'price': 1.0,
        'stock': p.$3,
        'minStock': 5,
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OwnerHomeScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();

    // Once per session: a notice with a View action.
    expect(find.text('2 products are low on stock'), findsOneWidget);
    final bell = find.byTooltip('Low stock alerts');
    expect(find.descendant(of: bell, matching: find.text('2')), findsOneWidget);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    final juice = tester.getTopLeft(find.text('Juice'));
    final book = tester.getTopLeft(find.text('Notebook'));
    expect(juice.dy, lessThan(book.dy), reason: 'out of stock listed first');
    expect(find.text('Out of stock · minimum 5'), findsOneWidget);
    expect(find.text('2 left · minimum 5'), findsOneWidget);
    expect(find.text('Blue pen'), findsNothing);
    expect(find.text('Open products to restock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
