import 'dart:convert';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/app/app_language.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/unknown_products.dart';
import 'package:pos_app/services/product_barcodes.dart';
import 'package:pos_app/widgets/identified_product_view.dart';
import '../support/optimistic_firestore.dart';

const identified = CatalogProduct(
  barcode: '12345678',
  name: 'Notebook',
  imageUrl: '',
  category: 'Stationery',
  productType: CatalogProduct.communityType,
  suggestedPrice: 0.7,
  brand: 'School',
  size: 'A5',
  description: 'Ruled notebook',
);
SaleRecord quoteSale({double price = 0.7, int quantity = 2, bool mixed = false}) => SaleRecord(
  id: 'quote-receipt',
  storeCode: 'A',
  storeName: 'Demo',
  cashierUid: 'cashierA',
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime(2026, 11, 26),
  items: [
    SaleLine(
      productId: 'unknown_A_12345678',
      barcode: '12345678',
      name: 'Notebook',
      price: price,
      quantity: quantity,
    ),
    if (mixed)
      const SaleLine(productId: 'normal', barcode: '456', name: 'Pen', price: 1, quantity: 1),
  ],
);
void main() {
  test('Open Facts normalized EAN preserves the requested UPC barcode identity', () async {
    final service = BarcodeCatalogService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 'success_with_warnings',
            'product': {'code': '0036000291452', 'product_name': 'Product', 'product_type': 'food'},
          }),
          200,
        ),
      ),
    );
    final result = (await service.lookup('036000291452'))!;
    expect(result.barcode, '036000291452');
    expect(result.name, 'Product');
  });

  test('simultaneous saves cannot claim the same barcode twice', () async {
    final db = OptimisticFirestore();
    final data = <String, dynamic>{
      'storeCode': 'A',
      'barcode': '99999999',
      'name': 'Book',
      'price': 1,
      'stock': 2,
    };
    Future<bool> attempt(String id) async {
      try {
        await ProductBarcodes.save(db, db.collection('products').doc(id), data, create: true);
        return true;
      } on StateError {
        return false;
      }
    }

    final results = await Future.wait([attempt('one'), attempt('two')]);
    expect(results.where((v) => v), hasLength(1));
    expect((await db.collection('products').get()).docs, hasLength(1));
  });

  test('barcode claims serialize competing product creation and permit edits', () async {
    final db = OptimisticFirestore();
    final p1 = db.collection('products').doc('one');
    final p2 = db.collection('products').doc('two');
    final data = <String, dynamic>{
      'storeCode': 'A',
      'barcode': '12345678',
      'name': 'Book',
      'price': 1,
      'stock': 2,
    };
    await ProductBarcodes.save(db, p1, data, create: true);
    await expectLater(ProductBarcodes.save(db, p2, data, create: true), throwsStateError);
    await ProductBarcodes.save(db, p1, {...data, 'barcode': '87654321'});
    expect((await ProductBarcodes.claim(db, 'A', '12345678').get()).exists, isFalse);
    expect((await ProductBarcodes.claim(db, 'A', '87654321').get()).data()?['productId'], 'one');
    expect((await db.collection('products').get()).docs, hasLength(1));
  });

  test('policy defaults off and never accepts public offers or non-finite prices', () {
    expect(const UnknownItemPolicy().sellablePrice(identified), isNull);
    const enabled = UnknownItemPolicy(sharedPriceSales: true, maxPrice: 1);
    expect(enabled.sellablePrice(identified), 0.7);
    expect(
      const UnknownItemPolicy(sharedPriceSales: true, maxPrice: 0.6).sellablePrice(identified),
      isNull,
    );
    expect(
      enabled.sellablePrice(
        const CatalogProduct(
          barcode: '12345678',
          name: 'Book',
          imageUrl: '',
          category: '',
          suggestedPrice: 0.5,
        ),
      ),
      isNull,
    );
    expect(
      enabled.sellablePrice(
        const CatalogProduct(
          barcode: '12345678',
          name: 'Book',
          imageUrl: '',
          category: '',
          productType: CatalogProduct.communityType,
          suggestedPrice: double.nan,
        ),
      ),
      isNull,
    );
  });
  test('cashier request preserves metadata and writes no inventory', () async {
    final db = FakeFirebaseFirestore();
    final service = UnknownProducts(db);
    expect(
      await service.requestApproval(
        storeCode: 'A',
        uid: 'cashierA',
        requestedByName: 'Cashier',
        barcode: identified.barcode,
        product: identified,
      ),
      isTrue,
    );
    final request = (await db.collection('productRequests').doc('A_12345678').get()).data()!;
    expect(request['brand'], 'School');
    expect(request['description'], 'Ruled notebook');
    expect((await db.collection('products').get()).docs, isEmpty);
  });
  test('owner approval is atomic and rejects a second product for the barcode', () async {
    final db = FakeFirebaseFirestore();
    final service = UnknownProducts(db);
    await service.requestApproval(
      storeCode: 'A',
      uid: 'cashierA',
      requestedByName: 'Cashier',
      barcode: identified.barcode,
      product: identified,
    );
    final request = ProductRequest.fromDoc(
      'A_12345678',
      (await db.collection('productRequests').doc('A_12345678').get()).data()!,
    );
    await service.addAsOwner(
      storeCode: 'A',
      barcode: identified.barcode,
      name: 'Owner notebook',
      price: 1,
      stock: 5,
      request: request,
    );
    final stored = (await db.collection('products').doc('A_12345678').get()).data()!;
    expect(stored['name'], 'Owner notebook');
    expect(stored['price'], 1);
    expect(stored['stock'], 5);
    expect(stored['brand'], 'School');
    expect((await db.collection('productRequests').get()).docs, isEmpty);
    await expectLater(
      service.addAsOwner(
        storeCode: 'A',
        barcode: identified.barcode,
        name: 'Duplicate',
        price: 2,
        stock: 1,
      ),
      throwsStateError,
    );
    expect((await db.collection('products').get()).docs, hasLength(1));
  });
  test('authorized quote and checkout never create inventory; retry is idempotent', () async {
    final db = OptimisticFirestore();
    final service = UnknownProducts(db);
    await db.collection('users').doc('cashierA').set({
      'storeCode': 'A',
      'role': 'cashier',
      'isActive': true,
    });
    await db.collection('stores').doc('A').set({'sharedPriceSales': true, 'sharedPriceMax': 1});
    await db.collection('catalog').doc('12345678').set({'price': 0.7, 'contributedBy': 'store'});
    final quote = await service.registerAtSharedPrice(
      storeCode: 'A',
      uid: 'cashierA',
      product: identified,
      price: 0.7,
    );
    expect(quote['id'], 'unknown_A_12345678');
    expect((await db.collection('products').get()).docs, isEmpty);
    final gateway = FirestoreSaleGateway(firestore: db, currentUserId: () => 'cashierA');
    await gateway.commit(quoteSale());
    await gateway.commit(quoteSale());
    expect((await db.collection('sales').get()).docs, hasLength(1));
    final sale = (await db.collection('sales').doc('quote-receipt').get()).data()!;
    expect(sale['total'], 1.4);
    expect(sale['unknownBarcode'], '12345678');
    expect((await db.collection('products').get()).docs, isEmpty);
  });
  test('policy revocation, price manipulation and mixed receipts fail before writing', () async {
    final db = OptimisticFirestore();
    await db.collection('users').doc('cashierA').set({'storeCode': 'A', 'role': 'cashier'});
    await db.collection('stores').doc('A').set({'sharedPriceSales': true, 'sharedPriceMax': 1});
    await db.collection('catalog').doc('12345678').set({'price': 0.7});
    final gateway = FirestoreSaleGateway(firestore: db, currentUserId: () => 'cashierA');
    await expectLater(gateway.commit(quoteSale(price: 0.1)), throwsA(isA<SaleConflictException>()));
    await expectLater(
      gateway.commit(quoteSale(mixed: true)),
      throwsA(isA<SaleConflictException>()),
    );
    await db.collection('stores').doc('A').update({'sharedPriceSales': false});
    await expectLater(gateway.commit(quoteSale()), throwsA(isA<SaleConflictException>()));
    expect((await db.collection('sales').get()).docs, isEmpty);
  });
  for (final type in ['food', 'beauty', 'product', 'petfood']) {
    test('$type lookup preserves all metadata without inventing selling prices', () async {
      final service = BarcodeCatalogService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'product': {
                'code': '12345678',
                'product_type': type,
                'product_name': 'Product $type',
                'brands': 'Brand',
                'quantity': '500 ml',
                'generic_name': 'Description',
                'categories': 'Category',
              },
            }),
            200,
          ),
        ),
      );
      final product = (await service.lookup('12345678'))!;
      expect(product.brand, 'Brand');
      expect(product.size, '500 ml');
      expect(product.description, 'Description');
      expect(product.productType, type);
      expect(product.suggestedPrice, 0);
    });
  }
  test('UPCitemdb source offer keeps currency and never becomes a selling price', () async {
    final service = BarcodeCatalogService(
      generalFallback: true,
      client: MockClient((request) async {
        if (request.url.host == 'world.openfoodfacts.org') return http.Response('{}', 404);
        return http.Response(
          jsonEncode({
            'items': [
              {
                'upc': '12345678',
                'title': 'Notebook',
                'brand': 'School',
                'size': 'A5',
                'description': 'Paper',
                'category': 'Office > Stationery',
                'offers': [
                  {'price': 2.49, 'currency': 'USD'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final product = (await service.lookup('12345678'))!;
    expect(product.provider, 'UPCitemdb');
    expect(product.category, 'Stationery');
    expect(product.referencePrice, 2.49);
    expect(product.referenceCurrency, 'USD');
    expect(product.suggestedPrice, 0);
    final restored = CatalogProduct.fromJson(product.toJson())!;
    expect(restored.referenceCurrency, 'USD');
    expect(restored.referencePrice, 2.49);
  });
  for (final locale in [AppLanguage.english, AppLanguage.arabic]) {
    testWidgets('identified product information is usable in ${locale.languageCode} at 320px', (
      tester,
    ) async {
      AppLanguage.locale.value = locale;
      addTearDown(() => AppLanguage.locale.value = AppLanguage.english);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Directionality(
            textDirection: locale == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: IdentifiedProductView(product: identified),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('Ruled notebook'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (locale == AppLanguage.arabic) {
        expect(find.textContaining('السعر المرجعي المشترك'), findsOneWidget);
      }
    });
  }
}
