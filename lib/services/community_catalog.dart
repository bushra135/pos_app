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

  /// Adds a barcode the first time any store saves it. Never overwrites an entry.
  Future<void> contribute({
    required String barcode,
    required String name,
    required String category,
    double price = 0,
    String image = '',
  });
}

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

  @override
  Future<CatalogProduct?> lookup(String barcode) async {
    final doc = await _firestore.collection('catalog').doc(barcode).get();
    final data = doc.data();
    final name = (data?['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final price = data?['price'];
    final image = (data?['image'] ?? '').toString();
    return CatalogProduct(
      barcode: barcode,
      name: name,
      imageUrl: _isSafeImage(image) ? image : '',
      category: (data?['category'] ?? '').toString().trim(),
      productType: CatalogProduct.communityType,
      suggestedPrice: price is num && price > 0 ? price.toDouble() : 0,
    );
  }

  /// Compact embedded images (the app's own format) or https links only.
  static bool _isSafeImage(String image) =>
      image.length <= maxImageLength &&
      (image.startsWith('data:image/') || image.startsWith('https://'));

  /// Matches the server rule; the app's compact images stay well below it.
  static const maxImageLength = 250000;

  @override
  Future<void> contribute({
    required String barcode,
    required String name,
    required String category,
    double price = 0,
    String image = '',
  }) async {
    final code = barcode.trim();
    final uid = _uid;
    final cleanName = name.trim();
    if (uid == null || cleanName.isEmpty || !_barcodePattern.hasMatch(code)) return;

    final ref = _firestore.collection('catalog').doc(code);
    // Server rules allow create only, so an existing entry is left as the first store wrote it.
    final existing = await ref.get();
    if (existing.exists) return;
    await ref.set({
      'name': cleanName.length > 80 ? cleanName.substring(0, 80).trim() : cleanName,
      'category': category.trim().length > 60
          ? category.trim().substring(0, 60).trim()
          : category.trim(),
      if (price > 0 && price <= 100000) 'price': price,
      if (_isSafeImage(image.trim())) 'image': image.trim(),
      'contributedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
