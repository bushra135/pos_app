import '../support/product_form.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/community_catalog.dart';
import 'package:pos_app/widgets/product_image.dart';

Finder field(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String photo;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFF2266AA), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    photo = 'data:image/png;base64,${base64Encode(png)}';
  });
  testWidgets(
    'Find Product fills metadata and a decodable photo, keeps edits and saves the photo',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('owner').set({'role': 'owner', 'storeCode': 'A'});
      await db.collection('catalog').doc('12345678').set({
        'name': 'Potato chips',
        'category': 'Snacks',
        'brand': 'Brand',
        'size': '21 g',
        'description': 'Salted chips',
        'image': photo,
        'contributedBy': 'store',
      });
      final service = BarcodeCatalogService(
        community: FirestoreCommunityCatalog(firestore: db, currentUserId: () => 'owner'),
        client: MockClient((_) async => throw StateError('Unexpected external request')),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductsScreen(firestore: db, currentUserId: () => 'owner', catalog: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(field('Barcode'), '12345678');
      await tester.tap(find.text('Find product info · free'));
      await tester.pumpAndSettle();
      expect(field('Category'), findsNothing);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
        findsNWidgets(4),
      );
      await openProductDetails(tester);
      for (final entry in {
        'Product name': 'Potato chips',
        'Category': 'Snacks',
        'Brand': 'Brand',
        'Size': '21 g',
        'Description': 'Salted chips',
      }.entries) {
        expect(tester.widget<TextField>(field(entry.key)).controller!.text, entry.value);
      }
      final preview = find.byWidgetPredicate((w) => w is ProductImage && w.source == photo);
      expect(preview, findsOneWidget);
      final displayed = tester.widget<Image>(
        find.descendant(of: preview, matching: find.byType(Image)),
      );
      expect(displayed.image, isA<MemoryImage>());
      expect(tester.widget<TextField>(field('Image URL')).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field('Price')).controller!.text, isEmpty);
      await tester.enterText(field('Product name'), 'Owner chips');
      await tester.enterText(field('Brand'), 'Owner brand');
      await tester.enterText(field('Price'), '0.200');
      await tester.enterText(field('Stock'), '10');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add product'));
      await tester.pumpAndSettle();
      final saved = (await db.collection('products').get()).docs.single.data();
      expect(saved['name'], 'Owner chips');
      expect(saved['brand'], 'Owner brand');
      expect(saved['size'], '21 g');
      expect(saved['description'], 'Salted chips');
      expect(saved['image'], photo);
      expect(saved['price'], 0.2);
      expect(saved['stock'], 10);
      expect(saved['storeCode'], 'A');
      expect(tester.takeException(), isNull);
    },
  );
}
