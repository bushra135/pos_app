import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';

http.Response found(
  String code, {
  String image = 'https://images.openfoodfacts.org/images/products/test.jpg',
}) => http.Response(
  jsonEncode({
    'status': 'success',
    'product': {
      'code': code,
      'product_name_en': 'Milk',
      'product_name_ar': 'حليب',
      'categories': 'Dairy, Milk',
      'image_front_url': image,
      'price': 999,
      'stock': 999,
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  test(
    'Lookup preserves leading zeros, limits requested fields, and caches results',
    () async {
      var calls = 0;
      final service = BarcodeCatalogService(
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/v3/product/012345678905');
          expect(request.headers['User-Agent'], contains('ShopPad'));
          expect(request.url.queryParameters['product_type'], 'all');
          expect(
            request.url.queryParameters['fields'],
            isNot(contains('price')),
          );
          return found('012345678905');
        }),
      );
      final result = await service.lookup(' 012345678905 ');
      expect(result!.barcode, '012345678905');
      expect(result.name, 'Milk');
      expect(result.category, 'Dairy');
      expect(result.attribution['provider'], 'Open Food Facts');
      expect(result.sourceUrl, endsWith('012345678905'));
      await service.lookup('012345678905');
      expect(calls, 1);
    },
  );
  test(
    'General manufacturer products retain the correct source and image',
    () async {
      final service = BarcodeCatalogService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'success',
              'product': {
                'code': '6111259733749',
                'product_type': 'product',
                'product_name': 'Dishwashing liquid',
                'image_front_url':
                    'https://images.openproductsfacts.org/images/products/test.jpg',
              },
            }),
            200,
          ),
        ),
      );
      final result = (await service.lookup('6111259733749'))!;
      expect(result.name, 'Dishwashing liquid');
      expect(result.provider, 'Open Products Facts');
      expect(
        result.sourceUrl,
        'https://world.openproductsfacts.org/product/6111259733749',
      );
      expect(result.imageUrl, contains('images.openproductsfacts.org'));
      expect(result.attribution['provider'], 'Open Products Facts');
    },
  );
  test('Missing products are cached temporarily and then retried', () async {
    var now = DateTime(2026);
    var calls = 0;
    final service = BarcodeCatalogService(
      now: () => now,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 404);
      }),
    );
    expect(await service.lookup('12345678'), isNull);
    expect(await service.lookup('12345678'), isNull);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 6));
    await service.lookup('12345678');
    expect(calls, 2);
  });
  test('Custom and malformed barcodes never send network requests', () async {
    final service = BarcodeCatalogService(
      client: MockClient((_) async => throw StateError('Unexpected request')),
    );
    for (final code in [
      'SKU-123',
      'https://example.com',
      '123',
      '../12345678',
    ]) {
      await expectLater(
        service.lookup(code),
        throwsA(isA<CatalogLookupException>()),
      );
    }
  });
  test('Concurrent same-barcode lookups share one request', () async {
    var calls = 0;
    final response = Completer<http.Response>();
    final service = BarcodeCatalogService(
      client: MockClient((_) {
        calls++;
        return response.future;
      }),
    );
    final a = service.lookup('12345678');
    final b = service.lookup('12345678');
    response.complete(found('12345678'));
    expect(await a, same(await b));
    expect(calls, 1);
  });
  test(
    'Provider failures do not poison the cache and unsafe images are discarded',
    () async {
      var calls = 0;
      final service = BarcodeCatalogService(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('busy', 503)
              : found('12345678', image: 'http://untrusted.example/image.jpg');
        }),
      );
      await expectLater(
        service.lookup('12345678'),
        throwsA(isA<CatalogLookupException>()),
      );
      expect((await service.lookup('12345678'))!.imageUrl, isEmpty);
      expect(calls, 2);
    },
  );
  test(
    'Mismatched products and invalid JSON are not treated as matches',
    () async {
      for (final response in [
        found('87654321'),
        http.Response('broken', 200),
      ]) {
        final service = BarcodeCatalogService(
          client: MockClient((_) async => response),
        );
        await expectLater(
          service.lookup('12345678'),
          throwsA(isA<CatalogLookupException>()),
        );
      }
    },
  );
  test('Timeouts keep manual entry available', () async {
    final service = BarcodeCatalogService(
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      service.lookup('12345678'),
      throwsA(
        isA<CatalogLookupException>().having(
          (e) => e.message,
          'message',
          contains('manually'),
        ),
      ),
    );
  });
  test('Reads stop at the provider limit and resume after a minute', () async {
    var now = DateTime(2026);
    var calls = 0;
    final service = BarcodeCatalogService(
      now: () => now,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 404);
      }),
    );
    for (var i = 0; i < 15; i++) {
      await service.lookup('${10000000 + i}');
    }
    await expectLater(
      service.lookup('20000000'),
      throwsA(isA<CatalogLookupException>()),
    );
    expect(calls, 15);
    now = now.add(const Duration(minutes: 1));
    await service.lookup('20000000');
    expect(calls, 16);
  });
}
