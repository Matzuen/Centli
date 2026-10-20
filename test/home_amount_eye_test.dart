import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/home/home_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 眼睛按钮只在资产锁开启时出现 —— 没开锁时没有任何可隐藏的东西。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: CentliTheme.light(), home: const HomePage()),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Finder eyeIcons() => find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.visibility_outlined ||
                w.icon == Icons.visibility_off_outlined),
      );

  testWidgets('no eye when 资产锁 is off', (tester) async {
    await pumpHome(tester);
    expect(eyeIcons(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eye appears once 资产锁 is on and amounts are hidden',
      (tester) async {
    await db.setAppLockEnabled(true);
    await pumpHome(tester);
    expect(eyeIcons(), findsOneWidget);
    // The lock is on and nothing was revealed this session → concealed state.
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
