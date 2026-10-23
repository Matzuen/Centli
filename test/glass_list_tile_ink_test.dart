import 'package:centli/core/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CentliGlass 内层 DecoratedBox 曾挡住 ListTile 水波纹：
/// Material(transparency) 必须在 tint 之内，visit 才能停在 Material。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ListTile under CentliGlass does not assert on ink', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CentliGlass(
            child: ListTile(
              title: const Text('row'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListTile under sheet-shaped CentliGlass (top radius 24) is fine',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CentliGlass(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            tint: Colors.white.withValues(alpha: 0.2),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('pick type'),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
