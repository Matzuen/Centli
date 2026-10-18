import 'package:centli/core/utils/date_range.dart';
import 'package:centli/core/utils/fx.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/home/home_page.dart';
import 'package:centli/features/stats/stats_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home/stats summary providers re-emit after writing a transaction', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final base = ledger.baseCurrency;
    final range = DateRangeWindow.lastDays(days: 30);
    final args = (
      ledgerId: ledger.id,
      key: range.key,
      startMs: range.startMs,
      endMs: range.endMs,
      base: base,
    );
    final nwArgs = (ledgerId: ledger.id, base: base);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // Keep providers alive so txnWriteSignal watch can trigger rebuilds.
    final homeSub = container.listen(homeRangeBaseProvider(args), (_, _) {});
    final nwSub = container.listen(homeNetWorthProvider(nwArgs), (_, _) {});
    final statsSub =
        container.listen(statsTotalsProvider(args), (_, _) {});
    addTearDown(homeSub.close);
    addTearDown(nwSub.close);
    addTearDown(statsSub.close);

    final homeBefore =
        await container.read(homeRangeBaseProvider(args).future);
    final nwBefore = await container.read(homeNetWorthProvider(nwArgs).future);
    final statsBefore =
        await container.read(statsTotalsProvider(args).future);

    expect(homeBefore.expenseMinor, 0);
    expect(statsBefore.expenseMinor, 0);

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 2500,
      currency: base,
      accountId: account.id,
    );

    // Wait until FutureProviders rebuild from txnWriteSignal (no invalidate).
    BaseRangeSummary? homeAfter;
    StatsTotals? statsAfter;
    BaseNetWorth? nwAfter;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final h = container.read(homeRangeBaseProvider(args)).valueOrNull;
      final s = container.read(statsTotalsProvider(args)).valueOrNull;
      final n = container.read(homeNetWorthProvider(nwArgs)).valueOrNull;
      if (h != null &&
          s != null &&
          n != null &&
          h.expenseMinor == 2500 &&
          s.expenseMinor == 2500 &&
          n.totalMinor != nwBefore.totalMinor) {
        homeAfter = h;
        statsAfter = s;
        nwAfter = n;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    expect(homeAfter, isNotNull, reason: 'home range summary did not re-emit');
    expect(statsAfter, isNotNull, reason: 'stats summary did not re-emit');
    expect(nwAfter, isNotNull, reason: 'home net worth did not re-emit');
    expect(homeAfter!.expenseMinor, 2500);
    expect(statsAfter!.expenseMinor, 2500);
    expect(homeAfter.expenseMinor, isNot(homeBefore.expenseMinor));
    expect(statsAfter.expenseMinor, isNot(statsBefore.expenseMinor));
    expect(nwAfter!.totalMinor, isNot(nwBefore.totalMinor));
  });
}
