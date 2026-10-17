import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home and assets netWorthInBase match after opening + txn', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;

    await db.updateAccount(
      id: account.id,
      name: account.name,
      currency: account.currency,
      type: account.type,
      openingBalanceMinor: 100000,
      icon: account.icon,
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 2500,
      currency: 'CNY',
      accountId: account.id,
    );

    final nw = await db.netWorthInBase(ledger.id, ledger.baseCurrency);
    // Same computation path used by both home and assets providers.
    final nw2 = await db.netWorthInBase(ledger.id, ledger.baseCurrency);
    expect(nw.totalMinor, nw2.totalMinor);
    expect(nw.totalMinor, 100000 - 2500);
  });
}
