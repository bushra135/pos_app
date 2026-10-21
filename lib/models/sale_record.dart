/// A fixed copy of a cart line; later cart edits cannot change queued sales.
class SaleLine {
  const SaleLine({
    required this.productId,
    required this.barcode,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String productId;
  final String barcode;
  final String name;
  final double price;
  final int quantity;

  double get subtotal => price * quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'barcode': barcode,
    'name': name,
    'price': price,
    'quantity': quantity,
    'subtotal': subtotal,
  };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
    productId: json['productId'] as String,
    barcode: json['barcode'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    quantity: json['quantity'] as int,
  );
}

/// The ID and receipt remain the same across restarts and transaction retries.
class SaleRecord {
  SaleRecord({
    required this.id,
    required this.storeCode,
    required this.storeName,
    required this.cashierUid,
    required this.cashierName,
    required this.paymentMethod,
    required this.createdAt,
    required List<SaleLine> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String storeCode;
  final String storeName;
  final String cashierUid;
  final String cashierName;
  final String paymentMethod;
  final DateTime createdAt;
  final List<SaleLine> items;

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);
  String get receiptNumber => 'RCPT-$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeCode': storeCode,
    'storeName': storeName,
    'cashierUid': cashierUid,
    'cashierName': cashierName,
    'paymentMethod': paymentMethod,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'receiptNumber': receiptNumber,
    'items': items.map((item) => item.toJson()).toList(),
    'total': total,
  };

  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
    id: json['id'] as String,
    storeCode: json['storeCode'] as String,
    storeName: json['storeName'] as String,
    cashierUid: json['cashierUid'] as String,
    cashierName: json['cashierName'] as String,
    paymentMethod: json['paymentMethod'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    items: (json['items'] as List)
        .map(
          (item) => SaleLine.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}
