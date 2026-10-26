import 'package:centli/app/theme.dart';
import 'package:centli/core/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('undo snack shows 已删除・撤销 and fires onUndo', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showGlassUndoSnackBar(
                    context,
                    message: '已删除',
                    onUndo: () {
                      undone = true;
                    },
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('已删除'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('・'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(undone, isTrue);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('undo snack auto-dismisses around 4s', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showGlassUndoSnackBar(context, message: '已修改', onUndo: () {});
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('已修改'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('已修改'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('已修改'), findsNothing);
  });

  test('inferGlassSnackTone treats 已修改 as success', () {
    expect(inferGlassSnackTone('已修改'), GlassSnackTone.success);
    expect(inferGlassSnackTone('已删除'), GlassSnackTone.success);
  });
}
