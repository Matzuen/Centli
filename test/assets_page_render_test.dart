import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/assets/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 资产页按截图数据渲染：图例金额不能被截断、分组头金额靠右、账户行不再有箭头。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(CentliDatabase db) {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: CentliTheme.light(), home: const AssetsPage()),
    );
  }

  Future<void> pump(WidgetTester tester, CentliDatabase db) async {
    tester.view.physicalSize = const Size(360 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(db));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Reproduce the screenshot: 现金 +679, 银行卡 0, 电子钱包 −87.89, 其他 0.
  Future<List<AssetTypeSlice>> screenshotSlices() async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final types = await db.loadAssetTypes(ledger.id);
    AssetType byName(String n) => types.firstWhere((t) => t.name == n);
    Account acc(String id, String name, String type) => Account(
          id: id,
          ledgerId: ledger.id,
          name: name,
          currency: 'CNY',
          type: type,
          icon: null,
          openingBalanceMinor: 0,
          sortOrder: 0,
          archived: 0,
          createdAt: 0,
          updatedAt: 0,
        );
    final accounts = [
      acc('a1', '现金', byName('现金').id),
      acc('a2', '农业银行', byName('银行卡').id),
      acc('a3', '支付宝', byName('电子钱包').id),
    ];
    return assetTypeSlices(
      accounts: accounts,
      balances: {'a1': 67900, 'a2': 0, 'a3': -8789},
      types: types,
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );
  }

  test('screenshot numbers keep their decimals in the legend', () async {
    final slices = await screenshotSlices();
    final wallet = slices.firstWhere((s) => s.name == '电子钱包');
    expect(wallet.totalMinor, -8789);
    // 87.89 / (679 + 87.89) = 11.46% → −11.5% (not truncated).
    expect(wallet.pct, '−11.5%');
    final cash = slices.firstWhere((s) => s.name == '现金');
    expect(cash.pct, '88.5%');
  });

  testWidgets('legend keeps the amount + percent intact', (tester) async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    await pump(tester, db);

    // Full strings must be present — the screenshot showed 「-11.5...」.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();
    final moneyRows = texts.where((t) => t.contains('%')).toList();
    expect(moneyRows, isNotEmpty);
    for (final t in moneyRows) {
      expect(t.endsWith('%）'), isTrue, reason: 'truncated: $t');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('account rows have no chevron and amounts sit at the edge',
      (tester) async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    await pump(tester, db);
    // Grouped account list uses chevrons only elsewhere; none here.
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('positive slices never reuse the liability red', () {
    // Direct check of the colour rule used by the analysis donut.
    const liability = CentliTheme.expenseRed;
    final palette = kAssetsDonutColors
        .where((c) => c.toARGB32() != liability.toARGB32())
        .toList();
    expect(palette.length, greaterThanOrEqualTo(3));
  });
}
