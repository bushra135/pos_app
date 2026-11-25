import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/reports/reports_screen.dart';
import 'package:pos_app/widgets/motion.dart';
import 'package:pos_app/widgets/welcome_overlay.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('count-up ends on the exact value', (tester) async {
    await tester.pumpWidget(
      _app(CountUpText(value: 48.75, format: (v) => 'BD ${v.toStringAsFixed(3)}')),
    );
    expect(find.text('BD 48.750'), findsNothing, reason: 'still counting');
    await tester.pumpAndSettle();
    expect(find.text('BD 48.750'), findsOneWidget);
  });

  testWidgets('with reduced motion numbers and entrances are immediate', (tester) async {
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            CountUpText(value: 12, format: (v) => v.round().toString()),
            const FadeSlideIn(index: 5, child: Text('Card')),
          ],
        ),
        reduced: true,
      ),
    );
    await tester.pump();
    expect(find.text('12'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Card'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 1);
  });

  testWidgets('the welcome shows once per sign-in and fades away', (tester) async {
    Widget gate() => _app(
      const WelcomeGate(
        uid: 'u-welcome',
        name: 'Maryam Ali',
        storeName: 'Al Reem',
        isOwner: true,
        child: Text('Home'),
      ),
    );
    await tester.pumpWidget(gate());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Maryam'), findsOneWidget);
    expect(find.text('Al Reem · Owner'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Maryam'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    // Same account again in this session: no welcome.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(gate());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Maryam'), findsNothing);
  });

  testWidgets('reduced motion skips the welcome', (tester) async {
    await tester.pumpWidget(
      _app(
        const WelcomeGate(
          uid: 'u-reduced',
          name: 'Noora',
          storeName: '',
          isOwner: false,
          child: Text('Home'),
        ),
        reduced: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Noora'), findsNothing);
  });

  testWidgets('the dashboard puts the most important recommendation first', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'role': 'owner', 'storeCode': 'A'});
    await db.collection('products').doc('juice').set({
      'storeCode': 'A',
      'name': 'Juice',
      'price': 0.3,
      'stock': 0,
      'minStock': 5,
    });
    await db.collection('sales').doc('s1').set({
      'storeCode': 'A',
      'type': 'sale',
      'status': 'completed',
      'total': 0.9,
      'subtotal': 0.9,
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 2))),
      'items': [
        {'productId': 'juice', 'name': 'Juice', 'price': 0.3, 'quantity': 3},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportsScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Most important now'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.textContaining('Juice is out of stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
