import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/widgets/auth_background.dart';
import 'package:pos_app/widgets/auth_motion.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  ),
);

void main() {
  testWidgets('a field glows and its label turns brand colour while focused', (tester) async {
    await tester.pumpWidget(_app(const GlowField(label: 'Email address', child: TextField())));
    BoxShadow shadow() =>
        (tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
                as BoxDecoration)
            .boxShadow!
            .first;
    expect(shadow().blurRadius, 0);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(shadow().blurRadius, greaterThan(0));
  });

  testWidgets('the password eye flips and says what it will do', (tester) async {
    var visible = false;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) =>
              PasswordEye(visible: visible, onPressed: () => setState(() => visible = !visible)),
        ),
      ),
    );
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('an error banner opens with the message and closes again', (tester) async {
    String? message = 'Your email or password is incorrect.';
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Column(
              children: [
                ShakeOnChange(trigger: message == null ? 0 : 1, child: const Text('Fields')),
                InlineErrorBanner(message: message),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your email or password is incorrect.'), findsOneWidget);
    set(() => message = null);
    await tester.pumpAndSettle();
    expect(find.text('Your email or password is incorrect.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion the logo shows at once', (tester) async {
    await tester.pumpWidget(_app(const Center(child: BrandLogo()), reduced: true));
    await tester.pump();
    expect(find.byType(Hero), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('the sign-in background keeps moving, and stops with reduced motion', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(height: 400, child: AuthBackground())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'animating');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(const SizedBox(height: 400, child: AuthBackground()), reduced: true),
    );
    await tester.pumpAndSettle(); // settles: nothing is animating
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'the scanner frame scans, keeps scanning while busy, and is still with reduced motion',
    (tester) async {
      const box = SizedBox.square(dimension: 120);
      await tester.pumpWidget(_app(const ScanFrame(child: box)));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'idle beam');

      await tester.pumpWidget(_app(const ScanFrame(scanning: true, child: box)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'scanning beam');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_app(const ScanFrame(scanning: true, child: box), reduced: true));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
