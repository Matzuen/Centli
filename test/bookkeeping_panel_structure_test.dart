import 'dart:io';

import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/ledger/bookkeeping_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bookkeeping panel structure (source contract)', () {
    late String src;

    setUpAll(() {
      src = File('lib/features/ledger/bookkeeping_sheet.dart').readAsStringSync();
    });

    test('no title 记一笔 Text in build UI', () {
      // Snackbar/comments may mention 再记一笔; the title string must not appear as UI Text.
      expect(
        RegExp(r"Text\(\s*'记一笔").hasMatch(src),
        isFalse,
      );
      expect(src.contains("记一笔 ·"), isFalse);
    });

    test('no close IconButton in panel sheet body', () {
      // Account picker may have close; main sheet build must not.
      final buildIdx = src.indexOf('Widget build(BuildContext context)');
      final chipIdx = src.indexOf('class _ChipScrollRow');
      final build = src.substring(buildIdx, chipIdx);
      expect(build.contains('Icons.close'), isFalse);
    });

    test('keypad first row is AC backspace / *', () {
      expect(
        RegExp(
          r"\['AC',\s*'\\u232b',\s*'/',\s*'\*'\]|"
          r"\['AC',\s*'⌫',\s*'/',\s*'\*'\]",
        ).hasMatch(src),
        isTrue,
      );
    });

    test('keypad has = and 0 spans two cols via flex sum', () {
      expect(src.contains("'='"), isTrue);
      expect(src.contains('_colFlex[0] + _colFlex[1]'), isTrue);
    });

    test('type chip key present', () {
      expect(src.contains("Key('bk_type_chip')"), isTrue);
    });

    test('chip rows and note and keypad keys present', () {
      expect(src.contains("Key('bk_chip_row_1')"), isTrue);
      expect(src.contains("Key('bk_chip_row_2')"), isTrue);
      expect(src.contains("Key('bk_note')"), isTrue);
      expect(src.contains("Key('bk_keypad')"), isTrue);
    });
  });

  group('bookkeeping panel structure (behavior)', () {
    testWidgets('type chip visible and switches with category kind filter',
        (tester) async {
      final db = CentliDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.seedDefaults();

      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: CentliTheme.light(),
            home: const Scaffold(body: BookkeepingSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bk_type_chip')), findsOneWidget);
      expect(find.textContaining('支出'), findsWidgets);

      await tester.tap(find.byKey(const Key('bk_type_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();

      expect(find.textContaining('收入'), findsWidgets);

      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      final inCats = await db.loadCategories(ledger.id, 'in');
      final outCats = await db.loadCategories(ledger.id, 'out');
      expect(inCats, isNotEmpty);
      expect(outCats, isNotEmpty);
      expect(find.byKey(const Key('bk_type_chip')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('transfer hides category chip', (tester) async {
      final db = CentliDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.seedDefaults();

      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: CentliTheme.light(),
            home: const Scaffold(body: BookkeepingSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bk_type_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();

      expect(find.text('分类'), findsNothing);
      expect(find.textContaining('转出'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
