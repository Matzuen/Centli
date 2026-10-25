import 'package:flutter_test/flutter_test.dart';
import 'package:centli/core/utils/account_label.dart';

void main() {
  test('ledger + account → 账本-账户', () {
    expect(
      formatLedgerAccountLabel(
        accountName: '农业银行',
        ledgerName: '我的账本',
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
      formatLedgerAccountLabel(accountName: '现金', ledgerName: '  '),
      '现金',
    );
  });

  test('trims whitespace', () {
    expect(
      formatLedgerAccountLabel(
        accountName: ' 现金 ',
        ledgerName: ' 小金库 ',
      ),
      '小金库-现金',
    );
  });
}
