import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/community_catalog.dart';

class _FailingCommunity implements CommunityCatalog {
  @override
  Future<CatalogProduct?> lookup(String barcode) async => throw StateError('offline');

  @override
  Future<void> contribute({
    required String barcode,
    required String name,
    required String category,
    double price = 0,
    String image = '',
  }) async {}
}

void main() {
  group('FirestoreCommunityCatalog', () {
    late FakeFirebaseFirestore db;
    late FirestoreCommunityCatalog catalog;

    setUp(() {
      db = FakeFirebaseFirestore();
      catalog = FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'ownerA');
    });

    test('shares name, category, image and price, never stock, then finds it', () async {
      await catalog.contribute(
        barcode: ' 6287017260083 ',
        name: ' Al Rabie Juice ',
        category: 'Drinks',
        price: 0.35,
        image: 'data:image/png;base64,AA==',
      );

      final stored = (await db.collection('catalog').doc('6287017260083').get()).data()!;
      expect(stored.keys.toSet(), {
        'name',
        'category',
        'price',
        'image',
        'contributedBy',
        'createdAt',
      });
      expect(stored['name'], 'Al Rabie Juice');
      expect(stored['contributedBy'], 'ownerA');

      final found = (await catalog.lookup('6287017260083'))!;
      expect(found.name, 'Al Rabie Juice');
      expect(found.category, 'Drinks');
      expect(found.suggestedPrice, 0.35);
      expect(found.imageUrl, 'data:image/png;base64,AA==');
      expect(found.provider, 'ShopPad stores');
      expect(found.sourceUrl, isEmpty);
      expect(found.creditLine, 'ShopPad stores · shared by other stores');
    });

    test('missing prices and unsafe images are not shared', () async {
      await catalog.contribute(
        barcode: '12345678',
        name: 'Pen',
        category: '',
        image: 'http://untrusted.example/pen.png',
      );

      final stored = (await db.collection('catalog').doc('12345678').get()).data()!;
      expect(stored.containsKey('price'), isFalse);
      expect(stored.containsKey('image'), isFalse);
      final found = (await catalog.lookup('12345678'))!;
      expect(found.suggestedPrice, 0);
      expect(found.imageUrl, isEmpty);
    });

    test('the first store to share a barcode keeps its name', () async {
      await catalog.contribute(barcode: '12345678', name: 'First name', category: '');
      await FirestoreCommunityCatalog(
        firestore: db,
        currentUserId: () => 'ownerB',
      ).contribute(barcode: '12345678', name: 'Second name', category: 'Other');

      expect((await catalog.lookup('12345678'))!.name, 'First name');
    });

    test('custom codes, blank names and signed-out users are not shared', () async {
      await catalog.contribute(barcode: 'SKU-1', name: 'Custom', category: '');
      await catalog.contribute(barcode: '12345678', name: '  ', category: '');
      await FirestoreCommunityCatalog(
        firestore: db,
        currentUserId: () => null,
      ).contribute(barcode: '87654321', name: 'Anonymous', category: '');

      expect((await db.collection('catalog').get()).docs, isEmpty);
      expect(await catalog.lookup('12345678'), isNull);
    });
  });

  group('BarcodeCatalogService with shared names', () {
    test('a shared name is used without calling the internet catalogues', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('catalog').doc('6287017260083').set({
        'name': 'Saudi Water',
        'category': 'Water',
      });
      final service = BarcodeCatalogService(
        community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'u'),
        client: MockClient((_) async => throw StateError('Unexpected request')),
      );

      final result = (await service.lookup('6287017260083'))!;
      expect(result.name, 'Saudi Water');
      expect(result.attribution['provider'], 'ShopPad stores');
      expect(result.attribution.containsKey('dataLicense'), isFalse);
    });

    test('an unavailable shared catalogue falls through to Open Food Facts', () async {
      final hosts = <String>[];
      final service = BarcodeCatalogService(
        community: _FailingCommunity(),
        generalFallback: false,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('{}', 404);
        }),
      );

      expect(await service.lookup('12345678'), isNull);
      expect(hosts, ['world.openfoodfacts.org']);
    });
  });
}
