import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/app/app_language.dart';
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
      final bytes = await ReceiptService.generatePdf(saved, status: 'Synchronization pending');
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(saved.total, 225);
      expect(bytes.length, greaterThan(1000));
    },
  );

  for (final width in [320.0, 800.0]) {
    testWidgets('Completed receipt is usable at width $width after the cart clears', (
      tester,
    ) async {
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
      expect(find.text('الإجمالي'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('BD 4.500'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Share PDF'),
        120,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.text('Share PDF'), findsOneWidget);
      await tester.tap(find.text('New sale'));
      await tester.pump();
      expect(newSales, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Arabic receipts keep VAT number groups and dates explicitly left to right', (
    tester,
  ) async {
    AppLanguage.locale.value = AppLanguage.arabic;
    addTearDown(() => AppLanguage.locale.value = AppLanguage.english);
    final saved = SaleRecord(
      id: 'direction-test',
      storeCode: 'A',
      storeName: 'متجر الاختبار',
      cashierUid: 'cashier',
      cashierName: 'سارة',
      paymentMethod: 'Cash',
      createdAt: DateTime(2026, 11, 28, 16, 30),
      invoiceKind: 'full',
      vatRate: 10,
      storeVatNumber: '123456789012345',
      buyerName: 'أحمد علي',
      buyerVatNumber: '543210987654321',
      items: const [SaleLine(productId: 'pen', barcode: '123', name: 'قلم', price: 2, quantity: 1)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SaleReceiptView(sale: saved, status: 'تمت المزامنة', onNewSale: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('5432 1098 7654 321')).textDirection, TextDirection.ltr);
    expect(tester.widget<Text>(find.text('28/11/2026 16:30')).textDirection, TextDirection.ltr);
    expect(find.text('رقم ض.ق.م للعميل'), findsOneWidget);
    expect(find.text('Customer VAT No.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
