import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/owner/offers_screen.dart';

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('owner').set({'role': 'owner', 'storeCode': 'S'});
  for (final p in [('pen', 'Blue pen', 50, 0.5), ('ruler', 'Ruler 30 cm', 18, 0.4)]) {
    await db.collection('products').doc(p.$1).set({
      'storeCode': 'S',
      'name': p.$2,
      'category': 'Stationery',
      'stock': p.$3,
      'minStock': 5,
      'price': p.$4,
    });
  }
  await db.collection('productCosts').doc('ruler').set({'storeCode': 'S', 'cost': 0.3});
  final now = DateTime.now();
  for (var i = 0; i < 4; i++) {
    await db.collection('sales').doc('s$i').set({
      'storeCode': 'S',
      'type': 'sale',
      'total': 5.0,
      'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i + 1))),
      'items': [
        {'productId': 'pen', 'name': 'Blue pen', 'price': 0.5, 'quantity': 10},
      ],
    });
  }
  return db;
}

void main() {
  testWidgets('owner starts a suggested bundle offer and stops it', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await _seed();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OffersScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Buy Blue pen, get Ruler 30 cm'), findsOneWidget);
    expect(
      find.textContaining('have not sold in 30 days'),
      findsOneWidget,
      reason: 'clearance tip',
    );

    await tester.tap(find.text('Start offer'));
    await tester.pumpAndSettle();
    // Cost 0.300 on a 0.400 ruler: at most 25% keeps it above cost, so 30% is not offered.
    expect(find.text('30%'), findsNothing);
    await tester.tap(find.text('20%'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    final ruler = (await db.collection('products').doc('ruler').get()).data()!;
    expect(ruler['offerActive'], isTrue);
    expect(ruler['offerWithId'], 'pen');
    expect(ruler['offerPercent'], 20);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect((await db.collection('products').doc('ruler').get()).data()!['offerActive'], isFalse);
    expect(tester.takeException(), isNull);
  });
}
