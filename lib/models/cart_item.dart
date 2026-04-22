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
}