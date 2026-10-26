import 'package:centli/core/constants/pref_keys.dart';
import 'package:centli/core/utils/budget_progress_style.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/settings/budget_warn_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CentliDatabase db;
  late List<({int notifId, String title, String body})> sent;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    sent = [];
  });

  tearDown(() async {
    await db.close();
  });

  BudgetWarnService service() => BudgetWarnService(
        db: db,
        showNotify: ({
          required int notifId,
          required String title,
          required String body,
        }) async {
          sent.add((notifId: notifId, title: title, body: body));
        },
      );

  MonthBudgetProgress progress({
    int? totalLimit,
    int spentTotal = 0,
    List<CategoryBudgetProgress> categories = const [],
    String? yearMonth,
  }) {
    return MonthBudgetProgress(
      yearMonth: yearMonth ?? budgetYearMonth(),
      baseCurrency: 'CNY',
      totalLimitMinor: totalLimit,
      spentTotalMinor: spentTotal,
      categories: categories,
    );
  }

  test('below notifyAt does not notify', () async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await service().evaluate(
      ledgerId: ledger.id,
      progress: progress(
        totalLimit: 10000,
        spentTotal: (BudgetProgressStyle.notifyAt * 10000).toInt() - 1,
      ),
    );
    expect(sent, isEmpty);
  });

  test('at notifyAt sends once and Chinese copy', () async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final svc = service();
    final p = progress(totalLimit: 10000, spentTotal: 8000);
    await svc.evaluate(ledgerId: ledger.id, progress: p);
    await svc.evaluate(ledgerId: ledger.id, progress: p);
    expect(sent, hasLength(1));
    expect(sent.single.title, '预算预警');
    expect(sent.single.body, contains('本月总预算已用约'));
    expect(sent.single.body, contains('80%'));
    final key = PrefKeys.budgetWarnSentKey(
      ledgerId: ledger.id,
      yearMonth: p.yearMonth,
      categoryId: '',
    );
    expect(await db.getSetting(key), isNotNull);
  });

  test('pref off skips notify', () async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await db.setSetting(PrefKeys.budgetWarnNotify, 'false');
    await service().evaluate(
      ledgerId: ledger.id,
      progress: progress(totalLimit: 10000, spentTotal: 9000),
    );
    expect(sent, isEmpty);
  });

  test('category budget notifies separately with label', () async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final p = progress(
      totalLimit: null,
      categories: [
        const CategoryBudgetProgress(
          categoryId: 'c-food',
          name: '餐饮',
          limitMinor: 1000,
          spentMinor: 850,
        ),
      ],
    );
    await service().evaluate(ledgerId: ledger.id, progress: p);
    expect(sent, hasLength(1));
    expect(sent.single.body, contains('餐饮'));
    expect(sent.single.body, contains('85%'));
  });

  test('past yearMonth is ignored', () async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await service().evaluate(
      ledgerId: ledger.id,
      progress: progress(
        totalLimit: 10000,
        spentTotal: 9000,
        yearMonth: '2020-01',
      ),
    );
    expect(sent, isEmpty);
  });

  test('budgetWarnSentKey shape', () {
    expect(
      PrefKeys.budgetWarnSentKey(
        ledgerId: 'L1',
        yearMonth: '2026-10',
        categoryId: '',
      ),
      'budget_warn_sent:L1:2026-10:',
    );
  });
}
