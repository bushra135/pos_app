import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/ai/ai_assistant_screen.dart';

void main() {
  testWidgets('Assistant fits narrow screens and compact viewports', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await font.load();
    final previewKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: previewKey,
          child: const AiAssistantScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(320, 420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Local analysis'), findsOneWidget);
    expect(find.text('Cloud AI'), findsNothing);
    await tester.tap(find.byTooltip('About this analysis mode'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No paid AI service or API key'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
