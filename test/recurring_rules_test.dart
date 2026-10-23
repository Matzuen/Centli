import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/recurring/recurring_runner.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v6 onCreate has recurring_rules + direction + occurrence_key', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 13);

    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table'",
    ).get();
    final names = {for (final r in tables) r.read<String>('name')};
    expect(names.contains('recurring_rules'), isTrue);

    final pendingCols = {
      for (final r in await db.customSelect('PRAGMA table_info(pending_captures)').get())
        r.read<String>('name'),
    };
    expect(pendingCols.contains('direction'), isTrue);

    final txnCols = {
      for (final r in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name'),
    };
    expect(txnCols.contains('occurrence_key'), isTrue);
  });

  test('runDueRecurring generates once and is idempotent', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    final lastMonth = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = 'rule-rent-1';
    await db.into(db.recurringRules).insert(
          RecurringRulesCompanion.insert(
            id: id,
            ledgerId: ledger.id,
            type: 'out',
            amountMinor: 300000,
            currency: 'CNY',
            accountId: account.id,
            categoryId: Value(cat.id),
            note: const Value('房租'),
            periodKind: 'month',
            startAt: lastMonth.millisecondsSinceEpoch,
            nextRunAt: lastMonth.millisecondsSinceEpoch,
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
        );

    final r1 = await runDueRecurring(db);
    expect(r1.generated, greaterThanOrEqualTo(1));

    final txns = await (db.select(db.transactions)
          ..where((t) => t.occurrenceKey.isNotNull()))
        .get();
    expect(txns, isNotEmpty);
    expect(txns.first.note, contains('[周期]'));
    expect(txns.first.happenAt, lastMonth.millisecondsSinceEpoch);

    final count1 = txns.length;
    final r2 = await runDueRecurring(db);
    expect(r2.generated, 0);
    final txns2 = await (db.select(db.transactions)
          ..where((t) => t.occurrenceKey.isNotNull()))
        .get();
    expect(txns2.length, count1);
  });

  test('disabled rule does not generate', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final past = DateTime.now().subtract(const Duration(days: 3));
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.recurringRules).insert(
          RecurringRulesCompanion.insert(
            id: 'disabled-1',
            ledgerId: ledger.id,
            type: 'out',
            amountMinor: 100,
            currency: 'CNY',
            accountId: account.id,
            periodKind: 'day',
            enabled: const Value(0),
            startAt: past.millisecondsSinceEpoch,
            nextRunAt: past.millisecondsSinceEpoch,
            createdAt: nowMs,
            updatedAt: nowMs,
          ),
        );
    final r = await runDueRecurring(db);
    expect(r.generated, 0);
  });
}
