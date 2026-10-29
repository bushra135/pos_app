import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/product_category_suggestion.dart';

void main() {
  test('suggests food and nonfood categories in English and Arabic', () {
    expect(
      ProductCategorySuggestion.fromName('Blue ballpoint pen 2 pack'),
      'Stationery',
    );
    expect(ProductCategorySuggestion.fromName('دفتر جامعي'), 'Stationery');
    expect(ProductCategorySuggestion.fromName('حليب المراعي'), 'Dairy');
    expect(ProductCategorySuggestion.fromName('USB charger'), 'Electronics');
    expect(ProductCategorySuggestion.fromName('شامبو للشعر'), 'Personal Care');
  });
  test('does not guess from substrings or unknown brands', () {
    expect(ProductCategorySuggestion.fromName('Open box'), isNull);
    expect(ProductCategorySuggestion.fromName('Brand X 123'), isNull);
    expect(ProductCategorySuggestion.fromName(''), isNull);
  });
  test('ambiguous names stay blank and specific phrases win', () {
    expect(
      ProductCategorySuggestion.fromName('Milk chocolate notebook'),
      isNull,
    );
    expect(ProductCategorySuggestion.fromName('Chocolate milk 1L'), 'Dairy');
  });
  testWidgets('name suggestions update and never replace a manual category', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({'storeCode': 'A'});
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Product Name');
    final category = find.widgetWithText(TextField, 'Category');
    String value() => tester.widget<TextField>(category).controller!.text;
    await tester.enterText(name, 'Blue pen');
    await tester.pump();
    expect(value(), 'Stationery');
    await tester.enterText(name, 'Milk');
    await tester.pump();
    expect(value(), 'Dairy');
    await tester.enterText(name, 'Unknown brand');
    await tester.pump();
    expect(value(), isEmpty);
    await tester.enterText(category, 'My category');
    await tester.enterText(name, 'Notebook');
    await tester.pump();
    expect(value(), 'My category');
  });
}
