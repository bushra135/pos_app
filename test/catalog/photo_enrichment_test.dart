import 'dart:convert';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/community_catalog.dart';

void main() {
  test('name-only shared entry is enriched with a public photo without losing its price', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('catalog').doc('12345678').set({
      'name': 'Store chips',
      'category': 'Snacks',
      'price': 0.2,
    });
    var calls = 0;
    final service = BarcodeCatalogService(
      community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'status': 'success',
            'product': {
              'code': '12345678',
              'product_name': 'External chips',
              'brands': 'Brand',
              'quantity': '21 g',
              'generic_name': 'Salted',
              'image_front_url': 'https://images.openfoodfacts.org/images/products/photo.jpg',
            },
          }),
          200,
        );
      }),
    );
    final results = await Future.wait([
      service.lookupWithPhoto('12345678'),
      service.lookupWithPhoto('12345678'),
    ]);
    for (final product in results) {
      expect(product!.name, 'Store chips');
      expect(product.suggestedPrice, 0.2);
      expect(product.imageUrl, endsWith('/photo.jpg'));
      expect(product.brand, 'Brand');
      expect(product.size, '21 g');
      expect(product.description, 'Salted');
      expect(product.productType, CatalogProduct.communityType);
    }
    expect(calls, 1);
    expect((await service.lookup('12345678'))!.suggestedPrice, 0.2);
  });
  test(
    'unavailable public photo preserves existing shared data and avoids repeated calls',
    () async {
      final db = FakeFirebaseFirestore();
      await db.collection('catalog').doc('12345678').set({
        'name': 'Local chips',
        'category': 'Snacks',
        'price': 0.2,
      });
      var calls = 0;
      final service = BarcodeCatalogService(
        community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
        client: MockClient((_) async {
          calls++;
          return http.Response('Busy', 503);
        }),
      );
      for (var i = 0; i < 2; i++) {
        final product = (await service.lookupWithPhoto('12345678'))!;
        expect(product.name, 'Local chips');
        expect(product.suggestedPrice, 0.2);
        expect(product.imageUrl, isEmpty);
      }
      expect(calls, 1);
    },
  );
  test('existing shared photo is used without an external request', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('catalog').doc('12345678').set({
      'name': 'Chips',
      'category': 'Snacks',
      'image': 'https://images.example/photo.jpg',
    });
    final service = BarcodeCatalogService(
      community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
      client: MockClient((_) async => throw StateError('Should not fetch')),
    );
    expect(
      (await service.lookupWithPhoto('12345678'))!.imageUrl,
      'https://images.example/photo.jpg',
    );
  });
}
