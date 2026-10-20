import 'package:centli/app/theme.dart';
import 'package:centli/core/widgets/glass.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/settings/ledgers_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 毛玻璃弹窗的两条硬要求：
/// 1. 模糊**只作用在弹窗面板自己的范围**（不是给整页加一层模糊）；
/// 2. 面板是玻璃（半透明 + 描边），不是一块实色板。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    CentliGlass.blurEnabled = true;
  });

  tearDown(() async {
    CentliGlass.blurEnabled = true;
    await db.close();
  });

  Future<void> openLedgerDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
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
        child: MaterialApp(
          theme: CentliTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          home: const LedgersPage(),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.byType(FloatingActionButton));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('the dialog is glass and only it is blurred', (tester) async {
    await openLedgerDialog(tester);

    final dialog = find.byType(CentliGlassDialog);
    expect(dialog, findsOneWidget);

    // Exactly one backdrop filter: the dialog panel's own.
    final filters = find.byType(BackdropFilter, skipOffstage: false);
    expect(filters, findsOneWidget, reason: 'no full-screen frosted backdrop');

    final filterRect = tester.getRect(filters);
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(
      filterRect.width < screen.width - 1 || filterRect.height < screen.height - 1,
      isTrue,
      reason: 'the blur must not cover the whole screen (that would blur the '
          'page instead of the panel): $filterRect vs $screen',
    );

    // The panel is glass: translucent fill, not an opaque white slab.
    final panel = find.descendant(
      of: dialog,
      matching: find.byType(CentliGlass),
    );
    expect(panel, findsOneWidget);
    final glass = tester.widget<CentliGlass>(panel);
    final tint = glass.tint ?? CentliTheme.glassSurface(tester.element(panel));
    expect(tint.a, lessThan(1.0), reason: 'panel must be translucent');
    expect(glass.blur, isTrue, reason: 'the panel itself is frosted');

    expect(tester.takeException(), isNull);
  });

  testWidgets('cards are translucent but never blurred', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
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
        child: MaterialApp(
          theme: CentliTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          home: const LedgersPage(),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byType(CentliSoftCard), findsWidgets);
    final glasses = tester.widgetList<CentliGlass>(
      find.descendant(
        of: find.byType(CentliSoftCard),
        matching: find.byType(CentliGlass),
      ),
    );
    expect(glasses, isNotEmpty);
    for (final g in glasses) {
      expect(g.blur, isFalse, reason: 'cards must not pay for a backdrop blur');
    }
    // No blur filter is mounted for the cards at all.
    expect(find.byType(BackdropFilter, skipOffstage: false), findsNothing);
  });
}
