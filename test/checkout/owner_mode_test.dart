import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/cashier/cashier_home_screen.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';
import 'package:pos_app/utils/cart_manager.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });
  tearDown(CartManager.clearCart);

  for (final width in [430.0, 800.0]) {
    testWidgets(
      'owner switches workspaces without changing role or losing cart at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final db = FakeFirebaseFirestore();
        await db.collection('users').doc('owner').set({
          'role': 'owner',
          'storeCode': 'A',
          'fullName': 'Owner',
        });
        await db.collection('stores').doc('A').set({
          'ownerUid': 'owner',
          'storeName': 'Demo',
        });
        CartManager.addItem(
          name: 'Pen',
          price: 2,
          barcode: '123',
          image: '',
          productId: 'p',
          storeCode: 'A',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: OwnerHomeScreen(firestore: db, currentUserId: () => 'owner'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch to cashier'));
        await tester.pumpAndSettle();
        expect(find.byType(CashierHomeScreen), findsOneWidget);
        expect(find.text('Scan'), findsOneWidget);
        expect(find.text('Switch to owner'), findsOneWidget);
        expect(CartManager.items.single.name, 'Pen');
        await tester.tap(find.text('Switch to owner'));
        await tester.pumpAndSettle();
        expect(find.byType(CashierHomeScreen), findsNothing);
        expect(find.text('Switch to cashier'), findsOneWidget);
        expect(CartManager.items.single.name, 'Pen');
        expect(
          (await db.collection('users').doc('owner').get()).data()!['role'],
          'owner',
        );
        expect(
          (await db.collection('stores').doc('A').get()).data()!['ownerUid'],
          'owner',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('ordinary cashier has no owner switch', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('cashier').set({
      'role': 'cashier',
      'storeCode': 'A',
      'fullName': 'Cashier',
      'isActive': true,
    });
    await db.collection('stores').doc('A').set({'storeName': 'Demo'});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CashierHomeScreen(firestore: db, currentUserId: () => 'cashier'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Switch to owner'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
