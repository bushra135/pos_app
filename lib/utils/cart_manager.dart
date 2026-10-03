import '../models/cart_item.dart';

/// In-memory cart shared by scanning, cart, and checkout screens.
/// Checkout saves the sale to Firestore before clearing these items.
abstract final class CartManager {
  static final List<CartItem> items = [];

  static void addItem({
    required String name,
    required double price,
    required String barcode,
    required String image,
  }) {
    // Barcode identifies a cart item; adding it again increases its quantity.
    final existingIndex = items.indexWhere((item) => item.barcode == barcode);

    if (existingIndex != -1) {
      items[existingIndex].quantity++;
    } else {
      items.add(
        CartItem(name: name, price: price, barcode: barcode, image: image),
      );
    }
  }

  static void increaseQuantity(int index) {
    items[index].quantity++;
  }

  static void decreaseQuantity(int index) {
    // Removing the last unit removes the item instead of leaving a zero row.
    if (items[index].quantity > 1) {
      items[index].quantity--;
    } else {
      items.removeAt(index);
    }
  }

  static void removeItem(int index) {
    items.removeAt(index);
  }

  static double get total {
    var subtotal = 0.0;
    for (final item in items) {
      subtotal += item.totalPrice;
    }
    return subtotal;
  }

  static void clearCart() {
    items.clear();
  }
}
