/// Cart item with fixed product details and an editable quantity.
class CartItem {
  final String name;
  final double price;
  final String barcode;
  final String image;
  int quantity;

  CartItem({
    required this.name,
    required this.price,
    required this.barcode,
    required this.image,
    this.quantity = 1,
  });

  double get totalPrice => price * quantity;

  /// Keeps receipt details without duplicating large embedded product images.
  Map<String, dynamic> toSaleData() => {
    'name': name,
    'price': price,
    'quantity': quantity,
    'barcode': barcode,
    // Several embedded images can exceed the size limit of a sales document.
    'image': image.trimLeft().startsWith('data:image/') ? '' : image,
    'subtotal': totalPrice,
  };
}
