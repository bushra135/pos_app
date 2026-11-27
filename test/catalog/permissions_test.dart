import '../support/product_form.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/product_costs.dart';
import 'package:pos_app/services/stock_moves.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });

  Future<FakeFirebaseFirestore> seed(Map<String, dynamic> user) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('me').set({'storeCode': 'A', 'isActive': true, ...user});
    await db.collection('products').doc('notebook').set({
      'storeCode': 'A',
      'name': 'Notebook',
      'category': 'Stationery',
      'price': 1.75,
      'stock': 3,
      'minStock': 5,
      'barcode': '789',
      'image': '',
    });
    return db;
  }

  Future<void> open(WidgetTester tester, FakeFirebaseFirestore db) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductsScreen(firestore: db, currentUserId: () => 'me'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cashier without permissions can only view products', (tester) async {
    final db = await seed({'role': 'cashier'});
    await open(tester, db);
    expect(find.byTooltip('Restock'), findsNothing);
    expect(find.text('Add'), findsNothing, reason: 'only owners add products');

    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();
    await openProductDetails(tester);
    expect(find.textContaining('View only'), findsOneWidget);
    expect(find.byTooltip('Delete product'), findsNothing);
    final price = tester.widget<TextField>(find.widgetWithText(TextField, 'Price'));
    expect(price.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cashier allowed to adjust stock restocks, and the move is recorded', (
    tester,
  ) async {
    final db = await seed({'role': 'cashier', 'fullName': 'Noora', 'canAdjustStock': true});
    await open(tester, db);
    await tester.tap(find.byTooltip('Restock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to stock'));
    await tester.pumpAndSettle();

    final product = (await db.collection('products').doc('notebook').get()).data()!;
    expect(product['stock'], 15);
    final moves = await db.collection(StockMoves.collection).get();
    expect(moves.docs, hasLength(1));
    final move = moves.docs.single.data();
    expect(move, containsPair('before', 3));
    expect(move, containsPair('after', 15));
    expect(move, containsPair('delta', 12));
    expect(move, containsPair('reason', 'restock'));
    expect(move, containsPair('byUid', 'me'));
    expect(move, containsPair('byName', 'Noora'));
    expect(product['lastStockMoveId'], moves.docs.single.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner cost prices are kept apart from products', (tester) async {
    final db = await seed({'role': 'owner'});
    // A product saved by an older version still carries its cost.
    await db.collection('products').doc('legacy').set({
      'storeCode': 'A',
      'name': 'Glue',
      'price': 2.0,
      'cost': 1.2,
      'stock': 4,
      'barcode': '111',
    });
    await open(tester, db);
    await tester.pumpAndSettle();

    final legacy = (await db.collection('products').doc('legacy').get()).data()!;
    expect(legacy.containsKey('cost'), isFalse, reason: 'cost moved off the product');
    expect((await db.collection(ProductCosts.collection).doc('legacy').get()).data(), {
      'storeCode': 'A',
      'cost': 1.2,
      'updatedAt': isNotNull,
    });

    // Saving a cost in the editor writes the owner-only document, not the product.
    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();
    await openProductDetails(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cost price (owner only, optional)'),
      '1.1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final notebook = (await db.collection('products').doc('notebook').get()).data()!;
    expect(notebook.containsKey('cost'), isFalse);
    expect(
      (await db.collection(ProductCosts.collection).doc('notebook').get()).data()!['cost'],
      1.1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a product also removes its owner-only cost', (tester) async {
    final db = await seed({'role': 'owner'});
    await ProductCosts.save(db, productId: 'notebook', storeCode: 'A', cost: 1.1);
    await open(tester, db);
    await tester.tap(find.text('Notebook'));
    await tester.pumpAndSettle();
    await openProductDetails(tester);
    await tester.tap(find.byTooltip('Delete product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect((await db.collection('products').doc('notebook').get()).exists, isFalse);
    expect((await db.collection(ProductCosts.collection).doc('notebook').get()).exists, isFalse);
    expect(tester.takeException(), isNull);
  });
}
