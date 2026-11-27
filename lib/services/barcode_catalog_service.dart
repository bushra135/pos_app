import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'community_catalog.dart';

/// Product details found for a barcode, from the shared catalogue or Open Food Facts.
class CatalogProduct {
  const CatalogProduct({
    required this.barcode,
    required this.name,
    required this.imageUrl,
    required this.category,
    this.productType = 'food',
    this.suggestedPrice = 0,
    this.brand = '',
    this.size = '',
    this.description = '',
    this.sharedPriceDate,
    this.originalSource = '',
    this.referencePrice = 0,
    this.referenceCurrency = '',
  });
  final String barcode;
  final String name;
  final String imageUrl;
  final String category;
  final String productType;

  /// Brand, size/weight ("400 g", "1000 ml") and a short description; empty when unknown.
  final String brand;
  final String size;
  final String description;

  /// When a ShopPad store shared [suggestedPrice]; null when there is no shared price.
  final DateTime? sharedPriceDate;

  /// For shared-catalogue entries first identified by a public catalogue: its name,
  /// kept so the original source is still credited.
  final String originalSource;

  /// A source offer, in its original currency; never a store selling price.
  final double referencePrice;
  final String referenceCurrency;

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
      ? (originalSource.isEmpty
            ? 'shared by other stores'
            : 'shared by other stores · from $originalSource')
      : _isUpcItemDb
      ? 'name, category and photo'
      : 'data ODbL · images CC BY-SA';

  /// One-line credit for the UI: provider, licence, and the source page when there is one.
  String get creditLine =>
      ['$provider · $licenseNote', if (sourceUrl.isNotEmpty) sourceUrl].join('\n');

  /// For the device cache.
  Map<String, Object?> toJson() => {
    'barcode': barcode,
    'name': name,
    'imageUrl': imageUrl,
    'category': category,
    'productType': productType,
    'brand': brand,
    'size': size,
    'description': description,
    'referencePrice': referencePrice,
    'referenceCurrency': referenceCurrency,
  };

  /// Reads a cached product; null when the entry is unreadable.
  static CatalogProduct? fromJson(Object? json) {
    if (json is! Map) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    if (text('name').isEmpty || text('barcode').isEmpty) return null;
    return CatalogProduct(
      barcode: text('barcode'),
      name: text('name'),
      imageUrl: text('imageUrl'),
      category: text('category'),
      productType: text('productType').isEmpty ? 'food' : text('productType'),
      brand: text('brand'),
      size: text('size'),
      description: text('description'),
      referencePrice: json['referencePrice'] is num
          ? (json['referencePrice'] as num).toDouble()
          : 0,
      referenceCurrency: text('referenceCurrency'),
    );
  }

  Map<String, dynamic> get attribution => {
    'provider': provider,
    'productType': productType,
    'url': sourceUrl,
    'note': licenseNote,
    if (_isOpenFacts) ...{'dataLicense': 'ODbL-1.0', 'imageLicense': 'CC-BY-SA-3.0'},
  };
}

