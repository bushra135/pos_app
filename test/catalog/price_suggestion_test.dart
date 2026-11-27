import '../support/product_form.dart';
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('price is cost plus markup, rounded up to 5 fils', () {
    expect(ProductsScreenPricing.priceFromCost(1.0, 25), 1.25);
    expect(ProductsScreenPricing.priceFromCost(2.4, 25), 3.0);
    expect(ProductsScreenPricing.priceFromCost(0.333, 20), 0.4); // 0.3996 → 0.400
    expect(ProductsScreenPricing.priceFromCost(0.5, 30), 0.65);
  });

  test('outside catalogues never invent a price', () async {
    final service = BarcodeCatalogService(
      generalFallback: true,
      client: MockClient((request) async {
        if (request.url.host == 'world.openfoodfacts.org') return http.Response('{}', 404);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'ean': '0012345678905',
                'title': 'Stapler',
                'category': 'Office > Staplers',
                'images': ['http://insecure.example/a.jpg', 'https://cdn.example/stapler.jpg'],
                'offers': [
                  {'price': 5.0},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final found = (await service.lookup('012345678905'))!;
    expect(found.imageUrl, 'https://cdn.example/stapler.jpg');
    expect(found.suggestedPrice, 0);
  });

  testWidgets('owner enters the invoice cost and the price follows the markup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A', 'role': 'owner'});
    final catalog = BarcodeCatalogService(
      generalFallback: false,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'success',
            'product': {
              'code': '87654321',
              'product_name': 'Cream cheese 24 pcs',
              'categories': 'Dairy',
            },
          }),
          200,
        ),
      ),
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
    await tester.enterText(find.widgetWithText(TextField, 'Barcode'), '87654321');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    TextEditingController field(String hint) =>
        tester.widget<TextField>(find.widgetWithText(TextField, hint)).controller!;
    expect(field('Product name').text, 'Cream cheese 24 pcs');
    expect(field('Price').text, isEmpty, reason: 'no guessed price');

    await tester.enterText(
      find.widgetWithText(TextField, 'Cost price (owner only, optional)'),
      '2.4',
    );
    await tester.pumpAndSettle();
    expect(field('Price').text, '3.000'); // default 25%
    expect(find.text('Cost 2.400 + 25% markup'), findsOneWidget);

    await tester.tap(find.text('30%'));
    await tester.pumpAndSettle();
    expect(field('Price').text, '3.120');
    expect((await SharedPreferences.getInstance()).getDouble('price_markup_percent'), 30);

    // A price typed by the owner is never overwritten by the markup.
    await tester.enterText(find.widgetWithText(TextField, 'Price'), '3.250');
    await tester.enterText(
      find.widgetWithText(TextField, 'Cost price (owner only, optional)'),
      '2.5',
    );
    await tester.pumpAndSettle();
    expect(field('Price').text, '3.250');
    expect(tester.takeException(), isNull);
  });
}
