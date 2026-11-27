import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/app_colors.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/widgets/app_snack_bar.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('status notice fits narrow screen with action and enlarged text: $direction', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          scaffoldMessengerKey: key,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Directionality(
                textDirection: direction,
                child: const Scaffold(body: SizedBox.expand()),
              ),
            ),
          ),
        ),
      );
      var tapped = false;
      for (final color in [AppColors.success, AppColors.danger]) {
        key.currentState!.showSnackBar(
          appSnackBar(
            backgroundColor: color,
            content: Text(
              direction == TextDirection.rtl
                  ? 'تم حذف المنتج بنجاح والفواتير السابقة محفوظة'
                  : 'Product deleted successfully. Existing receipts are preserved.',
            ),
            action: SnackBarAction(
              label: direction == TextDirection.rtl ? 'عرض' : 'View',
              onPressed: () => tapped = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byIcon(
            color == AppColors.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(direction == TextDirection.rtl ? 'عرض' : 'View'));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
        tapped = false;
      }
    });
  }
}
