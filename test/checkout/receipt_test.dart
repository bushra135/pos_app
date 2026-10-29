import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/services/receipt_service.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:pos_app/widgets/sale_receipt_view.dart';

SaleRecord receipt({int lines = 2}) => SaleRecord(
  id: 'test-receipt',
  storeCode: 'store-1',
  storeName: 'متجر الاختبار',
  cashierUid: 'cashier-1',
  cashierName: 'سارة',
  paymentMethod: 'Cash',
  createdAt: DateTime(2026, 10, 21, 10),
  items: List.generate(
    lines,
    (i) => SaleLine(
      productId: '$i',
      barcode: '$i',
      name: 'منتج عربي طويل للاختبار $i',
      price: 1.125,
      quantity: 2,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PDF uses the saved snapshot after the cart is cleared, including many Arabic lines',
    () async {
      final saved = receipt(lines: 100);
      CartManager.clearCart();
      final bytes = await ReceiptService.generatePdf(
        saved,
        status: 'Synchronization pending',
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(saved.total, 225);
      expect(bytes.length, greaterThan(1000));
    },
  );

  for (final width in [320.0, 800.0]) {
    testWidgets(
      'Completed receipt is usable at width $width after the cart clears',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        CartManager.clearCart();
        var newSales = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SaleReceiptView(
                sale: receipt(),
                status: 'Saved on device — synchronization pending',
                onNewSale: () => newSales++,
              ),
            ),
          ),
        );
        expect(find.text('Sale saved'), findsOneWidget);
        expect(find.text('Total: BD 4.500'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Share PDF'),
          120,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Share PDF'), findsOneWidget);
        await tester.tap(find.text('New sale'));
        await tester.pump();
        expect(newSales, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
