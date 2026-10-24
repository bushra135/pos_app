import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/ai/ai_assistant_screen.dart';
import 'package:pos_app/screens/reports/reports_screen.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await font.load();
  });
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'Assistant opens reports and returns to the same conversation at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final db = FakeFirebaseFirestore();
        await db.collection('users').doc('owner').set({
          'storeCode': 'A',
          'fullName': 'QA Owner',
        });
        await db.collection('products').doc('ours').set({
          'storeCode': 'A',
          'name': 'Coffee',
          'stock': 0,
          'minStock': 2,
        });
        await db.collection('products').doc('other').set({
          'storeCode': 'B',
          'name': 'Other store secret',
          'stock': 0,
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AiAssistantScreen(
              firestore: db,
              currentUserId: () => 'owner',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Low stock alerts');
        await tester.tap(find.byTooltip('Send message'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Coffee'), findsOneWidget);
        expect(find.textContaining('Other store secret'), findsNothing);
        await tester.enterText(find.byType(TextField), 'My next question');
        await tester.ensureVisible(find.text('Open reports'));
        await tester.tap(find.text('Open reports'));
        await tester.pumpAndSettle();
        expect(find.text('POS Reports'), findsOneWidget);
        expect(find.byTooltip('Back to assistant'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Back to assistant'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'My next question',
        );
        expect(find.text('Low stock alerts'), findsOneWidget);
        expect(find.textContaining('Coffee'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Report errors still allow returning to the previous screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReportsScreen(
                    returnToAssistant: true,
                    firestore: FakeFirebaseFirestore(),
                    currentUserId: () => null,
                  ),
                ),
              ),
              child: const Text('Open test reports'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open test reports'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load reports'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Open test reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
