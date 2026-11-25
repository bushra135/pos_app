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
import 'package:pos_app/utils/active_offers.dart';
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
  tearDown(CartManager.clearCart);

  testWidgets('an active bundle offer is applied at checkout and saved on the receipt', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
    await db.collection('stores').doc('A').set({'storeName': 'Store A'});
    await db.collection('products').doc('pen').set({
      'storeCode': 'A',
      'name': 'Blue pen',
      'price': 0.5,
      'stock': 50,
    });
    await db.collection('products').doc('ruler').set({
      'storeCode': 'A',
      'name': 'Ruler',
      'price': 0.4,
      'stock': 18,
      ...ActiveOffer.startFields(anchorId: 'pen', anchorName: 'Blue pen', percent: 25),
    });

    final gateway = _RecordingGateway();
    late SaleSyncService sync;
    late Database local;
    await tester.runAsync(() async {
      local = await databaseFactoryMemory.openDatabase('offer-checkout');
      sync = SaleSyncService(
        store: LocalPosStore(local),
        gateway: gateway,
        currentUserId: () => 'cashier',
        firestore: db,
      );
      SaleSyncService.maybeInstance = sync;
      await sync.loadContext('cashier');
      // Let the live product listener fill the offline catalogue.
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
    CartManager.addItem(
      name: 'Ruler',
      price: 0.4,
      barcode: 'ruler',
      image: '',
      productId: 'ruler',
      storeCode: 'A',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CheckoutReceiptScreen(firestore: db, currentUserId: () => 'cashier'),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    // 2 pens unlock one ruler: 25% of BD 0.400 = BD 0.100.
    expect(find.text('Offer: Ruler 25% off with Blue pen'), findsOneWidget);
    expect(find.text('− BD 0.100'), findsOneWidget);
    expect(find.text('BD 1.300'), findsWidgets); // 1.400 − 0.100

    await tester.tap(find.textContaining('Confirm'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    final saved = gateway.sales.single;
    expect(saved.discount, 0.1);
    expect(saved.offerDiscount, 0.1);
    expect(saved.total, 1.3);
    expect(saved.offerNames, ['Blue pen + Ruler 25%']);
    expect(find.text('عرض مجمّع · Bundle offer'), findsOneWidget, reason: 'shown on the receipt');
  });
}
