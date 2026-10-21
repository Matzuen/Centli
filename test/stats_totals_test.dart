import 'package:centli/core/utils/date_range.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/stats/stats_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统计页数据层：汇总（笔数 / 收入 / 支出 / 结余）、资产账户汇总（不含转账）、
/// 环形图分组（支出 / 收入 / 全部）与区间文案。
void main() {
  late CentliDatabase db;
  late String ledgerId;
  late List<Account> accounts;
  late List<Category> outCats;
  late List<Category> inCats;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    ledgerId = ledger.id;
    accounts = await db.loadActiveAccounts(ledgerId);
    outCats = await db.loadCategories(ledgerId, 'out');
    inCats = await db.loadCategories(ledgerId, 'in');
  });

  tearDown(() async => db.close());

  Future<void> add({
    required String type,
    required int amountMinor,
    required int happenAt,
    String? categoryId,
    String? accountId,
    String? toAccountId,
  }) => db.insertManualTransaction(
        ledgerId: ledgerId,
        type: type,
        amountMinor: amountMinor,
        currency: 'CNY',
        accountId: accountId ?? accounts.first.id,
        categoryId: categoryId,
        toAccountId: toAccountId,
        happenAt: DateTime.fromMillisecondsSinceEpoch(happenAt),
      );

  // October 2026 window.
  final oct = DateTimeRange2026.oct;
  int day(int d) => DateTime(2026, 10, d, 12).millisecondsSinceEpoch;

  group('statsRangeText', () {
    test('month range prints dotted start — end', () {
      expect(statsRangeText(statsMonthWindow(2026, 10)),
          '2026.10.01 — 2026.10.31');
    });

    test('year range covers Jan 1 – Dec 31', () {
      expect(statsRangeText(statsYearWindow(2026)),
          '2026.01.01 — 2026.12.31');
    });

    test('single-day custom range prints once', () {
      final r = DateRangeWindow.custom(
        startInclusive: DateTime(2026, 10, 8),
        endInclusive: DateTime(2026, 10, 8),
      );
      expect(statsRangeText(r), '2026.10.08');
    });
  });

  group('statsTotalsInBase', () {
    test('counts every bill, splits income/expense, nets them', () async {
      await add(
        type: 'out',
        amountMinor: 2500,
        happenAt: day(3),
        categoryId: outCats.first.id,
      );
      await add(
        type: 'in',
        amountMinor: 10000,
        happenAt: day(4),
        categoryId: inCats.first.id,
      );
      final t = await db.statsTotalsInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(t.count, 2);
      expect(t.incomeMinor, 10000);
      expect(t.expenseMinor, 2500);
      expect(t.netMinor, 7500);
    });

    test('transfers count as a bill but never as income/expense', () async {
      await add(
        type: 'transfer',
        amountMinor: 50000,
        happenAt: day(5),
        toAccountId: accounts[1].id,
      );
      final t = await db.statsTotalsInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(t.count, 1);
      expect(t.incomeMinor, 0);
      expect(t.expenseMinor, 0);
      expect(t.netMinor, 0);
    });

    test('legacy type=refund is ignored in totals', () async {
      await add(
        type: 'out',
        amountMinor: 5000,
        happenAt: day(6),
        categoryId: outCats.first.id,
      );
      await add(
        type: 'refund',
        amountMinor: 2000,
        happenAt: day(7),
        categoryId: outCats.first.id,
      );
      final t = await db.statsTotalsInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(t.expenseMinor, 5000);
      expect(t.netMinor, -5000);
    });

    test('bills outside the range are excluded', () async {
      await add(
        type: 'out',
        amountMinor: 9999,
        happenAt: DateTime(2026, 9, 30, 23).millisecondsSinceEpoch,
        categoryId: outCats.first.id,
      );
      final t = await db.statsTotalsInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(t.count, 0);
    });
  });

  group('statsByAccountInBase', () {
    test('splits by account and excludes transfers', () async {
      final a = accounts[0];
      final b = accounts[1];
      await add(
        type: 'out',
        amountMinor: 3000,
        happenAt: day(2),
        categoryId: outCats.first.id,
        accountId: a.id,
      );
      await add(
        type: 'in',
        amountMinor: 8000,
        happenAt: day(3),
        categoryId: inCats.first.id,
        accountId: b.id,
      );
      await add(
        type: 'transfer',
        amountMinor: 100000,
        happenAt: day(4),
        accountId: a.id,
        toAccountId: b.id,
      );
      final rows = await db.statsByAccountInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(rows, hasLength(2), reason: 'transfer must not add a row value');
      final rowA = rows.firstWhere((r) => r.accountId == a.id);
      final rowB = rows.firstWhere((r) => r.accountId == b.id);
      expect(rowA.expenseMinor, 3000);
      expect(rowA.incomeMinor, 0);
      expect(rowB.incomeMinor, 8000);
      expect(rowB.expenseMinor, 0);
      // No row carries the 1000.00 transfer.
      expect(rows.any((r) => r.incomeMinor == 100000 || r.expenseMinor == 100000),
          isFalse);
    });

    test('sorts the biggest account first', () async {
      await add(
        type: 'out',
        amountMinor: 100,
        happenAt: day(2),
        categoryId: outCats.first.id,
        accountId: accounts[0].id,
      );
      await add(
        type: 'out',
        amountMinor: 90000,
        happenAt: day(3),
        categoryId: outCats.first.id,
        accountId: accounts[1].id,
      );
      final rows = await db.statsByAccountInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(rows.first.accountId, accounts[1].id);
    });
  });

  group('statsAllCategoriesInBase', () {
    test('returns expenses and incomes separately', () async {
      await add(
        type: 'out',
        amountMinor: 1200,
        happenAt: day(2),
        categoryId: outCats.first.id,
      );
      await add(
        type: 'in',
        amountMinor: 5000,
        happenAt: day(3),
        categoryId: inCats.first.id,
      );
      final both = await db.statsAllCategoriesInBase(
        ledgerId,
        oct.startMs,
        oct.endMs,
        'CNY',
      );
      expect(both.expenses.single.totalMinor, 1200);
      expect(both.incomes.single.totalMinor, 5000);
    });
  });
}

/// October 2026 as a stats window.
class DateTimeRange2026 {
  static final oct = statsMonthWindow(2026, 10);
}
