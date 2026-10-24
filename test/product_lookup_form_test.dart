import 'dart:convert';
import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';

void main() {
  for (final outcome in ['missing', 'timeout', 'cancel', 'found']) {
    for (final replaceParent in [false, true]) {
      testWidgets('Lookup $outcome with parent replaced: $replaceParent', (
        tester,
      ) async {
        final font = FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
        await font.load();
        final showProducts = ValueNotifier(true);
        addTearDown(showProducts.dispose);
        final db = FakeFirebaseFirestore();
        await db.collection('users').doc('owner').set({'storeCode': 'A'});
        final response = Completer<http.Response>();
        final catalog = BarcodeCatalogService(
          client: MockClient((_) => response.future),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ValueListenableBuilder<bool>(
              valueListenable: showProducts,
              builder: (context, visible, child) => visible
                  ? ProductsScreen(
                      firestore: db,
                      currentUserId: () => 'owner',
                      catalog: catalog,
                    )
                  : const SizedBox(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Barcode'),
          '70850307258913',
        );
        await tester.tap(find.text('Find product info · free'));
        await tester.pump();
        expect(find.text('Finding product…'), findsOneWidget);
        if (replaceParent) {
          showProducts.value = false;
          await tester.pump();
        }
        if (outcome == 'timeout') {
          await tester.pump(const Duration(seconds: 6));
        } else if (outcome == 'cancel') {
          await tester.tap(find.text('Stop lookup'));
          await tester.pump();
          response.complete(
            outcome == 'found'
                ? http.Response(
                    jsonEncode({
                      'status': 'success',
                      'product': {
                        'code': '70850307258913',
                        'product_name': 'Test product',
                      },
                    }),
                    200,
                  )
                : http.Response('{}', 404),
          );
        } else {
          response.complete(
            outcome == 'found'
                ? http.Response(
                    jsonEncode({
                      'status': 'success',
                      'product': {
                        'code': '70850307258913',
                        'product_name': 'Test product',
                      },
                    }),
                    200,
                  )
                : http.Response('{}', 404),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Finding product…'), findsNothing);
        expect(
          find.textContaining(
            outcome == 'missing'
                ? 'Not found in the free product catalogues'
                : outcome == 'timeout'
                ? 'Product lookup timed out'
                : outcome == 'found'
                ? 'Product found.'
                : 'Lookup stopped',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
