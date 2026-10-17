import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listMerchantSuggestions returns distinct recent merchants', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 100,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      merchant: 'Starbucks',
      happenAt: DateTime(2026, 1, 1),
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 200,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      merchant: 'starbucks', // same key, newer
      happenAt: DateTime(2026, 2, 1),
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 300,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      merchant: '地铁',
      happenAt: DateTime(2026, 3, 1),
    );

    final all = await db.listMerchantSuggestions(ledger.id);
    expect(all.length, 2);
    expect(all.first, '地铁'); // newest first
    expect(all.map((e) => e.toLowerCase()), contains('starbucks'));

    final filtered = await db.listMerchantSuggestions(ledger.id, query: 'star');
    expect(filtered, hasLength(1));
    expect(filtered.first.toLowerCase(), 'starbucks');
  });

  test('listMerchantSuggestions includes merchant_rules keys', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();

    await db.upsertMerchantRule(
      ledgerId: ledger.id,
      merchantKey: 'only-in-rules',
      categoryId: null,
      accountId: null,
    );

    final list = await db.listMerchantSuggestions(ledger.id, query: 'only');
    expect(list, contains('only-in-rules'));
  });
}
