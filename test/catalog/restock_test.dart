import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });

  Future<FakeFirebaseFirestore> seed() async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('cashier').set({
      'storeCode': 'A',
      'role': 'cashier',
      'isActive': true,
    });
    await db.collection('products').doc('notebook').set({
      'storeCode': 'A',
      'name': 'Notebook',
      'price': 1.75,
      'stock': 3,
      'minStock': 5,
      'barcode': '789',
      'image': '',
    });
    return db;
  }

  testWidgets('restock adds a box of units without opening the product editor', (tester) async {
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductsScreen(firestore: db, currentUserId: () => 'cashier'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Restock'));
    await tester.pumpAndSettle();
    expect(find.text('In stock now: 3'), findsOneWidget);
    await tester.tap(find.text('+12'));
    await tester.pumpAndSettle();
    expect(find.text('New stock: 15'), findsOneWidget);
    await tester.tap(find.text('Add to stock'));
    await tester.pumpAndSettle();

    final saved = (await db.collection('products').doc('notebook').get()).data()!;
    expect(saved['stock'], 15);
    expect(find.text('Edit product'), findsNothing);
    expect(find.textContaining('Notebook restocked: +12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restock can be cancelled and rejects empty amounts', (tester) async {
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductsScreen(firestore: db, currentUserId: () => 'cashier'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Restock'));
    await tester.pumpAndSettle();
    final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add to stock'));
    expect(add.onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await db.collection('products').doc('notebook').get()).data()!['stock'], 3);
    expect(tester.takeException(), isNull);
  });
}
