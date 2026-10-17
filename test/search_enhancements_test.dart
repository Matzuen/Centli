import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search by category name and account name', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 888,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      note: 'zzz-unique-note',
    );

    final byCat = await db.searchTransactions(ledger.id, cat.name);
    expect(byCat.any((t) => t.amountMinor == 888), isTrue);

    final byAcc = await db.searchTransactions(ledger.id, account.name);
    expect(byAcc.any((t) => t.amountMinor == 888), isTrue);
  });

  test('search returns limit+1 rows when truncated', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    for (var i = 0; i < 5; i++) {
      await db.insertManualTransaction(
        ledgerId: ledger.id,
        type: 'out',
        amountMinor: 100 + i,
        currency: 'CNY',
        accountId: account.id,
        categoryId: cat.id,
        note: 'bulk-search',
      );
    }
    final rows = await db.searchTransactions(
      ledger.id,
      'bulk-search',
      limit: 3,
    );
    expect(rows.length, 4);
  });

  test('loadAccountsIncludingArchived includes archived', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await db.createAccount(
      ledgerId: ledger.id,
      name: 'old-bank',
      currency: 'CNY',
      type: 'bank',
    );
    final created = (await db.loadActiveAccounts(ledger.id))
        .firstWhere((a) => a.name == 'old-bank');
    await db.archiveAccount(created.id);
    final active = await db.loadActiveAccounts(ledger.id);
    expect(active.any((a) => a.id == created.id), isFalse);
    final all = await db.loadAccountsIncludingArchived(ledger.id);
    expect(all.any((a) => a.id == created.id), isTrue);
  });
}
