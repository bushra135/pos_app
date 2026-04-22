import '../models/cart_item.dart';

class CartManager {
  static final List<CartItem> items = [];

  static void addItem({
    required String name,
    required double price,
    required String barcode,
    required String image,
  }) {
    final int existingIndex = items.indexWhere(
      (item) => item.barcode == barcode,
    );

    if (existingIndex != -1) {
      items[existingIndex].quantity++;
    } else {
      items.add(
        CartItem(
          name: name,
          price: price,
          barcode: barcode,
          image: image,
        ),
      );
    }
  }

  static void increaseQuantity(int index) {
    items[index].quantity++;
  }

  static void decreaseQuantity(int index) {
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
    double sum = 0;
    for (final item in items) {
      sum += item.totalPrice;
    }
    return sum;
  }

  static void clearCart() {
    items.clear();
  }
}