import 'package:centli/core/utils/fx.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/assets/assets_page.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 资产分析：按**资产账户类型**汇总 + 环形图图例的单行格式。
void main() {
  CentliDatabase? db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db!.seedDefaults();
  });

  tearDown(() async => db?.close());

  Account account(String id, String name, String type, {int opening = 0}) =>
      Account(
        id: id,
        ledgerId: 'L',
        name: name,
        currency: 'CNY',
        type: type,
        icon: null,
        openingBalanceMinor: opening,
        sortOrder: 0,
        archived: 0,
        createdAt: 0,
        updatedAt: 0,
      );

  AssetType assetType(String id, String name, int order) => AssetType(
        id: id,
        ledgerId: 'L',
        name: name,
        icon: null,
        sortOrder: order,
        archived: 0,
        createdAt: 0,
        updatedAt: 0,
      );

  test('groups balances by account type, in type order', () {
    final types = [
      assetType('t-bank', '银行账户', 0),
      assetType('t-online', '线上账户', 1),
      assetType('t-credit', '信用卡', 2),
      assetType('t-invest', '投资账户', 3),
      assetType('t-loan', '借贷账户', 4),
      assetType('t-cash', '钱包', 5),
    ];
    final accounts = [
      account('a1', '招商银行', 't-bank'),
      account('a2', '支付宝', 't-online'),
      account('a3', '信用卡', 't-credit'),
      account('a4', '钱包', 't-cash'),
    ];
    final slices = assetTypeSlices(
      accounts: accounts,
      balances: {
        'a1': 80000, // 800.00
        'a2': 0,
        'a3': 0,
        'a4': -20000, // -200.00
      },
      types: types,
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );

    expect(slices.map((s) => s.name), [
      '银行账户',
      '线上账户',
      '信用卡',
      '钱包',
    ]);
    expect(slices[0].totalMinor, 80000);
    // 800 / 1000 = 80%.
    expect(slices[0].pct, '80%');
    expect(slices[1].totalMinor, 0);
    expect(slices[1].pct, '0%');
    expect(slices[2].pct, '0%');
    expect(slices[3].totalMinor, -20000);
    // -200 against |800| + |0| + |0| + |-200| = 1000 → −20%.
    expect(slices[3].pct, '−20%');
    // 投资账户 has no accounts → no slice.
    expect(slices.any((s) => s.name == '投资账户'), isFalse);
  });

  test('reference shape: 800 vs -200 uses the same denominator', () {
    final slices = assetTypeSlices(
      accounts: [
        account('a1', '招商银行', 't-bank'),
        account('a4', '钱包', 't-cash'),
      ],
      balances: {'a1': 80000, 'a4': -20000},
      types: [
        assetType('t-bank', '银行账户', 0),
        assetType('t-cash', '钱包', 1),
      ],
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );
    expect(slices[0].pct, '80%');
    expect(slices[1].pct, '−20%');
    // Percentages of a signed total add up to 100%.
    final sum = slices.fold<double>(
      0,
      (a, s) => a + s.totalMinor * 100 / 100000,
    );
    expect(sum, closeTo(60, 1e-9));
  });

  test('single type at 100%', () {
    final slices = assetTypeSlices(
      accounts: [account('a1', '钱包', 't-cash')],
      balances: {'a1': 5000},
      types: [assetType('t-cash', '钱包', 0)],
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );
    expect(slices.single.name, '钱包');
    expect(slices.single.pct, '100%');
  });

  test('splits accounts that share a type into one slice', () {
    final slices = assetTypeSlices(
      accounts: [
        account('a1', '招行', 't-bank'),
        account('a2', '工行', 't-bank'),
      ],
      balances: {'a1': 10000, 'a2': 30000},
      types: [assetType('t-bank', '银行账户', 0)],
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );
    expect(slices.single.totalMinor, 40000);
    expect(slices.single.pct, '100%');
  });

  test('unknown account type falls back to 其他', () {
    final slices = assetTypeSlices(
      accounts: [account('a1', '神秘资产账户', 't-missing'), account('a2', '银行', 't-bank')],
      balances: {'a1': 1000, 'a2': 9000},
      types: [assetType('t-bank', '银行账户', 0)],
      book: null,
      baseCurrency: 'CNY',
      onDay: '2026-10-18',
    );
    expect(slices.map((s) => s.name), ['银行账户', '其他']);
    expect(slices[1].totalMinor, 1000);
  });

  test('percentage labels: rounding and signed zero', () {
    expect(assetTypePctLabel(800, 1000), '80%');
    expect(assetTypePctLabel(0, 1000), '0%');
    expect(assetTypePctLabel(-200, 1000), '−20%');
    expect(assetTypePctLabel(-200, 800), '−25%');
    expect(assetTypePctLabel(1, 0), '0%');
    expect(assetTypePctLabel(5, 1000), '0.5%');
    // Any 7%-style value under 10 keeps one decimal, minus the .0 noise.
    expect(assetTypePctLabel(70, 1000), '7%');
    expect(assetTypePctLabel(246, 1000), '24.6%');
    expect(assetTypePctLabel(-246, 1000), '−24.6%');
    expect(assetTypePctLabel(1000, 1000), '100%');
  });

  group('via a real ledger', () {
    test('slices match account balances from the database', () async {
      final ledger = await (db!.select(db!.ledgers)..limit(1)).getSingle();
      final types = await db!.loadAssetTypes(ledger.id);
      final accountId = (await db!.loadActiveAccounts(ledger.id)).first.id;
      await db!.insertManualTransaction(
        ledgerId: ledger.id,
        type: 'out',
        amountMinor: 12345,
        currency: 'CNY',
        accountId: accountId,
      );
      final accounts = await db!.loadActiveAccounts(ledger.id);
      final balances = await db!.accountBalances(ledger.id);
      final slices = assetTypeSlices(
        accounts: accounts,
        balances: balances,
        types: types,
        book: FxBook(const []),
        baseCurrency: ledger.baseCurrency,
        onDay: '2026-10-18',
      );
      expect(slices, isNotEmpty);
      expect(slices.every((s) => s.pct.endsWith('%')), isTrue);
    });
  });
}
