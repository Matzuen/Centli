import 'package:centli/data/db/centli_database.dart';
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

    const withTotal = MonthBudgetProgress(
      yearMonth: '2026-10',
      baseCurrency: 'CNY',
      totalLimitMinor: 50000,
      spentTotalMinor: 100,
      categories: [],
    );
    expect(withTotal.hasAnyBudget, isTrue);
  });
}
