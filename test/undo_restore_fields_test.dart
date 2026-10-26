import 'package:centli/data/db/centli_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Soft-delete undo = undelete; field-edit undo = write back old values.
void main() {
  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Transaction> seedOut() async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final outCats = await db.loadCategories(ledger.id, 'out');
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 1200,
      currency: 'CNY',
      accountId: accounts.first.id,
      categoryId: outCats.first.id,
      note: '咖啡',
    );
    return (await db.watchRecentTransactions(ledger.id, limit: 1).first).single;
  }

  test('soft-delete then undelete restores the bill', () async {
    final before = await seedOut();
    await db.softDeleteTransaction(before.id);
    expect((await db.getTransaction(before.id))!.deletedAt, isNotNull);

    await db.undeleteTransaction(before.id);
    final after = (await db.getTransaction(before.id))!;
    expect(after.deletedAt, isNull);
    expect(after.amountMinor, before.amountMinor);
    expect(after.accountId, before.accountId);
    expect(after.categoryId, before.categoryId);
  });

  test('batch soft-delete then undeleteTransactions restores all', () async {
    final a = await seedOut();
    final b = await seedOut();
    final ids = [a.id, b.id];
    final n = await db.softDeleteTransactions(ids);
    expect(n, 2);

    final restored = await db.undeleteTransactions(ids);
    expect(restored, greaterThanOrEqualTo(2));
    expect((await db.getTransaction(a.id))!.deletedAt, isNull);
    expect((await db.getTransaction(b.id))!.deletedAt, isNull);
  });

  test('category/account edit undo writes back old values', () async {
    final before = await seedOut();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final outCats = await db.loadCategories(ledger.id, 'out');
    expect(accounts.length, greaterThan(1));
    expect(outCats.length, greaterThan(1));

    final newAccount = accounts.firstWhere((a) => a.id != before.accountId);
    final newCat = outCats.firstWhere((c) => c.id != before.categoryId);

    await db.updateTransactionFields(
      id: before.id,
      accountId: newAccount.id,
      categoryId: newCat.id,
    );
    final mid = (await db.getTransaction(before.id))!;
    expect(mid.accountId, newAccount.id);
    expect(mid.categoryId, newCat.id);

    // Undo path used by detail save snackbar.
    await db.updateTransactionFields(
      id: before.id,
      accountId: before.accountId,
      toAccountId: Value(before.toAccountId),
      categoryId: before.categoryId,
      toAmountMinor: Value(before.toAmountMinor),
      fxRate: Value(before.fxRate),
    );
    final after = (await db.getTransaction(before.id))!;
    expect(after.accountId, before.accountId);
    expect(after.categoryId, before.categoryId);
    expect(after.toAccountId, before.toAccountId);
  });
}
