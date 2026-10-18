import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/ledger/bookkeeping_sheet.dart';
import 'package:centli/features/ledger/ledger_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bill detail: 保存 replaces 编辑 in the app bar, every row is tappable, and a
/// staged amount is bridged to the full sheet. Field-level persistence is
/// covered by ledger_detail_edit_test.dart against a real in-memory DB.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDb db;
  late Transaction txn;

  setUp(() {
    final now = DateTime(2026, 10, 17, 16, 23).millisecondsSinceEpoch;
    db = _FakeDb(
      Transaction(
        id: 't1',
        ledgerId: 'L',
        type: 'out',
        amountMinor: 2000,
        currency: 'CNY',
        accountId: 'a1',
        toAccountId: null,
        categoryId: 'c-food',
        note: '午餐',
        tags: null,
        happenAt: now,
        includeInStat: 1,
        includeInBudget: 1,
        transferGroupId: null,
        fxRate: null,
        toAmountMinor: null,
        source: 'manual',
        pendingId: null,
        occurrenceKey: null,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      ),
    );
    txn = db.row!;
    pendingDetailAmountMinor = null;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: CentliTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          home: LedgerDetailPage(transactionId: txn.id),
        ),
      ),
    );
    await tester.pump();
  }

  TextButton saveButton(WidgetTester tester) => tester.widget<TextButton>(
        find.byKey(const Key('ledger_detail_save')),
      );

  testWidgets('app bar shows 保存 (not 编辑); disabled until an edit',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('账单'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.byTooltip('编辑'), findsNothing);
    expect(saveButton(tester).onPressed, isNull);
    expect(find.byTooltip('删除'), findsOneWidget);
  });

  testWidgets('every bill field row is tappable', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('ledger_detail_amount')), findsOneWidget);
    for (final k in const [
      'ledger_detail_account',
      'ledger_detail_time',
      'ledger_detail_tags',
      'ledger_detail_note',
    ]) {
      final tile = find.byKey(Key(k));
      expect(tile, findsOneWidget, reason: k);
      expect(
        find.descendant(of: tile, matching: find.byType(ListTile)),
        findsWidgets,
        reason: k,
      );
    }
    for (final k in const [
      'ledger_detail_include_stat',
      'ledger_detail_include_budget',
    ]) {
      expect(
        tester.widget<SwitchListTile>(find.byKey(Key(k))).onChanged,
        isNotNull,
        reason: k,
      );
    }
  });

  testWidgets('toggle writes nothing until 保存 is tapped', (tester) async {
    await pumpPage(tester);

    final sw = find.byKey(const Key('ledger_detail_include_stat'));
    await tester.tap(sw);
    await tester.pump();
    // Staged only — no DB write, and 保存 becomes enabled.
    expect(db.updates, isEmpty, reason: 'no auto-save on toggle');
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('ledger_detail_save')));
    await tester.pump();
    expect(db.updates, hasLength(1));
    expect(db.updates.single['includeInStat'], 0);
    expect(saveButton(tester).onPressed, isNull,
        reason: 'clean again after saving');
  });

  testWidgets('再记一笔 button is offered next to 删除', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const Key('ledger_detail_again')), findsOneWidget);
    expect(find.byTooltip('再记一笔'), findsOneWidget);
  });

  testWidgets('unsaved edits show a discard guard on back', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('ledger_detail_include_stat')));
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    // PopScope is generic (PopScope<Object>), so find it by its position in
    // the body subtree rather than by type.
    final guard = find
        .ancestor(
          of: find.byType(ListView).first,
          matching: find.byWidgetPredicate((w) => w is PopScope),
        )
        .evaluate()
        .first
        .widget as PopScope;
    expect(guard.canPop, isFalse, reason: 'guard engages while dirty');
  });

  testWidgets('stored note renders in its row; empty rows show a dash',
      (tester) async {
    await pumpPage(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('ledger_detail_note')),
        matching: find.text('午餐'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('ledger_detail_tags')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('支出'), findsWidgets);
  });
}

/// Read-only fake: the detail page reads the transaction plus picker sources,
/// and writes only through updateTransactionFields (recorded, not executed).
class _FakeDb implements CentliDatabase {
  _FakeDb(this.row);

  Transaction? row;
  final List<Map<String, Object?>> updates = [];

  @override
  Stream<Transaction?> watchTransaction(String id) => Stream.value(row);

  @override
  Stream<bool> watchHideAmount() => Stream.value(false);

  @override
  Future<List<Account>> loadAccountsIncludingArchived(String ledgerId) async =>
      const [
        Account(
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
        Account(
          id: 'a2',
          ledgerId: 'L',
          name: '招商银行',
          currency: 'CNY',
          type: 'bank',
          icon: null,
          openingBalanceMinor: 0,
          sortOrder: 1,
          archived: 1,
          createdAt: 0,
          updatedAt: 0,
        ),
      ];

  @override
  Future<List<Category>> loadCategories(String ledgerId, String kind) async =>
      [
        Category(
          id: kind == 'in' ? 'c-salary' : 'c-food',
          ledgerId: 'L',
          name: kind == 'in' ? '工资' : '餐饮',
          kind: kind,
          icon: null,
          sortOrder: 0,
          archived: 0,
          parentId: null,
          createdAt: 0,
        ),
      ];

  @override
  Future<Category?> getCategory(String id) async {
    final cats = [
      ...await loadCategories('L', 'out'),
      ...await loadCategories('L', 'in'),
    ];
    return cats.where((c) => c.id == id).firstOrNull;
  }

  @override
  Future<Account?> getAccount(String id) async =>
      (await loadAccountsIncludingArchived('L'))
          .where((a) => a.id == id)
          .firstOrNull;

  @override
  Future<List<String>> listDistinctTags(String ledgerId) async => const ['工作'];

  @override
  Future<void> updateTransactionFields({
    required String id,
    String? type,
    int? amountMinor,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    DateTime? happenAt,
    List<String>? tags,
    String? note,
    int? includeInStat,
    int? includeInBudget,
  }) async {
    updates.add(<String, Object?>{
      'id': id,
    }..addAll(<String, Object?>{
        'amountMinor': ?amountMinor,
        'note': ?note,
        'accountId': ?accountId,
        'includeInStat': ?includeInStat,
      }));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}
