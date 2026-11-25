import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/app_language.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/ai/ai_assistant_screen.dart';
import 'package:pos_app/screens/cart/cart_screen.dart';
import 'package:pos_app/screens/cashier/cashier_home_screen.dart';
import 'package:pos_app/screens/checkout/checkout_receipt_screen.dart';
import 'package:pos_app/screens/owner/offers_screen.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';
import 'package:pos_app/screens/products/products_screen.dart';
import 'package:pos_app/screens/reports/reports_screen.dart';
import 'package:pos_app/screens/reports/sales_history_screen.dart';
import 'package:pos_app/utils/cart_manager.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/widgets/sale_receipt_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the Arabic interface: every visible text on the main owner and cashier
/// screens must be translated. Brand and payment names are the only English allowed.
const _allowed = {'ShopPad', 'BenefitPay', 'PDF'};

Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('owner').set({
    'role': 'owner',
    'storeCode': 'S',
    'storeName': 'قرطاسية عائشة',
    'fullName': 'عائشة',
  });
  await db.collection('users').doc('c1').set({
    'role': 'cashier',
    'storeCode': 'S',
    'fullName': 'نورة',
    'isActive': true,
    'onDuty': true,
    'storeName': 'قرطاسية عائشة',
  });
  await db.collection('stores').doc('S').set({'ownerUid': 'owner', 'storeName': 'قرطاسية عائشة'});
  for (final p in [('p1', 'قلم أزرق', 64), ('p2', 'دفتر', 2), ('p3', 'عصير', 0)]) {
    await db.collection('products').doc(p.$1).set({
      'storeCode': 'S',
      'name': p.$2,
      'category': 'قرطاسية',
      'price': 0.5,
      'cost': 0.3,
      'stock': p.$3,
      'minStock': 5,
      'soldCount': 4,
      'barcode': p.$1,
      'image': '',
    });
  }
  final now = DateTime.now();
  for (var i = 0; i < 3; i++) {
    await db.collection('sales').doc('sale$i').set({
      'id': 'sale$i',
      'storeCode': 'S',
      'cashierUid': 'c1',
      'cashierName': 'نورة',
      'total': 1.5,
      'subtotal': 1.5,
      'tax': 0.136,
      'discount': 0.0,
      'status': 'completed',
      'type': 'sale',
      'paymentMethod': 'Cash',
      'createdAt': Timestamp.fromDate(now.subtract(Duration(hours: i + 1))),
      'items': [
        {
          'productId': 'p1',
          'barcode': 'p1',
          'name': 'قلم أزرق',
          'price': 0.5,
          'quantity': 3,
          'cost': 0.3,
        },
      ],
      'productIds': ['p1'],
    });
  }
  return db;
}

/// Latin words still on screen, after removing allowed names and short codes.
List<String> _englishOnScreen(WidgetTester tester) {
  final found = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    var rest = text;
    for (final word in _allowed) {
      rest = rest.replaceAll(word, '');
    }
    // Receipt codes such as #SZLXMV and barcodes are identifiers, not words.
    rest = rest.replaceAll(RegExp(r'#[A-Z0-9]+|RCPT-\S+'), '');
    if (RegExp(r'[A-Za-z]{3,}').hasMatch(rest)) found.add(text);
  }
  return found;
}

void main() {
  setUpAll(() {
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
  });
  setUp(() {
    AppLanguage.locale.value = AppLanguage.arabic;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    AppLanguage.locale.value = AppLanguage.english;
    CartManager.clearCart();
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: AppLanguage.arabic,
        supportedLocales: AppLanguage.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  void addCartItems() {
    CartManager.addItem(
      name: 'قلم أزرق',
      price: 0.5,
      barcode: 'p1',
      image: '',
      productId: 'p1',
      storeCode: 'S',
    );
    CartManager.addItem(
      name: 'دفتر',
      price: 1.75,
      barcode: 'p2',
      image: '',
      productId: 'p2',
      storeCode: 'S',
    );
  }

  final screens = <String, Future<Widget> Function()>{
    'owner home': () async =>
        OwnerHomeScreen(firestore: await _seed(), currentUserId: () => 'owner'),
    'cashier home': () async =>
        CashierHomeScreen(firestore: await _seed(), currentUserId: () => 'c1'),
    'cart': () async {
      addCartItems();
      return const CartScreen();
    },
    'checkout': () async {
      addCartItems();
      return CheckoutReceiptScreen(firestore: await _seed(), currentUserId: () => 'c1');
    },
    'products': () async => ProductsScreen(firestore: await _seed(), currentUserId: () => 'owner'),
    'dashboard': () async => ReportsScreen(firestore: await _seed(), currentUserId: () => 'owner'),
    'sales history': () async =>
        SalesHistoryScreen(firestore: await _seed(), currentUserId: () => 'owner'),
    'receipt after payment': () async => SaleReceiptView(
      sale: SaleRecord(
        id: 'ABC123',
        storeCode: 'S',
        storeName: 'قرطاسية عائشة',
        cashierUid: 'c1',
        cashierName: 'نورة',
        paymentMethod: 'Cash',
        createdAt: DateTime(2026, 11, 25, 9, 5),
        items: const [
          SaleLine(productId: 'p1', barcode: 'p1', name: 'قلم أزرق', price: 0.5, quantity: 2),
        ],
        discount: 0.1,
        vatRate: 10,
      ),
      status: 'Synchronized'.tr,
      onNewSale: () {},
    ),
    'offers and tips': () async =>
        OffersScreen(firestore: await _seed(), currentUserId: () => 'owner'),
    'assistant': () async =>
        AiAssistantScreen(firestore: await _seed(), currentUserId: () => 'owner'),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} shows no untranslated English in Arabic', (tester) async {
      await show(tester, await entry.value());
      expect(_englishOnScreen(tester), isEmpty);
    });
  }

  testWidgets('dashboard tabs show no untranslated English in Arabic', (tester) async {
    await show(tester, ReportsScreen(firestore: await _seed(), currentUserId: () => 'owner'));
    for (final tab in ['profit', 'products']) {
      await tester.tap(find.byKey(ValueKey('dashboard-tab-$tab')));
      await tester.pumpAndSettle();
      expect(_englishOnScreen(tester), isEmpty, reason: tab);
    }
  });
}
