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

    test('no title Text in build UI', () {
      expect(
        RegExp(r"Text\(\s*'记一笔").hasMatch(src),
        isFalse,
      );
      expect(src.contains("记一笔 ·"), isFalse);
    });

    test('no close IconButton in panel sheet body', () {
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

    test('type switcher key present; type chip removed', () {
      expect(src.contains("Key('bk_type_switcher')"), isTrue);
      expect(src.contains("Key('bk_type_chip')"), isFalse);
      expect(src.contains("bk_type_seg_"), isTrue);
    });

    test('single chips row; old dual rows gone', () {
      expect(src.contains("Key('bk_chips_row')"), isTrue);
      expect(src.contains("Key('bk_chip_row_1')"), isFalse);
      expect(src.contains("Key('bk_chip_row_2')"), isFalse);
      expect(src.contains("Key('bk_note')"), isTrue);
      expect(src.contains("Key('bk_keypad')"), isTrue);
    });

    test('currency MetaChip removed', () {
      expect(src.contains('Icons.payments_outlined'), isFalse);
    });

    test('member chip removed; order time category account tags', () {
      expect(src.contains('_pickMember'), isFalse);
      expect(src.contains('_memberCtrl'), isFalse);
      expect(src.contains('Icons.person_outline'), isFalse);
      expect(src.contains("? '成员'"), isFalse);
      final chipsIdx = src.indexOf("Key('bk_chips_row')");
      final noteIdx = src.indexOf("Key('bk_note')");
      final chips = src.substring(chipsIdx, noteIdx);
      expect(chips.contains("_happenAtLabel"), isTrue);
      expect(chips.contains("'分类'"), isTrue);
      expect(chips.contains("'资产账户'") || chips.contains("'转出'"), isTrue);
      expect(chips.contains("'标签'"), isTrue);
      expect(chips.contains("'成员'"), isFalse);
    });

    test('txn template suffix gone', () {
      expect(src.contains('list_alt_outlined'), isFalse);
      expect(src.contains("tooltip: '模板'"), isFalse);
    });
  });

  group('bookkeeping panel structure (behavior)', () {
    Future<void> pumpPanel(WidgetTester tester) async {
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
    }

    testWidgets('type switcher has 3 segs above amount; switches category kind',
        (tester) async {
      await pumpPanel(tester);

      expect(find.byKey(const Key('bk_type_switcher')), findsOneWidget);
      expect(find.byKey(const Key('bk_type_seg_out')), findsOneWidget);
      expect(find.byKey(const Key('bk_type_seg_in')), findsOneWidget);
      expect(find.byKey(const Key('bk_type_seg_transfer')), findsOneWidget);
      expect(find.byKey(const Key('bk_type_seg_refund')), findsNothing);

      final switcherTop =
          tester.getTopLeft(find.byKey(const Key('bk_type_switcher'))).dy;
      final amountTop = tester.getTopLeft(find.textContaining('CNY')).dy;
      expect(switcherTop < amountTop, isTrue);

      expect(find.text('CNY'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bk_type_seg_in')));
      await tester.pumpAndSettle();
      expect(find.textContaining('收入'), findsWidgets);

      final chipsH =
          tester.getSize(find.byKey(const Key('bk_chips_row'))).height;
      expect(chipsH, lessThan(50));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('member chip not shown', (tester) async {
      await pumpPanel(tester);
      expect(find.text('成员'), findsNothing);
      expect(find.text('标签'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('transfer shows category and account chips', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.byKey(const Key('bk_type_seg_transfer')));
      await tester.pumpAndSettle();

      // 转账也有分类（默认「转账」），并显示转出 / 转入账户。
      expect(find.textContaining('转出'), findsWidgets);
      expect(find.textContaining('转入'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
