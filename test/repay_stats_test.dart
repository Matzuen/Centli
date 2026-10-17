import 'package:centli/data/db/centli_database.dart';
import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T0B-5 repay confirm exclude from stats', () {
    late CentliDatabase db;
    late String ledgerId;
    late String accountId;
    late String outCatId;

    setUp(() async {
      db = CentliDatabase.forTesting(NativeDatabase.memory());
      await db.seedDefaults();
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      ledgerId = ledger.id;
      accountId = (await db.loadActiveAccounts(ledgerId)).first.id;
      outCatId = (await db.loadCategories(ledgerId, 'out')).first.id;
    });

    tearDown(() async => db.close());

    Future<({int income, int expense})> monthExpense() async {
      final now = DateTime.now();
      final start =
          DateTime(now.year, now.month, 1).toUtc().millisecondsSinceEpoch;
      final end =
          DateTime(now.year, now.month + 1, 1).toUtc().millisecondsSinceEpoch;
      final by = await db.rangeSummaryByCurrency(ledgerId, start, end);
      final cny = by['CNY'];
      return (income: cny?.income ?? 0, expense: cny?.expense ?? 0);
    }

    test('confirm repay defaults includeInStat=0; expense unchanged', () async {
      await db.insertManualTransaction(
        ledgerId: ledgerId,
        type: 'out',
        amountMinor: 10000,
        currency: 'CNY',
        accountId: accountId,
        categoryId: outCatId,
      );
      final before = await monthExpense();
      expect(before.expense, 10000);

      final pendingId = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: 'com.eg.android.AlipayGphone',
        rawTitle: '10月花呗账单还清啦',
        rawText: '从银行卡还款12.54元，本月账单已还清',
        dedupeKey: 'repay-stat-1',
        amountMinor: 1254,
        currency: 'CNY',
        parseOk: true,
        direction: 'repay',
      );
      expect(pendingId, isNotNull);

      await db.confirmPendingCapture(
        pendingId: pendingId!,
        amountMinor: 1254,
        currency: 'CNY',
        accountId: accountId,
        categoryId: outCatId,
        type: 'out',
        includeInStat: 0,
        includeInBudget: 0,
      );

      final txns = await db.loadTransactionsForExport(ledgerId);
      final repay = txns.firstWhere((t) => t.amountMinor == 1254);
      expect(repay.includeInStat, 0);
      expect(repay.includeInBudget, 0);
      expect(repay.type, 'out');

      final after = await monthExpense();
      expect(after.expense, before.expense);
    });

    test('confirm repay with includeInStat=1 increases expense', () async {
      await db.insertManualTransaction(
        ledgerId: ledgerId,
        type: 'out',
        amountMinor: 10000,
        currency: 'CNY',
        accountId: accountId,
        categoryId: outCatId,
      );
      final before = await monthExpense();

      final pendingId = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: 'com.eg.android.AlipayGphone',
        rawTitle: '还清',
        rawText: '还款20.00元已还清',
        dedupeKey: 'repay-stat-2',
        amountMinor: 2000,
        currency: 'CNY',
        parseOk: true,
        direction: 'repay',
      );

      await db.confirmPendingCapture(
        pendingId: pendingId!,
        amountMinor: 2000,
        currency: 'CNY',
        accountId: accountId,
        categoryId: outCatId,
        type: 'out',
        includeInStat: 1,
        includeInBudget: 1,
      );

      final after = await monthExpense();
      expect(after.expense, before.expense + 2000);
    });
  });

  group('T0B-6 repay dedupe', () {
    test('same repay notice injected twice → one pending row', () async {
      final db = CentliDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.seedDefaults();
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();

      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '10月花呗账单还清啦',
        text: '10月花呗账单还清啦，从银行卡还款12.54元，本月账单已还清',
        whenMs: DateTime(2026, 10, 17, 11, 43).millisecondsSinceEpoch,
      );
      final parsed = parseNotification(raw);
      expect(parsed.ok, isTrue);
      final key = dedupeKey(raw, parsed);

      final id1 = await db.ingestParsedNotification(
        ledgerId: ledger.id,
        sourcePkg: raw.pkg,
        rawTitle: raw.title,
        rawText: raw.text,
        dedupeKey: key,
        amountMinor: parsed.amountMinor,
        currency: parsed.currency ?? 'CNY',
        parseOk: parsed.ok,
        direction: parsed.direction,
      );
      final id2 = await db.ingestParsedNotification(
        ledgerId: ledger.id,
        sourcePkg: raw.pkg,
        rawTitle: raw.title,
        rawText: raw.text,
        dedupeKey: key,
        amountMinor: parsed.amountMinor,
        currency: parsed.currency ?? 'CNY',
        parseOk: parsed.ok,
        direction: parsed.direction,
      );
      expect(id1, isNotNull);
      expect(id2, isNull);

      final rows = await (db.select(db.pendingCaptures)
            ..where((t) => t.ledgerId.equals(ledger.id)))
          .get();
      expect(rows.length, 1);
    });
  });
}
