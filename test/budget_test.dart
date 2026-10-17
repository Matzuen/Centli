import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('budgetYearMonth formats yyyy-MM', () {
    expect(budgetYearMonth(DateTime(2026, 10, 14)), '2026-10');
    expect(budgetYearMonth(DateTime(2026, 1, 1)), '2026-01');
  });

  test('CategoryBudgetProgress ratio and over', () {
    const ok = CategoryBudgetProgress(
      categoryId: 'c1',
      name: 'food',
      limitMinor: 10000,
      spentMinor: 2500,
    );
    expect(ok.ratio, 0.25);
    expect(ok.over, isFalse);

    const over = CategoryBudgetProgress(
      categoryId: 'c1',
      name: 'food',
      limitMinor: 1000,
      spentMinor: 1500,
    );
    expect(over.over, isTrue);
    expect(over.ratio, 1.5);
  });

  test('MonthBudgetProgress.hasAnyBudget', () {
    const empty = MonthBudgetProgress(
      yearMonth: '2026-10',
      baseCurrency: 'CNY',
      totalLimitMinor: null,
      spentTotalMinor: 0,
      categories: [],
    );
    expect(empty.hasAnyBudget, isFalse);
    expect(empty.hasUnconverted, isFalse);

    const withTotal = MonthBudgetProgress(
      yearMonth: '2026-10',
      baseCurrency: 'CNY',
      totalLimitMinor: 50000,
      spentTotalMinor: 100,
      categories: [],
    );
    expect(withTotal.hasAnyBudget, isTrue);
  });

  test('monthBudgetProgress surfaces unconverted FX without counting spent',
      () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final outCat = (await db.loadCategories(ledger.id, 'out')).first;

    await db.createAccount(
      ledgerId: ledger.id,
      name: 'usd-cash',
      currency: 'USD',
      type: 'cash',
    );
    final usd = (await db.loadActiveAccounts(ledger.id))
        .firstWhere((a) => a.currency == 'USD');
    final cny = (await db.loadActiveAccounts(ledger.id))
        .firstWhere((a) => a.currency == 'CNY');

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 1000,
      currency: 'CNY',
      accountId: cny.id,
      categoryId: outCat.id,
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 500,
      currency: 'USD',
      accountId: usd.id,
      categoryId: outCat.id,
    );

    final ym = budgetYearMonth();
    final p = await db.monthBudgetProgress(ledger.id, ym, 'CNY');
    expect(p.spentTotalMinor, 1000);
    expect(p.hasUnconverted, isTrue);
    expect(p.unconvertedByCcy['USD'], 500);
  });
}
