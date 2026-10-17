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

/// Fallback after serial runs still showed ~0.01% antialias jitter (G1).
/// Cap is 0.01% (one-fifth of prior tolerance). Guarded by golden_guard_test (G5).
const double kGoldenMaxDiffPercent = 0.01;

class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) return true;
    return result.diffPercent <= kGoldenMaxDiffPercent;
  }
}


Future<void> loadGoldenFont() async {
  final file = File('test/golden/fonts/NotoSansSC.ttf');
  final bytes = await file.readAsBytes();
  final loader = FontLoader('NotoSansSC')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail('未设置，无法加载 MaterialIcons；'
        '请在 flutter test 环境下运行，或显式设置 FLUTTER_ROOT');
  }
  var file = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!file.existsSync()) {
    file = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  }
  if (!file.existsSync()) {
    fail('找不到 MaterialIcons 字体：${file.path}');
  }
  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadGoldenFont();
    await loadIconFont();
    goldenFileComparator = _TolerantGoldenComparator(
      Uri.parse('test/golden/bookkeeping_panel_golden_test.dart'),
    );
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
          debugShowCheckedModeBanner: false,
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
