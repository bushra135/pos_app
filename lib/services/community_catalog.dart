import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'barcode_catalog_service.dart';

/// Product names shared between ShopPad stores, keyed by barcode.
///
/// Global catalogues rarely list Gulf products (628/629 prefixes), so every product a
/// store saves teaches the next store that scans the same barcode. The barcode, name,
/// category, compact image and a suggested selling price are shared; stock and store
/// identity stay private.
abstract class CommunityCatalog {
  Future<CatalogProduct?> lookup(String barcode);

  /// Adds a barcode the first time any store saves it, and later fills a missing
  /// price or photo. Never overwrites what is already shared.
  Future<void> contribute({
    required String barcode,
    required String name,
    required String category,
    double price = 0,
    String image = '',
    String brand = '',
    String size = '',
    String description = '',
    String source = '',
  });
}

/// Shared barcode catalogue in Firestore: product names, categories, suggested prices
/// and photos that every ShopPad store can read and help fill in.
class FirestoreCommunityCatalog implements CommunityCatalog {
  FirestoreCommunityCatalog({FirebaseFirestore? firestore, String? Function()? currentUserId})
    : _firestoreOverride = firestore,
      _currentUserId = currentUserId;

  final FirebaseFirestore? _firestoreOverride;
  final String? Function()? _currentUserId;

  static final _barcodePattern = RegExp(r'^(?:\d{8}|\d{12,14})$');

  // Resolved lazily so creating the service never requires Firebase to be ready.
  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;
  String? get _uid =>
      _currentUserId != null ? _currentUserId() : FirebaseAuth.instance.currentUser?.uid;

  /// The shared entry for [barcode], or null when there is none.
  @override
  Future<CatalogProduct?> lookup(String barcode) async {
    final doc = await _firestore.collection('catalog').doc(barcode).get();
    final data = doc.data();
    final name = (data?['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final price = data?['price'];
    final image = (data?['image'] ?? '').toString();
    String text(String key) => (data?[key] ?? '').toString().trim();
    final hasPrice = price is num && price > 0;
    final priceDate = data?['priceAt'] ?? data?['createdAt'];
    return CatalogProduct(
      barcode: barcode,
      name: name,
      imageUrl: _isSafeImage(image) ? image : '',
      category: text('category'),
      productType: CatalogProduct.communityType,
      suggestedPrice: hasPrice ? price.toDouble() : 0,
      sharedPriceDate: hasPrice && priceDate is Timestamp ? priceDate.toDate() : null,
      brand: text('brand'),
      size: text('size'),
      description: text('description'),
      originalSource: text('source'),
    );
  }

  /// Compact embedded images (the app's own format) or https links only.
  static bool _isSafeImage(String image) =>
      image.length <= maxImageLength &&
      (image.startsWith('data:image/') || image.startsWith('https://'));

  /// Matches the server rule; the app's compact images stay well below it.
  static const maxImageLength = 250000;

  /// Adds a product to the shared catalogue, or fills a missing price or photo.
  /// Existing values are never changed (the security rules enforce this too).
  @override
  Future<void> contribute({
    required String barcode,
    required String name,
    required String category,
    double price = 0,
    String image = '',
    String brand = '',
    String size = '',
    String description = '',
    String source = '',
  }) async {
    final code = barcode.trim();
    final uid = _uid;
    final cleanName = name.trim();
    if (uid == null || cleanName.isEmpty || !_barcodePattern.hasMatch(code)) return;

    final ref = _firestore.collection('catalog').doc(code);
    // Server rules allow a create, or a fill-in of a missing price or photo.
    final existing = await ref.get();
    if (existing.exists) {
      // Name and category stay as first shared; only a missing price or photo is added,
      // so entries saved before prices were shared still become complete.
      final data = existing.data() ?? const {};
      final updates = <String, Object>{
        if (data['price'] == null && price > 0 && price <= 100000) ...{
          'price': price,
          'priceAt': FieldValue.serverTimestamp(),
        },
        if (data['image'] == null && _isSafeImage(image.trim())) 'image': image.trim(),
        if (data['brand'] == null && brand.trim().isNotEmpty) 'brand': _clip(brand, 60),
        if (data['size'] == null && size.trim().isNotEmpty) 'size': _clip(size, 40),
        if (data['description'] == null && description.trim().isNotEmpty)
          'description': _clip(description, 300),
      };
      if (updates.isNotEmpty) await ref.update(updates);
      return;
    }
    await ref.set({
      'name': cleanName.length > 80 ? cleanName.substring(0, 80).trim() : cleanName,
      'category': category.trim().length > 60
          ? category.trim().substring(0, 60).trim()
          : category.trim(),
      if (price > 0 && price <= 100000) ...{'price': price},
      if (_isSafeImage(image.trim())) 'image': image.trim(),
      if (brand.trim().isNotEmpty) 'brand': _clip(brand, 60),
      if (size.trim().isNotEmpty) 'size': _clip(size, 40),
      if (description.trim().isNotEmpty) 'description': _clip(description, 300),
      if (source.trim().isNotEmpty) 'source': _clip(source, 40),
      'contributedBy': 'store',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String _clip(String value, int max) {
    final text = value.trim();
    return text.length > max ? text.substring(0, max).trim() : text;
  }
}
