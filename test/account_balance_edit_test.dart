import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 编辑资产账户 → 「当前金额」→ 保存时记一笔「余额校正」把余额调到该值，
/// 期初余额保持不变（不计入统计 / 预算）。
void main() {
  late CentliDatabase db;
  late String ledgerId;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    ledgerId = ledger.id;
  });

  tearDown(() async => db.close());

  Future<Account> accountOf(String id) async => (await db.getAccount(id))!;

  test('adjusting the balance writes a 余额校正 and keeps 期初', () async {
    await db.createAccount(
      ledgerId: ledgerId,
      name: '支付宝',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 0,
    );
    final accounts = await db.loadActiveAccounts(ledgerId);
    final acc = accounts.firstWhere((a) => a.name == '支付宝');

    // Spend 100 first so the current balance is not the opening balance.
    await db.insertManualTransaction(
      ledgerId: ledgerId,
      type: 'out',
      amountMinor: 10000,
      currency: 'CNY',
      accountId: acc.id,
    );
    final balances = await db.accountBalances(ledgerId);
    expect(balances[acc.id], -10000);

    // User types the real current amount: -58.50 → record the correction.
    await db.adjustAccountBalance(
      account: acc,
      targetBalanceMinor: -5850,
      currentBalanceMinor: -10000,
    );

    final after = await db.accountBalances(ledgerId);
    expect(after[acc.id], -5850, reason: 'balance follows the typed amount');

    // 期初 unchanged.
    final reloaded = await accountOf(acc.id);
    expect(reloaded.openingBalanceMinor, 0);

    // Exactly one correction row, excluded from stats and budget.
    final rows = await db.loadTransactionsForExport(ledgerId);
    final corrections =
        rows.where((t) => (t.note ?? '') == '余额校正').toList();
    expect(corrections, hasLength(1));
    expect(corrections.single.includeInStat, 0);
    expect(corrections.single.includeInBudget, 0);
    expect(corrections.single.type, 'in'); // -100 → -58.50 is an increase
    expect(corrections.single.amountMinor, 4150);
  });

  test('editing an account keeps its opening balance', () async {
    await db.createAccount(
      ledgerId: ledgerId,
      name: '现金',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 5000,
    );
    final acc = (await db.loadActiveAccounts(ledgerId))
        .firstWhere((a) => a.name == '现金');

    // The editor only changes name/type/icon and re-submits the ORIGINAL
    // opening balance, so a rename must not move the balance base.
    await db.updateAccount(
      id: acc.id,
      name: '现金钱包',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: acc.openingBalanceMinor,
      icon: 'wallet',
    );
    final reloaded = await accountOf(acc.id);
    expect(reloaded.name, '现金钱包');
    // Seeded demo accounts: only assert what updateAccount preserved.
    expect(reloaded.openingBalanceMinor, acc.openingBalanceMinor);
    final balances = await db.accountBalances(ledgerId);
    expect(balances[acc.id], acc.openingBalanceMinor);
  });

  test('typing the same amount writes nothing', () async {
    await db.createAccount(
      ledgerId: ledgerId,
      name: '零钱',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 2000,
    );
    final acc = (await db.loadActiveAccounts(ledgerId))
        .firstWhere((a) => a.name == '零钱');
    await db.adjustAccountBalance(
      account: acc,
      targetBalanceMinor: 2000,
      currentBalanceMinor: 2000,
    );
    final rows = await db.loadTransactionsForExport(ledgerId);
    expect(rows.where((t) => (t.note ?? '') == '余额校正'), isEmpty);
  });

  test('negative target balance is allowed (credit card / overdraft)',
      () async {
    await db.createAccount(
      ledgerId: ledgerId,
      name: '信用卡',
      currency: 'CNY',
      type: 'cash',
    );
    final acc = (await db.loadActiveAccounts(ledgerId))
        .firstWhere((a) => a.name == '信用卡');
    await db.adjustAccountBalance(
      account: acc,
      targetBalanceMinor: -8789,
      currentBalanceMinor: 0,
    );
    final balances = await db.accountBalances(ledgerId);
    expect(balances[acc.id], -8789);
  });
}
