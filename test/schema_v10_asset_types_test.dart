import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v10 onCreate seeds 5 asset types; accounts.type are ids', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 11);

    final tables = {
      for (final r in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get())
        r.read<String>('name')
    };
    expect(tables.contains('asset_types'), isTrue);
    expect(tables.contains('subscriptions'), isFalse);

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final types = await db.loadAssetTypes(ledger.id, includeArchived: true);
    expect(types.map((t) => t.name).toSet(), {
      '现金',
      '银行卡',
      '电子钱包',
      '信用卡',
      '其他',
    });
    expect(types.length, 5);

    final nameToId = {for (final t in types) t.name: t.id};
    final accounts = await db.loadActiveAccounts(ledger.id);
    expect(accounts, isNotEmpty);
    for (final a in accounts) {
      expect(nameToId.values.contains(a.type), isTrue,
          reason: 'account ${a.name} type=${a.type} not an asset_types id');
    }
  });

  test('resolveAssetTypeId maps legacy codes and names', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final types = await db.loadAssetTypes(ledger.id, includeArchived: true);
    final nameToId = {for (final t in types) t.name: t.id};

    expect(await db.resolveAssetTypeId(ledgerId: ledger.id, raw: 'cash'),
        nameToId['现金']);
    expect(await db.resolveAssetTypeId(ledgerId: ledger.id, raw: 'credit'),
        nameToId['信用卡']);
    expect(await db.resolveAssetTypeId(ledgerId: ledger.id, raw: '银行卡'),
        nameToId['银行卡']);
    expect(await db.resolveAssetTypeId(ledgerId: ledger.id, raw: ''),
        nameToId['其他']);
    expect(await db.resolveAssetTypeId(ledgerId: ledger.id, raw: 'unknown-x'),
        nameToId['其他']);
    expect(
      await db.resolveAssetTypeId(
          ledgerId: ledger.id, raw: nameToId['电子钱包']!),
      nameToId['电子钱包'],
    );
  });

  test('createAssetType rejects blank and duplicate; delete blocks in-use',
      () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();

    expect(
      () => db.createAssetType(ledgerId: ledger.id, name: '  '),
      throwsA(isA<StateError>()),
    );

    final id = await db.createAssetType(ledgerId: ledger.id, name: '房产');
    expect(
      () => db.createAssetType(ledgerId: ledger.id, name: '房产'),
      throwsA(isA<StateError>()),
    );

    await db.createAccount(
      ledgerId: ledger.id,
      name: '房子',
      currency: 'CNY',
      type: id,
    );
    expect(
      () => db.deleteAssetType(id),
      throwsA(isA<StateError>()),
    );

    final cash = (await db.loadAssetTypes(ledger.id))
        .firstWhere((t) => t.name == '现金');
    // Move account off 房产 then delete ok
    final house = (await db.loadActiveAccounts(ledger.id))
        .firstWhere((a) => a.name == '房子');
    await db.updateAccount(
      id: house.id,
      name: house.name,
      currency: house.currency,
      type: cash.id,
      openingBalanceMinor: house.openingBalanceMinor,
      icon: house.icon,
    );
    await db.deleteAssetType(id);
    final names =
        (await db.loadAssetTypes(ledger.id, includeArchived: true))
            .map((t) => t.name)
            .toSet();
    expect(names.contains('房产'), isFalse);
  });
}
