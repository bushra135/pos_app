import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/cart_item.dart';
import 'package:pos_app/screens/cart/cart_screen.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:pos_app/utils/app_typography.dart';

void main() {
  setUpAll(() async {
    // Use the bundled font's real metrics for narrow-screen layout checks.
    final loader = FontLoader(AppTypography.family)
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await loader.load();
  });
  setUp(CartManager.clearCart);
  tearDown(CartManager.clearCart);

  test('Receipt payload stays small for a cart with embedded photos', () {
    final photo = 'data:image/png;base64,${'A' * (240 * 1024)}';
    final items = List.generate(
      8,
      (index) => CartItem(
        name: 'Product $index',
        price: 12.5,
        quantity: 2,
        barcode: '$index',
        image: photo,
      ),
    );
    final receipt = items.map((item) => item.toSaleData()).toList();
    expect(utf8.encode(jsonEncode(receipt)).length, lessThan(4 * 1024));
    expect(receipt.fold<num>(0, (sum, item) => sum + item['subtotal']), 200);
    expect(items.first.image, photo);
    expect(receipt.first['barcode'], '0');
    expect(receipt.first['quantity'], 2);
  });

  test('Receipt snapshots retain existing image links', () {
    final item = CartItem(
      name: 'Coffee',
      price: 12.5,
      barcode: '123',
      image: 'https://example.com/coffee.png',
    );
    expect(item.toSaleData()['image'], item.image);
  });

  for (final width in [320.0, 800.0]) {
    testWidgets('Empty cart renders at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const CartScreen()),
      );
      expect(find.text('No items in cart'), findsOneWidget);
    });
    testWidgets('Cart quantity controls work at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      CartManager.addItem(
        name: 'Fresh roasted coffee beans with a long product name',
        price: 12.5,
        barcode: '123',
        image: '',
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const CartScreen()),
      );
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();
      expect(CartManager.total, 25);
      await tester.tap(find.byIcon(Icons.remove_circle));
      await tester.pump();
      expect(CartManager.total, 12.5);
      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();
      expect(find.text('No items in cart'), findsOneWidget);
    });
  }

  test(
    'Cart merges products and recalculates totals when quantity changes',
    () {
      for (var i = 0; i < 2; i++) {
        CartManager.addItem(
          name: 'Coffee',
          price: 12.5,
          barcode: '123',
          image: '',
        );
      }
      expect(CartManager.items, hasLength(1));
      expect(CartManager.total, 25);
      CartManager.decreaseQuantity(0);
      expect(CartManager.total, 12.5);
      CartManager.decreaseQuantity(0);
      expect(CartManager.items, isEmpty);
      expect(CartManager.total, 0);
    },
  );
}
