import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/app/theme.dart';
import 'package:pos_app/screens/profile/profile_screen.dart';
import 'package:pos_app/screens/owner/owner_home_screen.dart';
import 'package:pos_app/screens/reports/reports_screen.dart';
import 'package:pos_app/widgets/motion.dart';
import '../support/owner_read_firestore.dart';

Future<OwnerReadFirestore> fixture() async {
  final db = OwnerReadFirestore();
  for (final id in ['A', 'B']) {
    await db.seed('users').doc(id).set({
      'fullName': 'Person $id',
      'email': '$id@example.invalid',
      'storeCode': id,
      'role': 'cashier',
    });
    await db.seed('stores').doc(id).set({
      'ownerUid': id,
      'storeName': 'Shop $id',
      'benefitNumber': '33000000',
    });
  }
  return db;
}

void main() {
  testWidgets('profile re-entry keeps visible data while refreshing the same account', (
    tester,
  ) async {
    final db = await fixture();
    Widget profile(bool active) => MaterialApp(
      theme: AppTheme.light,
      home: ProfileScreen(active: active, firestore: db, currentUserId: () => 'A'),
    );
    await tester.pumpWidget(profile(true));
    await tester.pumpAndSettle();
    expect(find.text('A@example.invalid'), findsOneWidget);
    await tester.pumpWidget(profile(false));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'users/A') await gate.future;
    };
    await db.seed('users').doc('A').update({'email': 'changed@example.invalid'});
    await tester.pumpWidget(profile(true));
    await tester.pump();
    expect(find.text('A@example.invalid'), findsOneWidget);
    expect(find.byType(HomeSkeleton), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('changed@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late profile response cannot overwrite another account and disposed reads are ignored',
    (tester) async {
      final db = await fixture();
      var uid = 'A';
      final gate = Completer<void>();
      db.beforeRead = (path, _) async {
        if (path == 'stores/A') await gate.future;
      };
      Widget profile() => MaterialApp(
        theme: AppTheme.light,
        home: ProfileScreen(firestore: db, currentUserId: () => uid),
      );
      await tester.pumpWidget(profile());
      await tester.pump();
      await tester.pump();
      uid = 'B';
      await tester.pumpWidget(profile());
      await tester.pumpAndSettle();
      expect(find.text('B@example.invalid'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('A@example.invalid'), findsNothing);
      expect(find.text('B@example.invalid'), findsOneWidget);
      final nextGate = Completer<void>();
      db.beforeRead = (path, _) async {
        if (path == 'users/A') await nextGate.future;
      };
      uid = 'A';
      await tester.pumpWidget(profile());
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      nextGate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('report queries start together and re-entry refreshes without a blocking spinner', (
    tester,
  ) async {
    final db = await fixture();
    final firstGate = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'sales') await firstGate.future;
    };
    Widget reports(bool active) => MaterialApp(
      theme: AppTheme.light,
      home: ReportsScreen(active: active, firestore: db, currentUserId: () => 'A'),
    );
    await tester.pumpWidget(reports(true));
    await tester.pump();
    await tester.pump();
    expect(db.reads, containsAll(['sales', 'products']));
    firstGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(reports(false));
    await tester.pumpAndSettle();
    final refreshGate = Completer<void>();
    db.beforeRead = (path, _) async {
      if (path == 'sales') await refreshGate.future;
    };
    await tester.pumpWidget(reports(true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    refreshGate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'owner dashboard retains its actual state and refreshes quietly after tab navigation',
    (tester) async {
      final db = await fixture();
      await db.seed('users').doc('A').update({'role': 'owner'});
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: OwnerHomeScreen(firestore: db, currentUserId: () => 'A'),
        ),
      );
      await tester.pumpAndSettle();
      Finder tab(String label) =>
          find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
      await tester.tap(tab('Dashboard'));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(ReportsScreen));
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      db.beforeRead = (path, _) async {
        if (path == 'users/A') await gate.future;
      };
      await tester.tap(tab('Dashboard'));
      await tester.pump();
      expect(identical(state, tester.state(find.byType(ReportsScreen))), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
