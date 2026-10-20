import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/stats/stats_page.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页四张卡片：时间范围 / 分类环形图 + 图例 / 汇总 / 资产账户。
///
/// 只做渲染与结构校验（不 pumpAndSettle：页面挂的是 Drift 流）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final outCats = await db.loadCategories(ledger.id, 'out');
    final inCats = await db.loadCategories(ledger.id, 'in');
    final now = DateTime.now();
    Future<void> add(String type, int minor, String catId, int daysAgo) =>
        db.insertManualTransaction(
          ledgerId: ledger.id,
          type: type,
          amountMinor: minor,
          currency: 'CNY',
          accountId: accounts.first.id,
          categoryId: catId,
          happenAt: now.subtract(Duration(days: daysAgo)),
        );
    await add('out', 2500, outCats.first.id, 1);
    await add('in', 10000, inCats.first.id, 2);
    await add('transfer', 3000, outCats.first.id, 3);

    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    // The page defaults to "last 30 days"; the header expects dotted dates,
    // so start from the current month for a stable label.
    final m = statsMonthWindow(now.year, now.month);
    container.read(statsRangeProvider.notifier).state = m;
    container.read(statsRangeModeProvider.notifier).state = StatsRangeMode.month;
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Widget app() => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: CentliTheme.light(), home: const StatsPage()),
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    // Let the FutureProviders resolve without pumpAndSettle (Drift streams).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('renders the four cards', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('stats_range_card')), findsOneWidget);
    expect(find.byKey(const Key('stats_breakdown_card')), findsOneWidget);
    expect(find.byKey(const Key('stats_summary_card')), findsOneWidget);
    expect(find.byKey(const Key('stats_accounts_card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('range card shows 月份/年份/自定义 and dotted range', (tester) async {
    await pump(tester);
    expect(find.text('月份'), findsOneWidget);
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    final text = tester
        .widget<Text>(find.byKey(const Key('stats_range_text')))
        .data!;
    expect(text, matches(RegExp(r'^\d{4}\.\d{2}\.\d{2} — \d{4}\.\d{2}\.\d{2}$')));
    expect(text.contains('—'), isTrue);
  });

  testWidgets('breakdown card has 支出/收入/全部 and a legend', (tester) async {
    await pump(tester);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('收入'), findsWidgets);
    expect(find.text('全部'), findsOneWidget);
    expect(find.byKey(const Key('stats_legend')), findsOneWidget);
  });

  testWidgets('legend puts name and amount on one line', (tester) async {
    await pump(tester);
    final legend = find.byKey(const Key('stats_legend'));
    expect(legend, findsOneWidget);
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: legend, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .where((t) => t.contains('¥') || t.contains('￥'))
        .toList();
    expect(texts, isNotEmpty, reason: 'legend should show an amount');
    final box = tester.getRect(legend);
    final textFinder = find.descendant(of: legend, matching: find.byType(Text));
    final contentMid = (tester.getTopLeft(textFinder.first).dy +
            tester.getBottomLeft(textFinder.last).dy) /
        2;
    expect((contentMid - box.center.dy).abs(), lessThan(24));
    for (final t in texts) {
      expect(t.contains('%'), isFalse, reason: t);
      final w = tester.widget<Text>(find.text(t).first);
      expect(w.maxLines, 1, reason: t);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('legend amount survives a narrow phone width', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.takeException(), isNull, reason: 'no overflow at 320dp');
    final legend = find.byKey(const Key('stats_legend'));
    expect(legend, findsOneWidget);
  });

  testWidgets('pie slice tooltip shows while pressed and hides on release',
      (tester) async {
    await pump(tester);
    final pie = find.byType(PieChart);
    expect(pie, findsWidgets);
    final center = tester.getCenter(pie.first);
    // 0° is the right edge of the ring; nudge clockwise into the first slice.
    final gesture = await tester.startGesture(center + const Offset(46, 14));
    await tester.pump();
    final tip = find.byKey(const Key('stats_pie_tooltip'));
    expect(tip, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: tip, matching: find.byType(Text)),
    );
    expect(text.data, matches(RegExp(r'^.+（\d+%）$')));
    expect(text.style?.fontSize, 12);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const Key('stats_pie_tooltip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ring and legend are separated by a real gap', (tester) async {
    await pump(tester);
    final legend = find.byKey(const Key('stats_legend'));
    expect(legend, findsOneWidget);
    final legendLeft = tester.getTopLeft(legend).dx;
    // The donut sits to the left; find its bounds via the pie chart.
    final pie = find.byType(PieChart);
    expect(pie, findsWidgets);
    final pieRight = tester.getTopRight(pie.first).dx;
    expect(legendLeft - pieRight, greaterThanOrEqualTo(16),
        reason: 'ring and legend must not touch');
  });

  testWidgets('summary card headers are 笔数/收入/支出/结余', (tester) async {
    await pump(tester);
    final card = find.byKey(const Key('stats_summary_card'));
    for (final h in const ['笔数', '收入', '支出', '结余']) {
      expect(
        find.descendant(of: card, matching: find.text(h)),
        findsOneWidget,
        reason: h,
      );
    }
    // 3 bills including the transfer.
    expect(
      find.descendant(of: card, matching: find.text('3')),
      findsWidgets,
    );
    // 笔数贴左：标签应靠近卡片左内边，不能悬在第一列正中。
    final countLabel = find.descendant(of: card, matching: find.text('笔数'));
    final cardLeft = tester.getTopLeft(card).dx;
    final labelLeft = tester.getTopLeft(countLabel).dx;
    expect(labelLeft - cardLeft, lessThan(28));
  });

  testWidgets('accounts card says transfers are excluded', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('stats_accounts_note')), findsOneWidget);
    expect(find.text('不包含转账数据'), findsOneWidget);
    expect(find.text('资产账户'), findsOneWidget);
    expect(find.text('名称'), findsOneWidget);
  });
}
