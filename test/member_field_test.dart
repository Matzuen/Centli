import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction member field round-trip', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 1200,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      member: 'Alice',
    );

    final recent = await db.loadTransactionsForExport(ledger.id);
    final hit = recent.firstWhere((t) => t.amountMinor == 1200);
    expect(hit.member, 'Alice');

    await db.updateManualTransaction(
      id: hit.id,
      type: 'out',
      amountMinor: 1200,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      member: 'Bob',
    );
    final updated = await db.getTransaction(hit.id);
    expect(updated!.member, 'Bob');
  });

  test('schema v5 has member column', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();
    final info = await db.customSelect('PRAGMA table_info(transactions)').get();
    final cols = {for (final r in info) r.read<String>('name')};
    expect(cols.contains('member'), isTrue);
  });
}
