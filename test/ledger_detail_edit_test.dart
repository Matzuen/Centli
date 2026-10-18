import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Row edits on the bill detail page go through
/// [CentliDatabase.updateTransactionFields]: only supplied fields change, and
/// provenance (source / occurrence key) is never reset by a row edit.
void main() {
  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async {
    await db.close();
  });

  Future<(int, String)> seedOutTxn({String source = 'notification'}) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final outCats = await db.loadCategories(ledger.id, 'out');
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 2000,
      currency: 'CNY',
      accountId: accounts.first.id,
      categoryId: outCats.first.id,
      note: '午餐',
      tags: const ['工作'],
      includeInStat: 1,
      includeInBudget: 1,
    );
    final txn = (await db.watchRecentTransactions(ledger.id, limit: 1).first)
        .single;
    // Simulate a notification-imported bill's provenance.
    await db.customStatement(
      "UPDATE transactions SET source = ?, occurrence_key = ? WHERE id = ?",
      [source, 'noti:abc', txn.id],
    );
    return (accounts.length, outCats.first.id);
  }

  test('amount-only edit keeps note, tags, source and flags', () async {
    final (_, firstCatId) = await seedOutTxn();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final before =
        (await db.watchRecentTransactions(ledger.id, limit: 1).first).single;

    await db.updateTransactionFields(id: before.id, amountMinor: 2550);
    final after = (await db.getTransaction(before.id))!;

    expect(after.amountMinor, 2550);
    expect(after.note, '午餐');
    expect(after.tags, before.tags);
    expect(after.source, 'notification');
    expect(after.occurrenceKey, 'noti:abc');
    expect(after.categoryId, firstCatId);
    expect(after.includeInStat, 1);
    expect(after.includeInBudget, 1);
    expect(after.happenAt, before.happenAt);
    expect(after.updatedAt, greaterThanOrEqualTo(before.updatedAt));
  });

  test('row picks update only themselves (account / time / tags / note)',
      () async {
    await seedOutTxn();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    expect(accounts.length, greaterThan(1));
    final before =
        (await db.watchRecentTransactions(ledger.id, limit: 1).first).single;
    final time = DateTime(2026, 10, 17, 16, 23);

    await db.updateTransactionFields(
      id: before.id,
      accountId: accounts[1].id,
      happenAt: time,
      tags: const ['报销', '旅行'],
      note: '和同事午餐',
      includeInStat: 0,
    );
    final after = (await db.getTransaction(before.id))!;

    expect(after.accountId, accounts[1].id);
    expect(
      after.happenAt,
      time.toUtc().millisecondsSinceEpoch,
    );
    expect(after.tags, contains('报销'));
    expect(after.note, '和同事午餐');
    expect(after.includeInStat, 0);
    expect(after.includeInBudget, 1, reason: 'unrelated flag untouched');
    expect(after.amountMinor, before.amountMinor);
    expect(after.categoryId, before.categoryId);
    expect(after.source, 'notification');
  });

  test('type + category edit re-derives direction', () async {
    await seedOutTxn();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final inCat = (await db.loadCategories(ledger.id, 'in')).first;
    final before =
        (await db.watchRecentTransactions(ledger.id, limit: 1).first).single;

    await db.updateTransactionFields(
      id: before.id,
      type: 'in',
      categoryId: inCat.id,
    );
    final after = (await db.getTransaction(before.id))!;
    expect(after.type, 'in');
    expect(after.categoryId, inCat.id);
    expect(after.source, 'notification');
  });
}
