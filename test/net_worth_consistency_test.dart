import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/assets/assets_page.dart';
import 'package:centli/features/home/home_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home and assets net-worth providers agree on same fixture', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    expect(accounts, isNotEmpty);
    final cash = accounts.first;

    await db.updateAccount(
      id: cash.id,
      name: cash.name,
      currency: cash.currency,
      type: cash.type,
      openingBalanceMinor: 100000,
      icon: cash.icon,
    );

    late Account credit;
    if (accounts.length >= 2) {
      credit = accounts[1];
      await db.updateAccount(
        id: credit.id,
        name: credit.name,
        currency: credit.currency,
        type: credit.type,
        openingBalanceMinor: -20000,
        icon: credit.icon,
      );
    } else {
      await db.createAccount(
        ledgerId: ledger.id,
        name: '信用卡',
        currency: ledger.baseCurrency,
        type: 'credit',
        openingBalanceMinor: -20000,
      );
      credit = (await db.loadActiveAccounts(ledger.id))
          .firstWhere((a) => a.name == '信用卡');
    }

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 2500,
      currency: ledger.baseCurrency,
      accountId: cash.id,
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'in',
      amountMinor: 800,
      currency: ledger.baseCurrency,
      accountId: cash.id,
    );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final nwArgs = (ledgerId: ledger.id, base: ledger.baseCurrency);
    final homeSub = container.listen(homeNetWorthProvider(nwArgs), (_, _) {});
    final assetsSub =
        container.listen(assetsNetWorthProvider(nwArgs), (_, _) {});
    addTearDown(homeSub.close);
    addTearDown(assetsSub.close);

    final homeNw = await container.read(homeNetWorthProvider(nwArgs).future);
    final assetsNw =
        await container.read(assetsNetWorthProvider(nwArgs).future);

    expect(homeNw.totalMinor, assetsNw.totalMinor);
    expect(homeNw.totalMinor, 100000 - 20000 - 2500 + 800);

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 100,
      currency: ledger.baseCurrency,
      accountId: cash.id,
    );

    container.invalidate(homeNetWorthProvider(nwArgs));
    container.invalidate(assetsNetWorthProvider(nwArgs));
    final home2 = await container.read(homeNetWorthProvider(nwArgs).future);
    final assets2 = await container.read(assetsNetWorthProvider(nwArgs).future);
    expect(home2.totalMinor, assets2.totalMinor);
    expect(home2.totalMinor, homeNw.totalMinor - 100);
  });
}