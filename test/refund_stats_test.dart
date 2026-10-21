import 'dart:io';

import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('type=refund rows are ignored by range summary', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final outCat = (await db.loadCategories(ledger.id, 'out')).first;
    final inCat = (await db.loadCategories(ledger.id, 'in')).first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 10000,
      currency: 'CNY',
      accountId: account.id,
      categoryId: outCat.id,
    );
    // 历史脏数据：不再参与统计。
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'refund',
      amountMinor: 3000,
      currency: 'CNY',
      accountId: account.id,
      categoryId: outCat.id,
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'in',
      amountMinor: 5000,
      currency: 'CNY',
      accountId: account.id,
      categoryId: inCat.id,
    );

    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, 1).toUtc().millisecondsSinceEpoch;
    final end =
        DateTime(now.year, now.month + 1, 1).toUtc().millisecondsSinceEpoch;
    final byCcy = await db.rangeSummaryByCurrency(ledger.id, start, end);
    final cny = byCcy['CNY']!;
    expect(cny.income, 5000);
    expect(cny.expense, 10000);
  });

  test('pending confirm no longer maps refund to type refund', () {
    final src =
        File('lib/features/pending/pending_page.dart').readAsStringSync();
    expect(src.contains("txnType = 'refund'"), isFalse);
    expect(src.contains("isRefundSignal"), isTrue);
    expect(src.contains("'退款'"), isTrue);
  });
}
