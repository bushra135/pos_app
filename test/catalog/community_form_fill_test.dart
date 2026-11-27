import '../support/product_form.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/community_catalog.dart';

void main() {
  testWidgets('a product shared by another store fills name, category and price, not stock', (
    tester,
  ) async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A', 'role': 'owner'});
    await db.collection('catalog').doc('6287017260083').set({
      'name': 'Al Rabie Juice',
      'category': 'Drinks',
      'price': 0.35,
      'contributedBy': 'ownerB',
    });
    final catalog = BarcodeCatalogService(
      community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
      client: MockClient((_) async => throw StateError('Internet catalogues are not needed')),
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
    await openProductDetails(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Barcode'), '6287017260083');
    await tester.ensureVisible(find.text('Find product info · free'));
    await tester.tap(find.text('Find product info · free'));
    await tester.pumpAndSettle();

    String field(String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;
    expect(field('Product name'), 'Al Rabie Juice');
    expect(field('Category'), 'Drinks');
    expect(field('Price'), '0.350');
    expect(find.textContaining('including a price another store uses'), findsOneWidget);
    expect(find.textContaining('ShopPad stores'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
