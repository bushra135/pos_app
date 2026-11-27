import 'package:cloud_firestore/cloud_firestore.dart';

import 'barcode_catalog_service.dart';
import 'product_barcodes.dart';

/// The owner's rule for barcodes that are not in the store yet.
///
/// By default an unknown product cannot be sold until the owner adds it (the cashier
/// sends a request). The owner may also let cashiers sell at the shared reference
/// price, set by another ShopPad store, when it is at or under [maxPrice].
class UnknownItemPolicy {
  const UnknownItemPolicy({this.sharedPriceSales = false, this.maxPrice = 0});

  factory UnknownItemPolicy.fromStore(Map<String, dynamic>? store) {
    final max = store?['sharedPriceMax'];
    return UnknownItemPolicy(
      sharedPriceSales: store?['sharedPriceSales'] == true,
      maxPrice: max is num && max.isFinite && max >= 0 ? max.toDouble() : 0,
    );
  }

  final bool sharedPriceSales;
  final double maxPrice;

  /// Largest maximum the owner can set (the security rules allow the same).
  static const maxAllowed = 1000.0;

  /// The shared reference price a cashier may sell [product] at, or null when the
  /// owner's rule does not allow it. Only a price shared by a ShopPad store counts,
  /// never a price from an international catalogue.
  double? sellablePrice(CatalogProduct? product) {
    if (!sharedPriceSales || product == null) return null;
    if (product.productType != CatalogProduct.communityType) return null;
    final price = product.suggestedPrice;
    if (!price.isFinite || price <= 0 || price > maxPrice) return null;
    return price;
  }
}

/// A cashier's request for the owner to add an unknown barcode.
class ProductRequest {
  const ProductRequest({
    required this.id,
    required this.storeCode,
    required this.barcode,
    required this.name,
    this.brand = '',
    this.category = '',
    this.image = '',
    this.size = '',
    this.description = '',
    this.sharedPrice = 0,
    this.requestedByName = '',
    this.createdAt,
  });

  factory ProductRequest.fromDoc(String id, Map<String, dynamic> data) {
    String text(String key) => (data[key] ?? '').toString();
    final price = data['sharedPrice'];
    final created = data['createdAt'];
    return ProductRequest(
      id: id,
      storeCode: text('storeCode'),
      barcode: text('barcode'),
      name: text('name'),
      brand: text('brand'),
      category: text('category'),
      image: text('image'),
      size: text('size'),
      description: text('description'),
      sharedPrice: price is num ? price.toDouble() : 0,
      requestedByName: text('requestedByName'),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }

  final String id;
  final String storeCode;
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final String image;
  final String size;
  final String description;

  /// Shared reference price known when the request was sent (0 when none). For the
  /// owner's information only; the owner always sets the selling price.
  final double sharedPrice;
  final String requestedByName;
  final DateTime? createdAt;
}

/// Firestore operations for unknown barcodes. Ids are `storeCode_barcode`, so the same
/// barcode is never requested or registered twice in one store.
class UnknownProducts {
  UnknownProducts(this.db);

  final FirebaseFirestore db;

  static String docId(String storeCode, String barcode) => '${storeCode}_$barcode';

  static String _clip(String value, int max) {
    final text = value.trim();
    return text.length > max ? text.substring(0, max).trim() : text;
  }

  /// Product details from a lookup, in the product document's field names.
  static Map<String, dynamic> _details(String barcode, CatalogProduct? product, String name) => {
    'barcode': barcode,
    'name': _clip(product?.name ?? name, 80),
    'brand': _clip(product?.brand ?? '', 60),
    'category': _clip(product?.category ?? '', 60),
    'image': product?.imageUrl ?? '',
    'size': _clip(product?.size ?? '', 40),
    'description': _clip(product?.description ?? '', 300),
  };

  /// True when the store already has a product with [barcode] (duplicate check).
  Future<bool> barcodeInUse(String storeCode, String barcode) async {
    final found = await db
        .collection('products')
        .where('storeCode', isEqualTo: storeCode)
        .where('barcode', isEqualTo: barcode)
        .limit(1)
        .get();
    return found.docs.isNotEmpty;
  }

