import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CatalogProduct {
  const CatalogProduct({
    required this.barcode,
    required this.name,
    required this.imageUrl,
    required this.category,
    this.productType = 'food',
  });
  final String barcode;
  final String name;
  final String imageUrl;
  final String category;
  final String productType;
  static const _sources = {
    'food': ('Open Food Facts', 'openfoodfacts.org'),
    'product': ('Open Products Facts', 'openproductsfacts.org'),
    'beauty': ('Open Beauty Facts', 'openbeautyfacts.org'),
    'petfood': ('Open Pet Food Facts', 'openpetfoodfacts.org'),
  };
  (String, String) get _source => _sources[productType] ?? _sources['product']!;
  String get provider => _source.$1;
  String get sourceUrl => 'https://world.${_source.$2}/product/$barcode';
  Map<String, dynamic> get attribution => {
    'provider': provider,
    'productType': productType,
    'url': sourceUrl,
    'dataLicense': 'ODbL-1.0',
    'imageLicense': 'CC-BY-SA-3.0',
  };
}

class CatalogLookupException implements Exception {
  const CatalogLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Read-only public catalogue across food, general products, beauty and pet food. Never supplies store prices or quantities.
class BarcodeCatalogService {
  BarcodeCatalogService({
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;
  static final shared = BarcodeCatalogService();
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;
  final _cache = <String, ({DateTime expires, CatalogProduct? product})>{};
  final _pending = <String, Future<CatalogProduct?>>{};
  final _requests = <DateTime>[];

  Future<CatalogProduct?> lookup(String rawBarcode) async {
    final code = rawBarcode.trim();
    if (!RegExp(r'^(?:\d{8}|\d{12,14})$').hasMatch(code)) {
      throw const CatalogLookupException(
        'This lookup supports 8, 12, 13, or 14 digit product barcodes. You can still enter this product manually.',
      );
    }
    final cached = _cache[code];
    if (cached != null && _now().isBefore(cached.expires)) {
      return cached.product;
    }
    if (_pending.containsKey(code)) return _pending[code]!;
    final request = _fetch(code);
    _pending[code] = request;
    try {
      return await request;
    } finally {
      _pending.remove(code);
    }
  }

  Future<CatalogProduct?> _fetch(String code) async {
    final now = _now();
    _requests.removeWhere(
      (time) => now.difference(time) >= const Duration(minutes: 1),
    );
    if (_requests.length >= 15) {
      throw const CatalogLookupException(
        'Please wait a minute before looking up more products. Manual entry is still available.',
      );
    }
    _requests.add(now);
    try {
      final response = await _client
          .get(
            Uri.https('world.openfoodfacts.org', '/api/v3/product/$code', {
              'fields':
                  'code,product_type,product_name,product_name_en,product_name_ar,categories,image_front_url,image_url',
              'lc': 'en',
              'product_type': 'all',
            }),
            headers: {
              'User-Agent': 'ShopPad/1.0.0 (student mobile POS)',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode == 404) return _remember(code, null);
      if (response.statusCode == 429 || response.statusCode == 503) {
        throw const CatalogLookupException(
          'The free catalogue is busy. Try again later or enter the product manually.',
        );
      }
      if (response.statusCode != 200) {
        throw const CatalogLookupException(
          'Product lookup is unavailable. You can enter the details manually.',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      final product = decoded['product'];
      if (product is! Map) {
        if (decoded['status'] == 'failure' || decoded['status'] == 0) {
          return _remember(code, null);
        }
        throw const FormatException();
      }
      final returnedCode = product['code']?.toString();
      if (returnedCode != null && returnedCode != code) {
        throw const FormatException();
      }
      String text(dynamic value) => value is String ? value.trim() : '';
      final name = [
        product['product_name_en'],
        product['product_name'],
        product['product_name_ar'],
      ].map(text).firstWhere((s) => s.isNotEmpty, orElse: () => '');
      if (name.isEmpty) return _remember(code, null);
      final image = Uri.tryParse(
        text(product['image_front_url']).isNotEmpty
            ? text(product['image_front_url'])
            : text(product['image_url']),
      );
      final safeImage =
          image != null &&
              image.scheme == 'https' &&
              const {
                'images.openfoodfacts.org',
                'images.openproductsfacts.org',
                'images.openbeautyfacts.org',
                'images.openpetfoodfacts.org',
              }.contains(image.host)
          ? image.toString()
          : '';
      return _remember(
        code,
        CatalogProduct(
          barcode: code,
          productType: text(product['product_type']).isEmpty
              ? 'food'
              : text(product['product_type']),
          name: name,
          imageUrl: safeImage,
          category: text(product['categories']).split(',').first.trim(),
        ),
      );
    } on CatalogLookupException {
      rethrow;
    } on TimeoutException {
      throw const CatalogLookupException(
        'Product lookup timed out. Check your connection or enter the details manually.',
      );
    } catch (_) {
      throw const CatalogLookupException(
        'Could not load product information. Check your connection or use manual entry.',
      );
    }
  }

  CatalogProduct? _remember(String code, CatalogProduct? product) {
    if (_cache.length >= 100) _cache.remove(_cache.keys.first);
    _cache[code] = (
      expires: _now().add(
        product == null ? const Duration(minutes: 5) : const Duration(hours: 1),
      ),
      product: product,
    );
    return product;
  }
}
