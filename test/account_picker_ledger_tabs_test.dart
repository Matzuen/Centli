import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('account picker ledger tabs (source contract)', () {
    late String pickerSrc;
    late String bookkeepingSrc;
    late String homeSrc;

    setUpAll(() {
      pickerSrc =
          File('lib/features/ledger/account_picker_sheet.dart').readAsStringSync();
      bookkeepingSrc =
          File('lib/features/ledger/bookkeeping_sheet.dart').readAsStringSync();
      homeSrc = File('lib/features/home/home_page.dart').readAsStringSync();
    });

    test('picker exposes preferredLedgerId and ledger tab key', () {
      expect(pickerSrc.contains('preferredLedgerId'), isTrue);
      expect(
        pickerSrc.contains("Key('account_picker_ledger_tabs')"),
        isTrue,
      );
      expect(pickerSrc.contains('_showLedgerTabs'), isTrue);
      expect(pickerSrc.contains('_ledgerAccounts'), isTrue);
      expect(pickerSrc.contains('ChoiceChip'), isTrue);
    });

    test('transfer pickers pass preferredLedgerId', () {
      expect(bookkeepingSrc.contains('preferredLedgerId: _ledgerId'), isTrue);
      expect(bookkeepingSrc.contains('选择转入资产账户'), isTrue);
      expect(bookkeepingSrc.contains('选择转出资产账户'), isTrue);
    });

    test('home multi-select: long-press entry, no checklist, fixed bar', () {
      expect(homeSrc.contains('_enterTxnSelect'), isTrue);
      expect(homeSrc.contains('_batchSoftDeleteTxns'), isTrue);
      expect(homeSrc.contains('已选 '), isTrue);
      expect(homeSrc.contains('centliDangerFilledStyle'), isTrue);
      expect(homeSrc.contains('Icons.checklist'), isFalse);
      expect(homeSrc.contains('checklist'), isFalse);
    });
  });
}
