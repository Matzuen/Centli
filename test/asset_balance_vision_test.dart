import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/assets/asset_balance_vision.dart';
import 'package:centli/features/ledger/llm_text_fill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAssetBalanceVisionMap', () {
    test('keeps accounts and maps type hints', () {
      final r = parseAssetBalanceVisionMap(
        {
          'screenKind': 'asset_overview',
          'accounts': [
            {
              'name': '支付宝',
              'balance': 128.5,
              'currency': 'CNY',
              'typeHint': '电子钱包',
              'isLiability': false,
            },
            {
              'name': '招行信用卡',
              'balance': -87.89,
              'currency': 'CNY',
              'typeHint': '信用卡',
              'isLiability': true,
            },
          ],
          'warnings': ['右下角金额略糊'],
        },
        typeNames: const ['现金', '银行卡', '电子钱包', '信用卡', '其他'],
      );
      expect(r.accounts.length, 2);
      expect(r.accounts.first.name, '支付宝');
      expect(r.accounts.first.balance, 128.5);
      expect(r.accounts.last.isLiability, isTrue);
      expect(r.warnings, ['右下角金额略糊']);
    });

    test('guesses type when hint missing', () {
      final r = parseAssetBalanceVisionMap(
        {
          'accounts': [
            {'name': '微信零钱', 'balance': 20},
          ],
        },
        typeNames: const ['现金', '银行卡', '电子钱包', '其他'],
      );
      expect(r.accounts.single.typeHint, '电子钱包');
    });

    test('empty accounts throws', () {
      expect(
        () => parseAssetBalanceVisionMap({'accounts': []}),
        throwsA(isA<LlmVisionException>()),
      );
    });
  });

  group('matchAccountByName', () {
    Account acc(String id, String name) => Account(
          id: id,
          ledgerId: 'L',
          name: name,
          currency: 'CNY',
          type: 't',
          icon: null,
          openingBalanceMinor: 0,
          sortOrder: 0,
          archived: 0,
          createdAt: 0,
          updatedAt: 0,
        );

    test('exact and contains', () {
      final list = [acc('1', '支付宝'), acc('2', '招商银行')];
      expect(matchAccountByName('支付宝', list)?.id, '1');
      expect(matchAccountByName('招商', list)?.id, '2');
      expect(matchAccountByName('没有的资产账户', list), isNull);
    });
  });
}
