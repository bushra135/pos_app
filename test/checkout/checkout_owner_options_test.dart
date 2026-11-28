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
import 'package:pos_app/utils/cart_manager.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingGateway implements SaleGateway {
  final sales = <SaleRecord>[];
  @override
  Future<void> commit(SaleRecord sale) async => sales.add(sale);
}

// Owner view of checkout: discounts and full tax invoices stay available to the owner.
// Kept in its own file: these checkout tests share the app-wide cart and sync service.
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
    Map<String, dynamic> store, {
    String role = 'cashier',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('cashier').set({
      'storeCode': 'A',
      'fullName': 'Noora',
      'role': role,
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

  testWidgets('the owner can still add a discount and a full tax invoice', (tester) async {
    await open(tester, {
      'vatRegistered': true,
      'vatNumber': '123456789012345',
      'storeAddress': 'Seef Mall, Shop 12, Manama, Kingdom of Bahrain',
    }, role: 'owner');
    expect(find.text('Add discount'), findsOneWidget);
    expect(find.text('Full tax invoice for the customer'), findsOneWidget);

    // A 20% discount lowers the amount paid and the VAT inside it (moved from discount_vat_test).
    await tester.tap(find.text('Add discount'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
      '20',
    );
    await tester.pumpAndSettle();
    expect(find.text('Customer pays BD 0.800'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('− BD 0.200'), findsOneWidget);
    expect(find.text('BD 0.073'), findsOneWidget); // VAT inside BD 0.800
    expect(find.text('Discount 20% · Edit'), findsOneWidget);

    // Finish the sale so the cart and local store close cleanly, like the other tests.
    await pay(tester);
  });
}
