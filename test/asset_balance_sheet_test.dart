import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/assets/asset_balance_recognize_sheet.dart';
import 'package:centli/features/assets/asset_balance_vision.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 截图识别的写入路径：币种不一致的行不能被应用。
///
/// `adjustAccountBalance` 只在账户自己的币种里移动余额，所以把一个按 CNY
/// 识别出来的数字应用到 USD 账户（或反之）会静默写错金额。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async => db.close());

  Future<void> openSheet(
    WidgetTester tester, {
    required List<Account> accounts,
    required Map<String, int> balances,
    required List<AssetType> types,
    required AssetBalanceVisionResult result,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CentliTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: Builder(
                  builder: (inner) => FilledButton(
                    onPressed: () => showAssetBalanceRecognizeSheet(
                      inner,
                      ref,
                      ledgerId: 'L1',
                      result: result,
                      accounts: accounts,
                      balances: balances,
                      types: types,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('a currency mismatch is shown but cannot be applied',
      (tester) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await db.createAccount(
      ledgerId: ledger.id,
      name: '招商银行',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 10000,
    );
    final accounts = await db.loadActiveAccounts(ledger.id);
    final types = await db.loadAssetTypes(ledger.id);
    final cny = accounts.firstWhere((a) => a.name == '招商银行');
    final balances = await db.accountBalances(ledger.id);

    // The model recognised the same account as USD 12.34.
    final result = parseAssetBalanceVisionMap({
      'accounts': [
        {
          'name': '招商银行',
          'balance': 12.34,
          'currency': 'USD',
          'typeHint': types.first.name,
        },
      ],
    }, typeNames: [for (final t in types) t.name]);

    await openSheet(
      tester,
      accounts: accounts,
      balances: balances,
      types: types,
      result: result,
    );

    expect(find.textContaining('币种不一致'), findsOneWidget);
    // Nothing selected → the apply button is disabled, so no write can happen.
    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '应用所选（0）'),
    );
    expect(apply.onPressed, isNull);

    final before = (await db.accountBalances(ledger.id))[cny.id];
    expect(before, 10000, reason: 'balance must be untouched');
  });

  testWidgets('a same-currency mismatch is offered as a correction',
      (tester) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await db.createAccount(
      ledgerId: ledger.id,
      name: '支付宝',
      currency: 'CNY',
      type: 'cash',
      openingBalanceMinor: 5000,
    );
    final accounts = await db.loadActiveAccounts(ledger.id);
    final types = await db.loadAssetTypes(ledger.id);
    final balances = await db.accountBalances(ledger.id);

    final result = parseAssetBalanceVisionMap({
      'accounts': [
        {
          'name': '支付宝',
          'balance': 128.5,
          'currency': 'CNY',
          'typeHint': '电子钱包',
        },
      ],
    }, typeNames: [for (final t in types) t.name]);

    await openSheet(
      tester,
      accounts: accounts,
      balances: balances,
      types: types,
      result: result,
    );

    expect(find.textContaining('校正余额'), findsOneWidget);
    expect(find.textContaining('币种不一致'), findsNothing);
    expect(find.widgetWithText(FilledButton, '应用所选（1）'), findsOneWidget);
  });
}
