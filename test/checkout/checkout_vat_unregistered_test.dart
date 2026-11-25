import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/screens/checkout/checkout_receipt_screen.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/sale_sync_service.dart';
import 'package:pos_app/utils/vat_invoice.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingGateway implements SaleGateway {
  final sales = <SaleRecord>[];
  @override
  Future<void> commit(SaleRecord sale) async => sales.add(sale);
}

void main() {
  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    // Each player opens its own event channel; answer it so the success sound is silent.
    messenger.setMockMethodCallHandler(const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['playerId'];
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$id'),
          (_) async => null,
        );
      }
      return null;
    });
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(CartManager.clearCart);

  Future<(_RecordingGateway, SaleSyncService)> open(
    WidgetTester tester,
    Map<String, dynamic> store,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('cashier').set({
      'storeCode': 'A',
      'fullName': 'Noora',
      'role': 'cashier',
      'isActive': true,
    });
    await db.collection('stores').doc('A').set({'storeName': 'Store A', ...store});
    await db.collection('products').doc('pen').set({
      'storeCode': 'A',
      'name': 'Blue pen',
      'price': 0.5,
      'stock': 50,
    });
    final gateway = _RecordingGateway();
    late SaleSyncService sync;
    late Database local;
    await tester.runAsync(() async {
      local = await databaseFactoryMemory.openDatabase('vat-${store.hashCode}');
      sync = SaleSyncService(
        store: LocalPosStore(local),
        gateway: gateway,
        currentUserId: () => 'cashier',
        firestore: db,
      );
      SaleSyncService.maybeInstance = sync;
      await sync.loadContext('cashier');
    });
    addTearDown(() async {
      SaleSyncService.maybeInstance = null;
      sync.dispose();
      await local.close();
    });
    for (var i = 0; i < 2; i++) {
      CartManager.addItem(
        name: 'Blue pen',
        price: 0.5,
        barcode: 'pen',
        image: '',
        productId: 'pen',
        storeCode: 'A',
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CheckoutReceiptScreen(firestore: db, currentUserId: () => 'cashier'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    return (gateway, sync);
  }

  Future<void> pay(WidgetTester tester) async {
    await tester.tap(find.textContaining('Confirm'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('a store that is not VAT-registered collects and shows no VAT', (tester) async {
    final (gateway, _) = await open(tester, {'vatRegistered': false, 'vatNumber': ''});
    expect(find.textContaining('VAT'), findsNothing);
    expect(find.text('Full tax invoice for the customer'), findsNothing);
    await pay(tester);

    final sale = gateway.sales.single;
    expect(sale.vatRate, 0);
    expect(sale.tax, 0);
    expect(sale.total, 1.0);
    expect(sale.invoiceKind, InvoiceKind.receipt);
    expect(sale.storeVatNumber, isEmpty);
    expect(find.text('إيصال · Receipt'), findsOneWidget);
    expect(find.textContaining('VAT'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
