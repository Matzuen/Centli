import 'package:centli/core/utils/id_gen.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/txn_templates.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TxnTemplate json round-trip', () {
    final t = TxnTemplate(
      id: 'tpl1',
      name: 'lunch',
      type: 'out',
      amountMinor: 2500,
      currency: 'CNY',
      accountId: 'acc1',
      categoryId: 'cat1',
      merchant: 'canteen',
      note: 'weekday',
      tags: ['daily'],
    );
    final list = TxnTemplate.decodeList(TxnTemplate.encodeList([t]));
    expect(list, hasLength(1));
    expect(list.first.name, 'lunch');
    expect(list.first.amountMinor, 2500);
    expect(list.first.tags, ['daily']);
    expect(list.first.merchant, 'canteen');
  });

  test('save and load txn templates via settings', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    await db.saveTxnTemplate(
      ledger.id,
      TxnTemplate(
        id: newId(),
        name: 'metro',
        type: 'out',
        amountMinor: 500,
        currency: 'CNY',
        accountId: account.id,
        categoryId: cat.id,
        note: 'commute',
        tags: ['transit'],
      ),
    );

    final loaded = await db.loadTxnTemplates(ledger.id);
    expect(loaded, hasLength(1));
    expect(loaded.first.name, 'metro');
    expect(loaded.first.amountMinor, 500);
    expect(loaded.first.accountId, account.id);
    expect(loaded.first.categoryId, cat.id);
    expect(loaded.first.tags, ['transit']);

    await db.deleteTxnTemplate(ledger.id, loaded.first.id);
    expect(await db.loadTxnTemplates(ledger.id), isEmpty);
  });
}
