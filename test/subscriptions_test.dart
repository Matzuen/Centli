import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/subscriptions/subscription_pages.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v7 onCreate has subscriptions; nextDueAt nullable', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 8);
    final tables = {
      for (final r in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get())
        r.read<String>('name')
    };
    expect(tables.contains('subscriptions'), isTrue);

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final ts = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.subscriptions).insert(
          SubscriptionsCompanion.insert(
            id: 'sub-life',
            ledgerId: ledger.id,
            name: '买断软件',
            priceMinor: 9900,
            currency: 'CNY',
            periodKind: 'lifetime',
            status: 'owned',
            startedAt: ts,
            nextDueAt: const Value(null),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    final row = await (db.select(db.subscriptions)
          ..where((t) => t.id.equals('sub-life')))
        .getSingle();
    expect(row.nextDueAt, isNull);
  });

  test('subscriptionsDueSoon does not write transactions', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final ts = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.subscriptions).insert(
          SubscriptionsCompanion.insert(
            id: 'sub-due',
            ledgerId: ledger.id,
            name: '流媒体',
            priceMinor: 1500,
            currency: 'CNY',
            periodKind: 'month',
            status: 'active',
            startedAt: ts,
            nextDueAt: Value(tomorrow.millisecondsSinceEpoch),
            remindDaysBefore: const Value(3),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    final before = await db.select(db.transactions).get();
    final due = subscriptionsDueSoon(await db.select(db.subscriptions).get());
    expect(due.length, 1);
    final after = await db.select(db.transactions).get();
    expect(after.length, before.length);
  });
}
