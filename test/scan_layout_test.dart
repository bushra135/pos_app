import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:pos_app/services/barcode_catalog_service.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_sync_service.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/scan/scan_screen.dart';
import 'package:pos_app/utils/cart_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await font.load();
    for (final name in [
      'dev.steenbakker.mobile_scanner/scanner/event',
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
      (call) async => call.method == 'state' ? 2 : null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
  });
  setUp(CartManager.clearCart);
  tearDown(CartManager.clearCart);
  testWidgets(
    'An unknown barcode previews catalogue data without selling or creating stock',
    (tester) async {
      final db = await databaseFactoryMemory.openDatabase(
        'unknown-product-test',
      );
      final sync = _MissingProductSync(LocalPosStore(db));
      SaleSyncService.maybeInstance = sync;
      addTearDown(() async {
        SaleSyncService.maybeInstance = null;
        sync.dispose();
        await db.close();
      });
      var calls = 0;
      final catalog = BarcodeCatalogService(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            jsonEncode({
              'status': 'success',
              'product': {'code': '012345678905', 'product_name': 'Milk'},
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ScanScreen(catalog: catalog),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '012345678905');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('New barcode'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(CartManager.items, isEmpty);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SKU-123');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This lookup supports'), findsOneWidget);
      expect(calls, 1);
      expect(CartManager.items, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('browser camera opens inside Scan without a second button', (
    tester,
  ) async {
    final requests = <Completer<bool>>[];
    var reviews = 0;
    Future<bool> launch({
      required Future<String> Function(String) onBarcode,
      required String summary,
    }) {
      final request = Completer<bool>();
      requests.add(request);
      return request.future;
    }

    Widget view() => MaterialApp(
      theme: AppTheme.light,
      home: ScanScreen(browserCheckout: launch, onGoToCart: () => reviews++),
    );
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    requests.first.complete(false);
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    CartManager.addItem(name: 'Pen', price: 0.5, barcode: '1', image: '');
    expect(find.text('Open camera'), findsNothing);
    expect(find.text('Resume scanning'), findsNothing);
    expect(find.text('Current sale'), findsOneWidget);
    await tester.pumpWidget(view());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review sale'));
    expect(reviews, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'browser startup failure keeps retry and manual entry available',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ScanScreen(
            browserCheckout: ({required onBarcode, required summary}) async {
              calls++;
              throw StateError('Browser camera blocked');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        find.textContaining('Could not open browser camera'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry camera'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text('Enter barcode'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 800.0]) {
    testWidgets('Manual barcode entry and review stay usable at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      CartManager.addItem(
        name: 'Long product name to check narrow layouts',
        price: 1.125,
        barcode: '123',
        image: '',
      );
      var reviews = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ScanScreen(onGoToCart: () => reviews++),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Enter barcode'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12345');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('BD 1.125'), findsOneWidget);
      await tester.tap(find.text('Review sale'));
      expect(reviews, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}

class _MissingProductSync extends SaleSyncService {
  _MissingProductSync(LocalPosStore store)
    : super(
        store: store,
        gateway: _UnusedGateway(),
        currentUserId: () => 'cashier',
      );
  @override
  Future<Map<String, dynamic>> findProduct(
    String barcode, {
    bool preferCache = false,
  }) async => throw ProductNotFoundException(barcode);
}

class _UnusedGateway implements SaleGateway {
  @override
  Future<void> commit(SaleRecord sale) async =>
      throw StateError('No sale should be submitted');
}
