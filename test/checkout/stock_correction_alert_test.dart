import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });

  testWidgets('owner sees miscounted sales and can mark them reviewed', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({
      'role': 'owner',
      'storeCode': 'A',
      'storeName': 'Test Store',
      'fullName': 'Owner',
    });
    await db.collection('stores').doc('A').set({'ownerUid': 'owner', 'storeName': 'Test Store'});
    await db.collection('products').doc('notebook').set({
      'storeCode': 'A',
      'name': 'Notebook',
      'price': 1.75,
      'stock': 0,
      'minStock': 5,
      'lastStockCorrection': {
        'name': 'Notebook',
        'stockBefore': 0,
        'quantitySold': 2,
        'addedQuantity': 2,
        'saleId': 'sale-1',
      },
    });
    await db.collection('products').doc('pen').set({
      'storeCode': 'A',
      'name': 'Pen',
      'price': 0.5,
      'stock': 10,
      'lastStockCorrection': {'stockBefore': 0, 'quantitySold': 1, 'reviewed': true},
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: OwnerHomeScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 stock count was corrected'), findsOneWidget);
    expect(find.text('Notebook: records showed 0, cashier sold 2'), findsOneWidget);
    expect(find.textContaining('Pen: records showed'), findsNothing);

    await tester.tap(find.text('Mark as reviewed'));
    await tester.pumpAndSettle();

    final saved = (await db.collection('products').doc('notebook').get()).data()!;
    expect((saved['lastStockCorrection'] as Map)['reviewed'], isTrue);
    expect((saved['lastStockCorrection'] as Map)['saleId'], 'sale-1');
    expect(find.text('1 stock count was corrected'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
