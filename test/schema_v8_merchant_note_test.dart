import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  test('confirm with merchantForRule still learns auto-categorize', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final cat = (await db.loadCategories(ledger.id, 'out')).first;

    final id1 = await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'manual:test',
      rawText: '星巴克 支付成功',
      dedupeKey: 'rule-1',
      amountMinor: 2500,
      currency: 'CNY',
      merchant: '星巴克',
      parseOk: true,
    );
    await db.confirmPendingCapture(
      pendingId: id1!,
      amountMinor: 2500,
      currency: 'CNY',
      accountId: account.id,
      categoryId: cat.id,
      note: '星巴克',
      merchantForRule: '星巴克',
      type: 'out',
    );

    final id2 = await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'manual:test',
      rawText: '星巴克 支付成功 2',
      dedupeKey: 'rule-2',
      amountMinor: 3000,
      currency: 'CNY',
      merchant: '星巴克',
      parseOk: true,
    );
    final pending2 = await (db.select(db.pendingCaptures)
          ..where((t) => t.id.equals(id2!)))
        .getSingle();
    expect(pending2.suggestedCategoryId, cat.id);
  });

  test('v8 onCreate has no merchant columns; merchant_rules kept', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 8);

    final txnCols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(txnCols.contains('merchant'), isFalse);
    expect(txnCols.contains('note'), isTrue);

    final pendCols = {
      for (final r in await db
          .customSelect('PRAGMA table_info(pending_captures)')
          .get())
        r.read<String>('name')
    };
    expect(pendCols.contains('merchant'), isFalse);
    expect(pendCols.contains('note'), isTrue);

    final tables = {
      for (final r in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get())
        r.read<String>('name')
    };
    expect(tables.contains('merchant_rules'), isTrue);
  });
}
