import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'community_catalog.dart';

class CatalogProduct {
  const CatalogProduct({
    required this.barcode,
    required this.name,
    required this.imageUrl,
    required this.category,
    this.productType = 'food',
    this.suggestedPrice = 0,
  });
  final String barcode;
  final String name;
  final String imageUrl;
  final String category;
  final String productType;

  /// Selling price another ShopPad store set; 0 when unknown. Public catalogues never supply one.
  final double suggestedPrice;
  static const _sources = {
    'food': ('Open Food Facts', 'openfoodfacts.org'),
    'product': ('Open Products Facts', 'openproductsfacts.org'),
    'beauty': ('Open Beauty Facts', 'openbeautyfacts.org'),
    'petfood': ('Open Pet Food Facts', 'openpetfoodfacts.org'),
  };

  /// Product type used for general merchandise found through the UPCitemdb fallback.
  static const upcItemDbType = 'upcitemdb';

  /// Product type for names shared by other ShopPad stores.
  static const communityType = 'shoppad';

  bool get _isUpcItemDb => productType == upcItemDbType;
  bool get _isCommunity => productType == communityType;
  bool get _isOpenFacts => !_isUpcItemDb && !_isCommunity;
  (String, String) get _source => _sources[productType] ?? _sources['product']!;
  String get provider => _isCommunity
      ? 'ShopPad stores'
      : _isUpcItemDb
      ? 'UPCitemdb'
      : _source.$1;

  /// Public page for the product; empty for community entries, which have none.
  String get sourceUrl => _isCommunity
      ? ''
      : _isUpcItemDb
      ? 'https://www.upcitemdb.com/upc/$barcode'
      : 'https://world.${_source.$2}/product/$barcode';

  /// Short licence line shown beside the source link.
  String get licenseNote => _isCommunity
      ? 'shared by other stores'
      : _isUpcItemDb
      ? 'name, category and photo'
      : 'data ODbL · images CC BY-SA';

  /// One-line credit for the UI: provider, licence, and the source page when there is one.
  String get creditLine =>
      ['$provider · $licenseNote', if (sourceUrl.isNotEmpty) sourceUrl].join('\n');

  Map<String, dynamic> get attribution => {
    'provider': provider,
    'productType': productType,
    'url': sourceUrl,
    'note': licenseNote,
    if (_isOpenFacts) ...{'dataLicense': 'ODbL-1.0', 'imageLicense': 'CC-BY-SA-3.0'},
  };
}

class CatalogLookupException implements Exception {
  const CatalogLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Read-only public catalogue across food, general products, beauty and pet food. Never supplies store prices or quantities.
///
/// Search order:
/// 1. Names shared by other ShopPad stores (covers local Gulf products).
/// 2. Open Food Facts and its sister catalogues.
/// 3. The free UPCitemdb trial endpoint for general merchandise such as stationery.
class BarcodeCatalogService {
  BarcodeCatalogService({
    http.Client? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 4),
    bool? generalFallback,
    this.community,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       // UPCitemdb only allows browser requests from its own site, so web builds skip it.
       generalFallback = generalFallback ?? !kIsWeb;
  static final shared = BarcodeCatalogService(community: FirestoreCommunityCatalog());
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;

  /// Store-shared names, checked before any internet catalogue.
  final CommunityCatalog? community;

  /// Whether to try UPCitemdb when Open Food Facts has no match.
  final bool generalFallback;
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
    final shared = await _lookupCommunity(code);
    if (shared != null) return _remember(code, shared);

    final now = _now();
    _requests.removeWhere((time) => now.difference(time) >= const Duration(minutes: 1));
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
      if (response.statusCode == 404) return _remember(code, await _lookupGeneral(code));
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
          return _remember(code, await _lookupGeneral(code));
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
      if (name.isEmpty) return _remember(code, await _lookupGeneral(code));
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

  /// Kept short so an offline device moves on to the internet catalogues quickly.
  Future<CatalogProduct?> _lookupCommunity(String code) async {
    final source = community;
    if (source == null) return null;
    try {
      return await source.lookup(code).timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      return null;
    }
  }

  /// Second source for general merchandise. Any failure here (offline, browser CORS,
  /// daily limit) means "not found", so manual entry stays available without an error.
  Future<CatalogProduct?> _lookupGeneral(String code) async {
    if (!generalFallback) return null;
    try {
      final response = await _client
          .get(
            Uri.https('api.upcitemdb.com', '/prod/trial/lookup', {'upc': code}),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['items'] is! List) return null;

      String text(dynamic value) => value is String ? value.trim() : '';
      String digits(dynamic value) => text(value).replaceFirst(RegExp(r'^0+'), '');
      final wanted = digits(code);
      for (final item in decoded['items'] as List) {
        if (item is! Map) continue;
        // Accept the same number written as UPC-A or EAN-13 (leading zeros differ).
        final matches = digits(item['ean']) == wanted || digits(item['upc']) == wanted;
        final name = text(item['title']);
        if (!matches || name.isEmpty) continue;
        // UPCitemdb categories run general > specific; the last part is most useful in a shop.
        final category = text(item['category']).split('>').last.trim();
        // First secure (https) retailer photo; plain http images are skipped.
        final images = item['images'] is List ? item['images'] as List : const [];
        final image = images
            .map(text)
            .firstWhere((url) => Uri.tryParse(url)?.scheme == 'https', orElse: () => '');
        return CatalogProduct(
          barcode: code,
          name: name.length > 80 ? name.substring(0, 80).trim() : name,
          imageUrl: image,
          category: category,
          productType: CatalogProduct.upcItemDbType,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  CatalogProduct? _remember(String code, CatalogProduct? product) {
    if (_cache.length >= 100) _cache.remove(_cache.keys.first);
    _cache[code] = (
      expires: _now().add(product == null ? const Duration(minutes: 5) : const Duration(hours: 1)),
      product: product,
    );
    return product;
  }
}
