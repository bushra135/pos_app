import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/models/sale_record.dart';
import 'package:pos_app/screens/reports/sales_history_screen.dart';
import 'package:pos_app/screens/reports/reports_screen.dart';
import 'package:pos_app/widgets/sale_receipt_view.dart';

final today = DateTime(2026, 10, 29, 12);
Future<void> addSale(
  FakeFirebaseFirestore db,
  String id,
  String uid,
  String name,
  double total, {
  String store = 'A',
  DateTime? date,
  String status = 'completed',
  bool refund = false,
  bool correction = false,
}) async {
  final sale = SaleRecord(
    id: id,
    storeCode: store,
    storeName: 'Test Store',
    cashierUid: uid,
    cashierName: name,
    paymentMethod: 'Cash',
    createdAt: date ?? today,
    items: [
      SaleLine(
        productId: 'pen',
        barcode: '123',
        name: 'Blue Pen',
        price: total,
        quantity: 1,
      ),
    ],
  );
  await db.collection('sales').doc(id).set({
    ...sale.toJson(),
    'createdAt': Timestamp.fromDate(date ?? today),
    'status': status,
    'type': refund ? 'refund' : 'sale',
    if (correction)
      'stockCorrections': [
        {
          'name': 'Blue Pen',
          'stockBefore': 3,
          'addedQuantity': 2,
          'quantitySold': 5,
          'stockAfter': 0,
        },
      ],
  });
}

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  for (final entry in {
    'owner': 'Owner Person',
    'a': 'Alice Person',
    'b': 'Bob Person',
  }.entries) {
    await db.collection('users').doc(entry.key).set({
      'storeCode': 'A',
      'role': entry.key == 'owner' ? 'owner' : 'cashier',
      'fullName': entry.value,
    });
  }
  await addSale(db, 'alice-1', 'a', 'Alice', 10);
  await addSale(db, 'alice-2', 'a', 'Alice', 5);
  await addSale(db, 'alice-old', 'a', 'Alice', 40, date: DateTime(2026, 9, 1));
  await addSale(db, 'bob', 'b', 'Bob', 25, correction: true);
  await addSale(db, 'owner-sale', 'owner', 'Owner', 999);
  await addSale(db, 'pending', 'a', 'Alice', 10000, status: 'pending');
  await addSale(db, 'refund', 'b', 'Bob', 1000, refund: true);
  await addSale(db, 'foreign', 'b', 'Foreign secret', 99999, store: 'B');
  return db;
}

