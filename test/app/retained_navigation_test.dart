import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/retained_tab_body.dart';

class _Page extends StatefulWidget {
  const _Page(this.id, this.created, this.closed);
  final int id;
  final List<int> created, closed;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.id);
  }

  @override
  void dispose() {
    widget.closed.add(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(key: ValueKey('field-${widget.id}'));
}

void main() {
  testWidgets('retained destinations load lazily, preserve edits and dispose camera destinations', (
    tester,
  ) async {
    final created = <int>[], closed = <int>[];
    Future<void> tab(int index, {String scope = 'A'}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetainedTabBody(
              key: ValueKey(scope),
              index: index,
              retained: const {2, 3},
              builder: (id) => _Page(id, created, closed),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await tab(0);
    expect(created, [0]);
    await tab(2);
    expect(created, [0, 2]);
    await tester.enterText(find.byKey(const ValueKey('field-2')), 'unsaved profile edit');
    await tab(1);
    expect(created, [0, 2, 1]);
    expect(closed, contains(0));
    await tab(2);
    expect(created.where((id) => id == 2), hasLength(1));
    expect(closed, contains(1));
    expect(find.text('unsaved profile edit'), findsOneWidget);
    await tab(3);
    await tab(2);
    expect(created.where((id) => id == 2), hasLength(1));
    await tab(2, scope: 'other-account-store');
    expect(created.where((id) => id == 2), hasLength(2));
    expect(find.text('unsaved profile edit', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
