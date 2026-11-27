import 'package:flutter_test/flutter_test.dart';

Future<void> openProductDetails(WidgetTester tester) async {
  final details = find.text('Additional details (optional)');
  await tester.ensureVisible(details);
  await tester.tap(details);
  await tester.pumpAndSettle();
}