Widget view(
  FakeFirebaseFirestore db, {
  String uid = 'owner',
  bool top = false,
}) => MaterialApp(
  theme: AppTheme.light,
  home: SalesHistoryScreen(
    firestore: db,
    showTopCashiers: top,
    currentUserId: () => uid,
    now: () => today,
  ),
);
void main() {
  setUpAll(() async {
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
  });
  testWidgets(
    'combined filters export only matching store receipts and clear resets',
    (tester) async {
      final db = await seed();
      await db.collection('sales').doc('bob').update({
        'paymentMethod': 'Card',
        'items': [
          {
            'productId': 'pen',
            'barcode': '123',
            'name': 'Blue Pen',
            'quantity': 2,
            'price': 1.0,
          },
          {
            'productId': 'coffee',
            'barcode': '456',
            'name': 'Coffee',
            'quantity': 1,
            'price': 23.0,
          },
        ],
      });
      String? exported, filename;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SalesHistoryScreen(
            firestore: db,
            currentUserId: () => 'owner',
            now: () => today,
            exportReport: (csv, name) async {
              exported = csv;
              filename = name;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All payments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All products'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue Pen · 123').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('completed').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters (4)'), findsOneWidget);
      expect(
        find.text('1 receipts · Net receipt total: BD 25.000'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Selected product: 2 units · BD 2.000'),
        findsOneWidget,
      );
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(filename, 'shoppad-sales-20261029.csv');
      expect(exported, contains('RCPT-bob'));
      expect(exported, isNot(contains('RCPT-alice')));
      expect(exported, isNot(contains('RCPT-foreign')));
      expect(exported!.split('\r\n').length, 3);
      await tester.tap(find.byTooltip('Clear report filters'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7 receipts ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'custom dates include the entire end day and cancelled picker preserves range',
    (tester) async {
      final db = await seed();
      await addSale(
        db,
        'late',
        'a',
        'Alice',
        2,
        date: DateTime(2026, 9, 1, 23, 59),
      );
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SalesHistoryScreen(
            firestore: db,
            currentUserId: () => 'owner',
            now: () => today,
            selectDateRange: (context, current) async => picks++ == 0
                ? DateTimeRange(
                    start: DateTime(2026, 9, 1),
                    end: DateTime(2026, 9, 1),
                  )
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom range').last);
      await tester.pumpAndSettle();
      expect(
        find.text('2 receipts · Net receipt total: BD 42.000'),
        findsOneWidget,
      );
      await tester.tap(find.text('Custom range').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom range').last);
      await tester.pumpAndSettle();
      expect(
        find.text('2 receipts · Net receipt total: BD 42.000'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'owner history and cashier ranking are scoped and usable at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final db = await seed();
        await tester.pumpWidget(view(db));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('7 receipts · Net receipt total:'),
          findsOneWidget,
        );
        expect(find.textContaining('Foreign secret'), findsNothing);
        expect(find.text('Top cashiers'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(view(db, top: true));
        await tester.pumpAndSettle();
        expect(find.text('Best cashier · Alice Person'), findsOneWidget);
        expect(find.text('BD 55.000'), findsOneWidget);
        expect(find.text('BD 25.000'), findsOneWidget);
        expect(find.textContaining('Owner Person'), findsNothing);
        await tester.tap(find.text('All time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Today').last);
        await tester.pumpAndSettle();
        expect(find.text('Best cashier · Bob Person'), findsOneWidget);
        await addSale(db, 'bob-new', 'b', 'Bob', 30);
        await tester.pumpAndSettle();
        expect(find.text('Best cashier · Bob Person'), findsOneWidget);
        expect(find.text('BD 55.000'), findsOneWidget);
        await tester.tap(find.text('Best cashier · Bob Person'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('3 receipts · Net receipt total:'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'receipt search opens items, stock correction audit, PDF and returns to history',
    (tester) async {
      final db = await seed();
      await tester.pumpWidget(view(db));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'RCPT-bob');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 receipts · Net receipt total:'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ListTile, 'RCPT-bob'));
      await tester.pumpAndSettle();
      expect(find.text('Cashier: Bob'), findsOneWidget);
      expect(find.textContaining('Barcode: 123'), findsOneWidget);
      final sheetScroll = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Stock corrections'),
        200,
        scrollable: sheetScroll,
      );
      expect(find.text('Blue Pen: 3 + 2 − 5 = 0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('View receipt / PDF'),
        150,
        scrollable: sheetScroll,
      );
      await tester.tap(find.text('View receipt / PDF'));
      await tester.pumpAndSettle();
      expect(find.byType(SaleReceiptView), findsOneWidget);
      expect(find.text('Back to history'), findsOneWidget);
      await tester.tap(find.text('Back to history'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 receipts · Net receipt total:'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'equal cashier scores share top rank and identical names remain separate',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('owner').set({
        'storeCode': 'A',
        'role': 'owner',
      });
      for (final uid in ['sam-a', 'sam-b']) {
        await db.collection('users').doc(uid).set({
          'storeCode': 'A',
          'role': 'cashier',
          'fullName': 'Sam',
        });
        await addSale(db, uid, uid, 'Sam', 10);
      }
      await addSale(db, 'missing-cashier-id', '', 'Sam', 10000);
      await tester.pumpWidget(view(db, top: true));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.pumpAndSettle();
      expect(find.textContaining('Joint top cashier · Sam'), findsNWidgets(2));
      expect(find.text('BD 10.000'), findsNWidgets(2));
      expect(find.text('BD 20.000'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty history does not invent a best cashier', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('owner').set({
      'storeCode': 'A',
      'role': 'owner',
    });
    await tester.pumpWidget(view(db, top: true));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.pumpAndSettle();
    expect(
      find.text('No completed cashier sales for this period.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cashiers cannot open owner history', (tester) async {
    final db = await seed();
    await tester.pumpWidget(view(db, uid: 'a'));
    await tester.pumpAndSettle();
    expect(find.text('Owner access required.'), findsOneWidget);
    expect(find.text('All receipts'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('owner reaches history from Reports and returns', (tester) async {
    final db = await seed();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportsScreen(firestore: db, currentUserId: () => 'owner'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales history'));
    await tester.pumpAndSettle();
    expect(find.byType(SalesHistoryScreen), findsOneWidget);
    expect(find.text('Top cashiers'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('Top cashiers'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
