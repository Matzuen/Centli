import 'package:centli/app/theme.dart';
import 'package:centli/core/widgets/txn_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(
    WidgetTester tester, {
    bool enabled = true,
    VoidCallback? onCopy,
    VoidCallback? onDelete,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: TxnSwipeHost(
              enabled: enabled,
              onCopy: onCopy ?? () {},
              onDelete: onDelete ?? () {},
              child: const SizedBox(
                height: 72,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('流水行')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('左滑露出删除与复制新建', (tester) async {
    await pumpHost(tester);
    var state = tester.state<TxnSwipeHostState>(find.byType(TxnSwipeHost));
    expect(state.offset, closeTo(0, 0.5));

    await tester.drag(find.text('流水行'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsOneWidget);
    expect(find.text('复制新建'), findsOneWidget);
    expect(find.text('编辑'), findsNothing);
    state = tester.state<TxnSwipeHostState>(find.byType(TxnSwipeHost));
    expect(state.offset, closeTo(-TxnSwipeHost.startActionsExtent, 0.5));
  });

  testWidgets('右滑不露出编辑且偏移保持为 0', (tester) async {
    await pumpHost(tester);

    await tester.drag(find.text('流水行'), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(find.text('编辑'), findsNothing);
    final state = tester.state<TxnSwipeHostState>(find.byType(TxnSwipeHost));
    expect(state.offset, closeTo(0, 0.5));
  });

  testWidgets('点删除触发回调并收起', (tester) async {
    var deleted = false;
    await pumpHost(tester, onDelete: () => deleted = true);

    await tester.drag(find.text('流水行'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    final state = tester.state<TxnSwipeHostState>(find.byType(TxnSwipeHost));
    expect(state.offset, closeTo(0, 0.5));
  });

  testWidgets('多选禁用滑动', (tester) async {
    await pumpHost(tester, enabled: false);

    await tester.drag(find.text('流水行'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsNothing);
    expect(find.byType(TxnSwipeHost), findsOneWidget);
  });

  testWidgets('长按区域仍在 child 上（不吞手势）', (tester) async {
    var longPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: TxnSwipeHost(
            onCopy: () {},
            onDelete: () {},
            child: SizedBox(
              height: 72,
              width: double.infinity,
              child: GestureDetector(
                onLongPress: () => longPressed = true,
                child: const ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('流水行')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.text('流水行'));
    await tester.pump();
    expect(longPressed, isTrue);
  });
}
