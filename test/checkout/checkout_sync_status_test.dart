import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/screens/checkout/checkout_receipt_screen.dart';
import 'package:pos_app/services/local_pos_store.dart';
import 'package:pos_app/services/sale_gateway.dart';
import 'package:pos_app/services/sale_sync_service.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:pos_app/widgets/sale_receipt_view.dart';

class DelayedGateway implements SaleGateway {
  final result = Completer<void>();
  int calls = 0;
  @override
  Future<void> commit(SaleRecord sale) {
    calls++;
    return result.future;
  }
}

class QueuedCheckout extends SaleSyncService {
  QueuedCheckout(LocalPosStore store)
    : super(
        store: store,
        gateway: DelayedGateway(),
        currentUserId: () => 'cashier',
      );
  int calls = 0;
  void confirmLater() {
    online = true;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> loadContext(String uid) async => {
    'profile': {'storeCode': 'A', 'fullName': 'Cashier'},
    'store': {'storeName': 'Test Store'},
  };
  @override
  Future<SaleSubmission> submit(SaleRecord sale) async {
    calls++;
    return const SaleSubmission(
      SaleSubmissionStatus.queued,
      'Server confirmation is taking longer than expected.',
    );
  }
}

SaleRecord sample() => SaleRecord(
  id: 'late',
  storeCode: 'A',
  storeName: 'Test',
  cashierUid: 'cashier',
  cashierName: 'Cashier',
  paymentMethod: 'Cash',
  createdAt: DateTime.utc(2026),
  items: const [
    SaleLine(
      productId: 'p1',
      barcode: '123',
      name: 'Pen',
      price: 3,
      quantity: 1,
    ),
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    for (final name in [
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers.global',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
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
  testWidgets(
    'queued receipt is ready without a spinner behind the notice or duplicate submission',
    (tester) async {
      final database = await databaseFactoryMemory.openDatabase(
        'checkout-ready',
      );
      final sync = QueuedCheckout(LocalPosStore(database));
      SaleSyncService.maybeInstance = sync;
      addTearDown(() async {
        SaleSyncService.maybeInstance = null;
        sync.dispose();
        CartManager.clearCart();
        await database.close();
      });
      CartManager.addItem(
        name: 'Pen',
        price: 3,
        barcode: '123',
        image: '',
        productId: 'p1',
        storeCode: 'A',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: CheckoutReceiptScreen(
            firestore: FakeFirebaseFirestore(),
            currentUserId: () => 'cashier',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final confirm = find.text('Confirm Cash Payment');
      await tester.scrollUntilVisible(confirm, 350);
      final button = tester.widget<ElevatedButton>(
        find.ancestor(of: confirm, matching: find.byType(ElevatedButton)),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Receipt saved — sync pending'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SaleReceiptView), findsOneWidget);
      expect(sync.calls, 1);
      expect(CartManager.items, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(SaleReceiptView), findsOneWidget);
      sync.confirmLater();
      await tester.pump();
      expect(
        tester.widget<SaleReceiptView>(find.byType(SaleReceiptView)).status,
        'Synchronized',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final succeeds in [true, false]) {
    test(
      'late server confirmation cleans queue only on success: $succeeds',
      () async {
        final database = await databaseFactoryMemory.openDatabase(
          'late-$succeeds',
        );
        final local = LocalPosStore(database);
        final gateway = DelayedGateway();
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('products').doc('p1').set({
          'storeCode': 'A',
          'barcode': '123',
          'name': 'Pen',
          'stock': 10,
          'price': 3,
        });
        final sync = SaleSyncService(
          store: local,
          gateway: gateway,
          currentUserId: () => 'cashier',
          firestore: firestore,
          requestTimeout: const Duration(milliseconds: 30),
        );
        addTearDown(() async {
          sync.dispose();
          await database.close();
        });
        await sync.bind('cashier', 'A');
        await Future<void>.delayed(Duration.zero);
        await local.cacheProducts('A', [
          {
            'id': 'p1',
            'storeCode': 'A',
            'barcode': '123',
            'name': 'Pen',
            'stock': 10,
            'price': 3,
          },
        ]);
        sync.online = true;
        final response = await sync.submit(sample());
        expect(response.status, SaleSubmissionStatus.queued);
        expect(response.message, contains('background'));
        expect(await local.pendingSales('cashier', 'A'), hasLength(1));
        if (succeeds) {
          gateway.result.complete();
        } else {
          gateway.result.completeError(StateError('Server unavailable'));
        }
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          await local.pendingSales('cashier', 'A'),
          succeeds ? isEmpty : hasLength(1),
        );
        expect(gateway.calls, 1);
      },
    );
  }
}
