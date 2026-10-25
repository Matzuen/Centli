import 'package:centli/data/db/centli_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CentliDatabase db;
  late String ledgerA;
  late String ledgerB;
  late String cashA;
  late String cashB;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledgers = await db.select(db.ledgers).get();
    expect(ledgers, isNotEmpty);
    ledgerA = ledgers.first.id;

    final ledgerBRow = await db.createLedgerWithDefaults(
      name: '小金库',
      baseCurrency: 'CNY',
      switchTo: false,
    );
    ledgerB = ledgerBRow.id;

    final accountsA = await db.loadActiveAccounts(ledgerA);
    expect(accountsA, isNotEmpty);
    cashA = accountsA.first.id;

    await db.createAccount(
      ledgerId: ledgerB,
      name: '小金库-支付宝',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 0,
    );
    final accountsB = await db.loadActiveAccounts(ledgerB);
    cashB = accountsB.firstWhere((a) => a.name == '小金库-支付宝').id;
  });

  tearDown(() async {
    await db.close();
  });

  test('cross-ledger transfer: both ledgers list a row; balances once', () async {
    final id = await db.createTransferTransaction(
      accountId: cashA,
      toAccountId: cashB,
      amountMinor: 11113900,
      currency: 'CNY',
      happenAt: DateTime.utc(2026, 10, 19, 12),
      ledgerId: ledgerA,
    );

    final fromRows = await db
        .watchTransactionsInRange(
          ledgerA,
          DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
          DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
          limit: 0,
        )
        .first;
    final toRows = await db
        .watchTransactionsInRange(
          ledgerB,
          DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
          DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
          limit: 0,
        )
        .first;

    expect(fromRows.where((t) => t.type == 'transfer'), hasLength(1));
    expect(toRows.where((t) => t.type == 'transfer'), hasLength(1));
    expect(fromRows.first.id, id);
    expect(toRows.first.source, CentliDatabase.kTransferMirrorSource);
    expect(fromRows.first.transferGroupId, toRows.first.transferGroupId);

    final balA = await db.accountBalances(ledgerA);
    final balB = await db.accountBalances(ledgerB);
    // from account decreased, to account increased — not double-counted
    expect(balA[cashA]! , lessThan(0)); // opening 0 - transfer
    expect(balA[cashA], -11113900);
    expect(balB[cashB], 11113900);

    // Income/expense unchanged in both ledgers
    final lifeA = await db.lifetimeTotalsInBase(ledgerA, 'CNY');
    final lifeB = await db.lifetimeTotalsInBase(ledgerB, 'CNY');
    expect(lifeA.incomeMinor, 0);
    expect(lifeB.incomeMinor, 0);
  });

  test('same-ledger transfer stays single row', () async {
    final accountsA = await db.loadActiveAccounts(ledgerA);
    expect(accountsA.length, greaterThanOrEqualTo(2));
    final a0 = accountsA[0].id;
    final a1 = accountsA[1].id;
    await db.createTransferTransaction(
      accountId: a0,
      toAccountId: a1,
      amountMinor: 500,
      currency: 'CNY',
      ledgerId: ledgerA,
    );
    final rows = await (db.select(db.transactions)
          ..where((t) => t.type.equals('transfer') & t.deletedAt.isNull()))
        .get();
    expect(rows, hasLength(1));
    expect(rows.first.source, isNot(CentliDatabase.kTransferMirrorSource));
  });

  test('soft-delete removes both sides of cross-ledger transfer', () async {
    final id = await db.createTransferTransaction(
      accountId: cashA,
      toAccountId: cashB,
      amountMinor: 1000,
      currency: 'CNY',
      ledgerId: ledgerA,
    );
    await db.softDeleteTransaction(id);
    final live = await (db.select(db.transactions)
          ..where((t) => t.deletedAt.isNull() & t.type.equals('transfer')))
        .get();
    expect(live, isEmpty);

    final balB = await db.accountBalances(ledgerB);
    expect(balB[cashB], 0);
  });

  test('backfill creates mirror for legacy single-row cross-ledger transfer',
      () async {
    // Legacy: one row in from-ledger only (pre-fix).
    final group = 'legacy-group-1';
    await db.insertManualTransaction(
      ledgerId: ledgerA,
      type: 'transfer',
      amountMinor: 250000,
      currency: 'CNY',
      accountId: cashA,
      toAccountId: cashB,
      transferGroupId: group,
      happenAt: DateTime.utc(2026, 10, 19),
    );

    // Destination has balance but no流水
    expect((await db.accountBalances(ledgerB))[cashB], 250000);
    final before = await db
        .watchTransactionsInRange(
          ledgerB,
          0,
          DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
          limit: 0,
        )
        .first;
    expect(before.where((t) => t.type == 'transfer'), isEmpty);

    final n = await db.backfillCrossLedgerTransferMirrors();
    expect(n, 1);

    final after = await db
        .watchTransactionsInRange(
          ledgerB,
          0,
          DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
          limit: 0,
        )
        .first;
    expect(after.where((t) => t.type == 'transfer'), hasLength(1));
    expect(after.first.source, CentliDatabase.kTransferMirrorSource);
    // Balance unchanged (no double count)
    expect((await db.accountBalances(ledgerB))[cashB], 250000);

    // Idempotent
    expect(await db.backfillCrossLedgerTransferMirrors(), 0);
  });

  test('editing transfer syncs mirror amount', () async {
    final id = await db.createTransferTransaction(
      accountId: cashA,
      toAccountId: cashB,
      amountMinor: 10000,
      currency: 'CNY',
      ledgerId: ledgerA,
    );
    await db.updateManualTransaction(
      id: id,
      type: 'transfer',
      amountMinor: 20000,
      currency: 'CNY',
      accountId: cashA,
      toAccountId: cashB,
      toAmountMinor: 20000,
    );
    final mirrors = await (db.select(db.transactions)
          ..where(
            (t) =>
                t.source.equals(CentliDatabase.kTransferMirrorSource) &
                t.deletedAt.isNull(),
          ))
        .get();
    expect(mirrors, hasLength(1));
    expect(mirrors.first.amountMinor, 20000);
    expect((await db.accountBalances(ledgerB))[cashB], 20000);
  });
}