/// A lookup failure with a message that can be shown to the user.
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
    LookupCache? deviceCache,
  }) : _client = client ?? http.Client(),
       _deviceCache = deviceCache,
       _now = now ?? DateTime.now,
       // UPCitemdb only allows browser requests from its own site, so web builds skip it.
       generalFallback = generalFallback ?? !kIsWeb;
  static final shared = BarcodeCatalogService(
    community: FirestoreCommunityCatalog(),
    deviceCache: PrefsLookupCache(),
  );
  final http.Client _client;
  final DateTime Function() _now;
  final Duration timeout;

  /// Products identified by the public catalogues, kept on this device so the same
  /// barcode does not call the internet again.
  final LookupCache? _deviceCache;

  /// Store-shared names, checked before any internet catalogue.
  final CommunityCatalog? community;

  /// Whether to try UPCitemdb when Open Food Facts has no match.
  final bool generalFallback;
  final _cache = <String, ({DateTime expires, CatalogProduct? product})>{};
  final _pending = <String, Future<CatalogProduct?>>{};
  final _requests = <DateTime>[];
  final _generalRequests = <DateTime>[];

  /// Looks up a product barcode (8, 12, 13 or 14 digits). Results are cached and
  /// repeated requests for the same code share one network call.
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

  final _photoPending = <String, Future<CatalogProduct?>>{};
  final _photoAttempts = <String, DateTime>{};

  /// Find Product may enrich a name-only shared entry with a public catalogue
  /// photo. Shared names/prices and owner edits remain authoritative.
  Future<CatalogProduct?> lookupWithPhoto(String rawBarcode) async {
    final code = rawBarcode.trim();
    final found = await lookup(code);
    if (found == null ||
        found.imageUrl.isNotEmpty ||
        found.productType != CatalogProduct.communityType) {
      return found;
    }
    final attempt = _photoAttempts[code];
    if (attempt != null && _now().difference(attempt) < const Duration(minutes: 5)) {
      return _cache[code]?.product ?? found;
    }
    final active = _photoPending[code];
    if (active != null) return active;
    final request = _completePhoto(code, found);
    _photoPending[code] = request;
    try {
      return await request;
    } finally {
      _photoPending.remove(code);
    }
  }

  Future<CatalogProduct?> _completePhoto(String code, CatalogProduct shared) async {
    try {
      final device = await _readDeviceCache(code);
      final external = device != null && device.imageUrl.isNotEmpty
          ? device
          : await _fetchExternal(code, remember: false);
      if (external == null || external.imageUrl.isEmpty) return _remember(code, shared);
      unawaited(_writeDeviceCache(external));
      return _remember(
        code,
        CatalogProduct(
          barcode: code,
          name: shared.name,
          imageUrl: external.imageUrl,
          category: shared.category.isEmpty ? external.category : shared.category,
          productType: shared.productType,
          suggestedPrice: shared.suggestedPrice,
          sharedPriceDate: shared.sharedPriceDate,
          brand: shared.brand.isEmpty ? external.brand : shared.brand,
          size: shared.size.isEmpty ? external.size : shared.size,
          description: shared.description.isEmpty ? external.description : shared.description,
          originalSource: external.provider,
          referencePrice: external.referencePrice,
          referenceCurrency: external.referenceCurrency,
        ),
      );
    } catch (_) {
      // A photo source outage must not discard a known product or reference price.
      return _remember(code, shared);
    } finally {
      if (_photoAttempts.length >= 100) _photoAttempts.remove(_photoAttempts.keys.first);
      _photoAttempts[code] = _now();
    }
  }

  /// Tries the shared ShopPad catalogue first, then Open Food Facts
  /// (at most 15 requests a minute).
  Future<CatalogProduct?> _fetch(String code) async {
    final shared = await _lookupCommunity(code);
    if (shared != null) return _remember(code, shared);
    final cachedOnDevice = await _readDeviceCache(code);
    if (cachedOnDevice != null) {
      _share(cachedOnDevice);
      return _remember(code, cachedOnDevice);
    }
    final found = await _fetchExternal(code);
    if (found != null) {
      unawaited(_writeDeviceCache(found));
      _share(found);
    }
    return found;
  }

  /// Open Food Facts (all product types: food, beauty, household, pet food), then UPCitemdb.
  Future<CatalogProduct?> _fetchExternal(String code, {bool remember = true}) async {
    CatalogProduct? finish(CatalogProduct? product) =>
        remember ? _remember(code, product) : product;
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
                  'code,product_type,product_name,product_name_en,product_name_ar,brands,quantity,'
                  'generic_name,generic_name_en,categories,image_front_url,image_url',
              'lc': 'en',
              'product_type': 'all',
            }),
            headers: {
              'User-Agent': 'ShopPad/1.0.0 (student mobile POS)',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode == 404) return finish(await _lookupGeneral(code));
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
          return finish(await _lookupGeneral(code));
        }
        throw const FormatException();
      }
      final returnedCode = product['code']?.toString();
      if (returnedCode != null &&
          returnedCode.replaceFirst(RegExp(r'^0+'), '') != code.replaceFirst(RegExp(r'^0+'), '')) {
        throw const FormatException();
      }
      String text(dynamic value) => value is String ? value.trim() : '';
      final name = [
        product['product_name_en'],
        product['product_name'],
        product['product_name_ar'],
      ].map(text).firstWhere((s) => s.isNotEmpty, orElse: () => '');
      if (name.isEmpty) return finish(await _lookupGeneral(code));
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
      return finish(
        CatalogProduct(
          barcode: code,
          productType: text(product['product_type']).isEmpty
              ? 'food'
              : text(product['product_type']),
          name: name,
          imageUrl: safeImage,
          category: text(product['categories']).split(',').first.trim(),
          brand: text(product['brands']).split(',').first.trim(),
          size: text(product['quantity']),
          description: [
            product['generic_name_en'],
            product['generic_name'],
          ].map(text).firstWhere((s) => s.isNotEmpty, orElse: () => ''),
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
    final now = _now();
    _generalRequests.removeWhere((t) => now.difference(t) >= const Duration(days: 1));
    if (_generalRequests.length >= 100 ||
        _generalRequests.where((t) => now.difference(t) < const Duration(minutes: 1)).length >= 6) {
      return null;
    }
    _generalRequests.add(now);
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
        final offers = item['offers'] is List ? item['offers'] as List : const [];
        final offer = offers
            .whereType<Map>()
            .where(
              (o) =>
                  o['price'] is num &&
                  (o['price'] as num).isFinite &&
                  (o['price'] as num) > 0 &&
                  o['currency'] is String &&
                  RegExp(r'^[A-Z]{3}$').hasMatch(o['currency'] as String),
            )
            .firstOrNull;
        return CatalogProduct(
          referencePrice: offer == null ? 0 : (offer['price'] as num).toDouble(),
          referenceCurrency: offer == null ? '' : offer['currency'] as String,
          barcode: code,
          name: name.length > 80 ? name.substring(0, 80).trim() : name,
          imageUrl: image,
          category: category,
          productType: CatalogProduct.upcItemDbType,
          brand: text(item['brand']),
          size: text(item['size']),
          description: _clip(text(item['description']), 300),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Teaches the shared catalogue a product found in a public catalogue (no price),
  /// crediting the source. Best effort: never delays or fails the lookup.
  void _share(CatalogProduct product) {
    final source = community;
    if (source == null) return;
    unawaited(
      source
          .contribute(
            barcode: product.barcode,
            name: product.name,
            category: product.category,
            image: product.imageUrl,
            brand: product.brand,
            size: product.size,
            description: product.description,
            source: product.provider,
          )
          .catchError((Object _) {}),
    );
  }

  Future<CatalogProduct?> _readDeviceCache(String code) async {
    try {
      return await _deviceCache?.read(code, _now());
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDeviceCache(CatalogProduct product) async {
    try {
      await _deviceCache?.write(product, _now());
    } catch (_) {
      // A full or unavailable device store only means the next lookup asks again.
    }
  }

  static String _clip(String value, int max) =>
      value.length > max ? value.substring(0, max).trim() : value;

  CatalogProduct? _remember(String code, CatalogProduct? product) {
    if (_cache.length >= 100) _cache.remove(_cache.keys.first);
    _cache[code] = (
      expires: _now().add(product == null ? const Duration(minutes: 5) : const Duration(hours: 1)),
      product: product,
    );
    return product;
  }
}

/// Device storage for products identified by the public catalogues.
abstract class LookupCache {
  Future<CatalogProduct?> read(String barcode, DateTime now);
  Future<void> write(CatalogProduct product, DateTime now);
}

/// [LookupCache] in SharedPreferences: up to [maxEntries] products for [maxAge],
/// the oldest dropped first.
class PrefsLookupCache implements LookupCache {
  PrefsLookupCache({this.maxEntries = 300, this.maxAge = const Duration(days: 30)});

  final int maxEntries;
  final Duration maxAge;
  static const _key = 'barcode_lookup_cache_v1';

  Future<Map<String, dynamic>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  @override
  Future<CatalogProduct?> read(String barcode, DateTime now) async {
    final entry = (await _load(await SharedPreferences.getInstance()))[barcode];
    if (entry is! Map) return null;
    final saved = DateTime.tryParse('${entry['savedAt']}');
    if (saved == null || now.difference(saved) > maxAge) return null;
    return CatalogProduct.fromJson(entry['product']);
  }

  @override
  Future<void> write(CatalogProduct product, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _load(prefs)
      ..remove(product.barcode)
      ..[product.barcode] = {'savedAt': now.toIso8601String(), 'product': product.toJson()};
    while (all.length > maxEntries) {
      all.remove(all.keys.first);
    }
    await prefs.setString(_key, jsonEncode(all));
  }
}
