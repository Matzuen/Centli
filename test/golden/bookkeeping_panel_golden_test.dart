import 'dart:io';

import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/ledger/bookkeeping_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadGoldenFont() async {
  final file = File('test/golden/fonts/NotoSansSC.ttf');
  final bytes = await file.readAsBytes();
  final loader = FontLoader('NotoSansSC')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadGoldenFont();
  });

  Future<CentliDatabase> openDb() async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    return db;
  }

  ThemeData withGoldenFont(ThemeData base) {
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'NotoSansSC'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'NotoSansSC'),
    );
  }

  Future<void> pumpSheet(
    WidgetTester tester, {
    required CentliDatabase db,
    required ThemeData theme,
  }) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: withGoldenFont(theme),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: const BookkeepingSheet(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final k in ['1', '2', '3', '4', '.', '5', '6']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('bookkeeping panel golden light', (tester) async {
    final db = await openDb();
    addTearDown(db.close);
    await pumpSheet(tester, db: db, theme: CentliTheme.light());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bookkeeping_panel.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }, tags: ['golden']);

  testWidgets('bookkeeping panel golden dark', (tester) async {
    final db = await openDb();
    addTearDown(db.close);
    await pumpSheet(tester, db: db, theme: CentliTheme.dark());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/bookkeeping_panel_dark.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }, tags: ['golden']);
}
