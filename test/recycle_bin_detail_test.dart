import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/settings/recycle_bin_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回收站要能看到被删账单的详细信息，而不是只有金额。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final deletedAt = DateTime(2026, 10, 18, 9, 30).millisecondsSinceEpoch;
  final happenAt = DateTime(2026, 10, 17, 12, 5).millisecondsSinceEpoch;

  final txn = Transaction(
    id: 't-del',
    ledgerId: 'L',
    type: 'out',
    amountMinor: 4350,
    currency: 'CNY',
    accountId: 'a1',
    toAccountId: null,
    categoryId: 'c-food',
    note: '午餐 公司楼下',
    tags: '["工作","报销"]',
    happenAt: happenAt,
    includeInStat: 1,
    includeInBudget: 0,
    transferGroupId: null,
    fxRate: null,
    toAmountMinor: null,
    source: 'notification',
    pendingId: null,
    occurrenceKey: null,
    createdAt: happenAt,
    updatedAt: happenAt,
    deletedAt: deletedAt,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(_FakeRecycleDb(txn)),
        ],
        child: MaterialApp(
          theme: CentliTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          home: const RecycleBinPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('list row shows category, account, note and amount',
      (tester) async {
    await pump(tester);
    expect(find.text('餐饮'), findsOneWidget); // category, not raw type
    expect(find.textContaining('支付宝'), findsOneWidget);
    expect(find.textContaining('午餐 公司楼下'), findsOneWidget);
    expect(find.textContaining('删除于'), findsOneWidget);
    expect(find.textContaining('43.5'), findsOneWidget);
  });

  testWidgets('tapping opens the detail sheet with every field',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    for (final label in const [
      '时间',
      '账户',
      '分类',
      '备注',
      '标签',
      '计入统计',
      '计入预算',
      '来源',
      '删除于',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Values the old list never showed.
    // Tags decode into a joined string; assert on content not separator.
    expect(find.textContaining('工作'), findsWidgets);
    expect(find.textContaining('报销'), findsWidgets);
    expect(find.text('notification'), findsOneWidget);
    expect(find.text('否'), findsOneWidget, reason: '计入预算=0');
    expect(find.byKey(const Key('recycle_restore')), findsOneWidget);
    expect(find.byKey(const Key('recycle_purge')), findsOneWidget);
  });

  testWidgets('empty bin keeps its empty state', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(_FakeRecycleDb(null)),
        ],
        child: const MaterialApp(home: RecycleBinPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('回收站为空'), findsOneWidget);
  });
}

class _FakeRecycleDb implements CentliDatabase {
  _FakeRecycleDb(this.row);
  final Transaction? row;

  @override
  Stream<Ledger?> watchCurrentLedger() => Stream.value(
        const Ledger(
          id: 'L',
          name: '我的账本',
          baseCurrency: 'CNY',
          archived: 0,
          createdAt: 0,
        ),
      );

  @override
  Stream<List<Transaction>> watchDeletedTransactions(String ledgerId) =>
      Stream.value([?row]);

  @override
  Future<TxnListLookups> loadTxnListLookups(String ledgerId) async =>
      TxnListLookups(
        categoriesById: {
          'c-food': Category(
            id: 'c-food',
            ledgerId: 'L',
            name: '餐饮',
            kind: 'out',
            icon: null,
            sortOrder: 0,
            archived: 0,
            parentId: null,
            createdAt: 0,
          ),
        },
        accountsById: {
          'a1': Account(
            id: 'a1',
            ledgerId: 'L',
            name: '支付宝',
            currency: 'CNY',
            type: 'wallet',
            icon: null,
            openingBalanceMinor: 0,
            sortOrder: 0,
            archived: 0,
            createdAt: 0,
            updatedAt: 0,
          ),
        },
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}
