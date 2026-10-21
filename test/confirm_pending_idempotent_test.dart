import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmPendingCapture twice does not insert two transactions', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final outCats = await db.loadCategories(ledger.id, 'out');
    expect(outCats, isNotEmpty);
    final cat = outCats.first;

    final pendingId = await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'com.tencent.mm',
      rawText: '支付成功 ¥12.00',
      dedupeKey: 'idempotent-${DateTime.now().microsecondsSinceEpoch}',
      amountMinor: 1200,
      currency: 'CNY',
      merchant: 'cafe',
      parseOk: true,
    );
    expect(pendingId, isNotNull);

    Future<void> confirmOnce() => db.confirmPendingCapture(
          pendingId: pendingId!,
          amountMinor: 1200,
          currency: 'CNY',
          accountId: account.id,
          categoryId: cat.id,
          note: 'cafe',
          type: 'out',
        );

    await confirmOnce();
    await confirmOnce(); // idempotent — must not throw / not double-insert

    final txns = await (db.select(db.transactions)
          ..where((t) => t.pendingId.equals(pendingId!)))
        .get();
    expect(txns, hasLength(1));

    final pending = await (db.select(db.pendingCaptures)
          ..where((t) => t.id.equals(pendingId!)))
        .getSingle();
    expect(pending.status, 'confirmed');
  });
}
