import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/screens/scan/scan_screen.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/sale_sync_service.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:sembast/sembast_memory.dart';

/// Records show zero stock unless the cashier confirms a miscount.
class _SoldOutSync extends SaleSyncService {
  _SoldOutSync(LocalPosStore store)
    : super(store: store, gateway: _UnusedGateway(), currentUserId: () => 'cashier');

  final requests = <bool>[];

  @override
  Future<Map<String, dynamic>> findProduct(
    String barcode, {
    bool preferCache = false,
    bool allowStockCorrection = false,
  }) async {
    requests.add(allowStockCorrection);
    if (!allowStockCorrection) throw OutOfStockException('Notebook');
    return {
      'id': 'notebook',
      'name': 'Notebook',
      'price': 1.75,
      'barcode': barcode,
      'storeCode': 'A',
      'image': '',
      'stock': 0,
    };
  }
}

class _UnusedGateway implements SaleGateway {
  @override
  Future<void> commit(SaleRecord sale) async => throw StateError('No sale should be submitted');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Cairo')..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
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

  Future<_SoldOutSync> scanSoldOut(WidgetTester tester, String name) async {
    final db = await databaseFactoryMemory.openDatabase(name);
    final sync = _SoldOutSync(LocalPosStore(db));
    SaleSyncService.maybeInstance = sync;
    addTearDown(() async {
      SaleSyncService.maybeInstance = null;
      sync.dispose();
      await db.close();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const ScanScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter barcode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '789');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Out of stock in the system'), findsOneWidget);
    return sync;
  }

  testWidgets('cashier can sell an item the records show as sold out', (tester) async {
    final sync = await scanSoldOut(tester, 'miscount-sell');
    await tester.tap(find.text('Sell as miscounted'));
    await tester.pumpAndSettle();

    expect(sync.requests, [false, true]);
    expect(CartManager.items.single.name, 'Notebook');
    expect(find.textContaining('added as miscounted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling keeps the sold-out item out of the cart', (tester) async {
    final sync = await scanSoldOut(tester, 'miscount-cancel');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(sync.requests, [false]);
    expect(CartManager.items, isEmpty);
    expect(find.textContaining('not added: recorded stock is 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