  /// An authorized one-line sale is a temporary quote, never an inventory write.
  /// Re-read the owner policy and shared price from the server before offering it.
  Future<Map<String, dynamic>> registerAtSharedPrice({
    required String storeCode,
    required String uid,
    required CatalogProduct product,
    required double price,
  }) async {
    final store = await db
        .collection('stores')
        .doc(storeCode)
        .get(const GetOptions(source: Source.server));
    final shared = await db
        .collection('catalog')
        .doc(product.barcode)
        .get(const GetOptions(source: Source.server));
    final reference = shared.data()?['price'];
    final policy = UnknownItemPolicy.fromStore(store.data());
    if (!price.isFinite ||
        reference is! num ||
        price != reference ||
        !policy.sharedPriceSales ||
        price <= 0 ||
        price > policy.maxPrice) {
      throw StateError('The owner has not authorized this reference price.');
    }
    if (await barcodeInUse(storeCode, product.barcode)) {
      throw StateError('This barcode already exists');
    }
    return {
      ..._details(product.barcode, product, product.name),
      'id': 'unknown_${storeCode}_${product.barcode}',
      'storeCode': storeCode,
      'price': price,
    };
  }

  /// Cashier: asks the owner to add the product. Returns false when a request for this
  /// barcode is already waiting.
  Future<bool> requestApproval({
    required String storeCode,
    required String uid,
    required String requestedByName,
    required String barcode,
    CatalogProduct? product,
  }) async {
    final ref = db.collection('productRequests').doc(docId(storeCode, barcode));
    try {
      await ref.set({
        ..._details(barcode, product, product?.name ?? barcode),
        'storeCode': storeCode,
        if ((product?.suggestedPrice ?? 0) > 0 &&
            product?.productType == CatalogProduct.communityType)
          'sharedPrice': product!.suggestedPrice,
        'requestedBy': uid,
        'requestedByName': _clip(requestedByName, 80),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (error) {
      // The rules refuse a second request for the same barcode (it would be an update).
      if (error.code == 'permission-denied') {
        final existing = await ref.get(const GetOptions(source: Source.server));
        if (existing.exists) return false;
      }
      rethrow;
    }
  }

  /// Owner: requests waiting in [storeCode], newest first.
  Stream<List<ProductRequest>> pending(String storeCode) => db
      .collection('productRequests')
      .where('storeCode', isEqualTo: storeCode)
      .snapshots()
      .map((snapshot) {
        final list = [for (final doc in snapshot.docs) ProductRequest.fromDoc(doc.id, doc.data())];
        list.sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)),
        );
        return list;
      });

  /// Owner: adds the product with the owner's price and counted stock, and closes the
  /// request when there is one. Refuses a barcode the store already has.
  Future<Map<String, dynamic>> addAsOwner({
    required String storeCode,
    required String barcode,
    required String name,
    required double price,
    required int stock,
    CatalogProduct? product,
    ProductRequest? request,
  }) async {
    if (name.trim().isEmpty ||
        !price.isFinite ||
        price <= 0 ||
        stock < 0 ||
        !RegExp(r'^(?:\d{8}|\d{12,14})$').hasMatch(barcode)) {
      throw StateError('Please fill all required fields correctly');
    }
    if (await barcodeInUse(storeCode, barcode)) {
      throw StateError('This barcode already exists');
    }
    final ref = db.collection('products').doc(docId(storeCode, barcode));
    final details = request == null
        ? _details(barcode, product, name)
        : {
            'barcode': request.barcode,
            'name': _clip(name, 80),
            'brand': request.brand,
            'category': request.category,
            'image': request.image,
            'size': request.size,
            'description': request.description,
          };
    final data = {
      ...details,
      'name': _clip(name, 80),
      'storeCode': storeCode,
      'price': price,
      'stock': stock,
      'minStock': 0,
      if (product != null) 'catalogueSource': product.attribution,
    };
    await db.runTransaction((transaction) async {
      if ((await transaction.get(ref)).exists) throw StateError('This barcode already exists');
      final claim = ProductBarcodes.claim(db, storeCode, barcode);
      final held = await transaction.get(claim);
      if (held.exists && held.data()?['productId'] != ref.id) {
        throw StateError('This barcode already exists');
      }
      if (request != null) {
        final pending = await transaction.get(db.collection('productRequests').doc(request.id));
        if (!pending.exists ||
            pending.data()?['storeCode'] != storeCode ||
            pending.data()?['barcode'] != barcode) {
          throw StateError('This request is no longer available.');
        }
      }
      transaction.set(claim, {'storeCode': storeCode, 'barcode': barcode, 'productId': ref.id});
      transaction.set(ref, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (request != null) transaction.delete(db.collection('productRequests').doc(request.id));
    });
    return {...data, 'id': ref.id};
  }

  /// Owner: declines a request (it is removed; the cashier may ask again later).
  Future<void> decline(ProductRequest request) =>
      db.collection('productRequests').doc(request.id).delete();
}
