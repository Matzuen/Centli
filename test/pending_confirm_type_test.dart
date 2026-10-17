import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmPendingCapture with income category stores type in', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final inCats = await db.loadCategories(ledger.id, 'in');
    final outCats = await db.loadCategories(ledger.id, 'out');
    expect(inCats, isNotEmpty);
    expect(outCats, isNotEmpty);

    final incomeCat = inCats.first;
    final expenseCat = outCats.first;

    // Mirror pending_page.dart resolution against loaded lists (behavior).
    String resolveType(String? categoryId, {String direction = 'out'}) {
      if (direction == 'refund') return 'refund';
      final known = outCats.any((x) => x.id == categoryId) ||
          inCats.any((x) => x.id == categoryId);
      final txnType = !known
          ? 'out'
          : (inCats.any((x) => x.id == categoryId) ? 'in' : 'out');
      return txnType;
    }

    expect(resolveType(incomeCat.id), 'in');
    expect(resolveType(expenseCat.id), 'out');
    expect(resolveType('deleted-cat-id'), 'out');
    expect(resolveType(expenseCat.id, direction: 'refund'), 'refund');

    final pendingInId = await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'manual:test',
      rawText: 'salary 5000',
      dedupeKey: 'test-income-${DateTime.now().microsecondsSinceEpoch}',
      amountMinor: 500000,
      currency: 'CNY',
      merchant: 'corp',
      parseOk: true,
    );
    expect(pendingInId, isNotNull);

    await db.confirmPendingCapture(
      pendingId: pendingInId!,
      amountMinor: 500000,
      currency: 'CNY',
      accountId: account.id,
      categoryId: incomeCat.id,
      merchant: 'corp',
      type: resolveType(incomeCat.id),
    );

    final txns = await db.loadTransactionsForExport(ledger.id);
    final hit = txns.firstWhere((t) => t.amountMinor == 500000);
    expect(hit.type, 'in');
  });
}
