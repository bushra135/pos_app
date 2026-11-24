import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/closing/end_of_day_screen.dart';

void main() {
  test('day summary splits payments, discounts, refunds and VAT', () {
    final summary = DaySummary.fromSales([
      {'paymentMethod': 'Cash', 'total': 9.0, 'subtotal': 10.0, 'discount': 1.0, 'tax': 0.818},
      {'paymentMethod': 'BenefitPay', 'total': 5.5, 'tax': 0.5},
      {'paymentMethod': 'Cash', 'total': 2.0, 'status': 'refund', 'refund': 2.0},
      {'paymentMethod': 'Cash', 'total': 99.0, 'status': 'pending'},
    ]);
    expect(summary.receipts, 2);
    expect(summary.gross, 15.5);
    expect(summary.discounts, 1.0);
    expect(summary.refunds, 2.0);
    expect(summary.net, closeTo(12.5, 1e-9));
    expect(summary.vat, closeTo(1.318, 1e-9));
    expect(summary.cashSales, closeTo(7.0, 1e-9));
    expect(summary.expectedCash(20), closeTo(27.0, 1e-9));
  });

  testWidgets('cashier closes only their own drawer and sees the difference', (tester) async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 11, 24, 18);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('c1').set({
      'storeCode': 'A',
      'role': 'cashier',
      'fullName': 'Noora',
      'storeName': 'Test Store',
    });
    Future<void> sale(String id, String cashier, double total, DateTime when) =>
        db.collection('sales').doc(id).set({
          'storeCode': 'A',
          'cashierUid': cashier,
          'paymentMethod': 'Cash',
          'total': total,
          'status': 'completed',
          'createdAt': Timestamp.fromDate(when),
        });
    await sale('mine', 'c1', 12.0, DateTime(2026, 11, 24, 10));
    await sale('other-cashier', 'c2', 50.0, DateTime(2026, 11, 24, 11));
    await sale('yesterday', 'c1', 30.0, DateTime(2026, 11, 23, 15));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EndOfDayScreen(firestore: db, currentUserId: () => 'c1', now: () => now),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 receipt today'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Opening float (cash at start of day)'),
      '20',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Counted cash'), '31.5');
    await tester.pumpAndSettle();

    expect(find.text('BD 32.000'), findsOneWidget); // expected = 20 + 12
    expect(find.text('Short by BD 0.500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
