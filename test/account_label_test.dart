import 'package:flutter_test/flutter_test.dart';
import 'package:centli/core/utils/account_label.dart';

void main() {
  test('same-ledger: account only even when ledgerName present', () {
    expect(
      formatLedgerAccountLabel(
        accountName: '支付宝',
        ledgerName: '我的账本',
      ),
      '支付宝',
    );
    expect(
      formatLedgerAccountLabel(
        accountName: '农业银行',
        ledgerName: '我的账本',
        includeLedger: false,
      ),
      '农业银行',
    );
  });

  test('cross-ledger: 账本-账户', () {
    expect(
      formatLedgerAccountLabel(
        accountName: '农业银行',
        ledgerName: '我的账本',
        includeLedger: true,
      ),
      '我的账本-农业银行',
    );
  });

  test('missing ledger falls back to account', () {
    expect(
      formatLedgerAccountLabel(accountName: '现金', ledgerName: null),
      '现金',
    );
    expect(
      formatLedgerAccountLabel(
        accountName: '现金',
        ledgerName: '  ',
        includeLedger: true,
      ),
      '现金',
    );
  });

  test('trims whitespace when includeLedger', () {
    expect(
      formatLedgerAccountLabel(
        accountName: ' 现金 ',
        ledgerName: ' 小金库 ',
        includeLedger: true,
      ),
      '小金库-现金',
    );
  });

  test('empty account with includeLedger returns ledger', () {
    expect(
      formatLedgerAccountLabel(
        accountName: '  ',
        ledgerName: '我的账本',
        includeLedger: true,
      ),
      '我的账本',
    );
  });
}
