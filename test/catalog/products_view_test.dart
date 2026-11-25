import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:http/testing.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/community_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });

  testWidgets('owner switches products between list and grid, and the choice is kept', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A', 'role': 'owner'});
    for (final name in ['Pen', 'Notebook', 'Glue']) {
      await db.collection('products').doc(name).set({
        'storeCode': 'A',
        'name': name,
        'price': 1.0,
        'stock': 10,
        'minStock': 2,
        'barcode': name,
        'image': '',
      });
    }
    Widget app() => MaterialApp(
      theme: AppTheme.light,
      home: ProductsScreen(firestore: db, currentUserId: () => 'owner'),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);

    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byTooltip('Restock'), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    // Reopening the screen keeps the grid.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('products_view'), isFalse);
  });

  testWidgets('long press offers delete without opening the editor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A', 'role': 'owner'});
    await db.collection('products').doc('pen').set({
      'storeCode': 'A',
      'name': 'Pen',
      'price': 1.0,
      'stock': 4,
      'barcode': '111',
      'image': '',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductsScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Pen'));
    await tester.pumpAndSettle();
    expect(find.text('Restock'), findsOneWidget);
    await tester.tap(find.text('Delete product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect((await db.collection('products').doc('pen').get()).exists, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a typed barcode fills name, category, image and price by itself', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A', 'role': 'owner'});
    await db.collection('catalog').doc('6281234567890').set({
      'name': 'Saudi Water',
      'category': 'Drinks',
      'price': 0.1,
      'image':
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    });
    final catalog = BarcodeCatalogService(
      community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
      client: MockClient((_) async => throw StateError('not needed')),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductsScreen(firestore: db, currentUserId: () => 'owner', catalog: catalog),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Barcode'), '6281234567890');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    String field(String hint) =>
        tester.widget<TextField>(find.widgetWithText(TextField, hint)).controller!.text;
    expect(field('Product name'), 'Saudi Water');
    expect(field('Category'), 'Drinks');
    expect(field('Price'), '0.100');
    expect(find.textContaining('Product found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
