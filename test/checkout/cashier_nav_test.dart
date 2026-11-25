import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/cashier/cashier_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });

  testWidgets('the cashier bottom bar keeps a Scan button next to Start sale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('c1').set({
      'role': 'cashier',
      'storeCode': 'S',
      'fullName': 'Noora',
      'isActive': true,
      'storeName': 'Test Store',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CashierHomeScreen(firestore: db, currentUserId: () => 'c1'),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    final labels = tester
        .widgetList<NavigationDestination>(
          find.descendant(of: bar, matching: find.byType(NavigationDestination)),
        )
        .map((d) => d.label)
        .toList();
    expect(labels, ['Home', 'Scan', 'Cart', 'Profile']);
    expect(find.text('Start sale'), findsWidgets, reason: 'the home shortcut stays too');
    expect(tester.takeException(), isNull);
  });
}
