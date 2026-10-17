import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final actions = File('lib/features/capture/capture_intake_actions.dart')
      .readAsStringSync();
  final pending = File('lib/features/pending/pending_page.dart').readAsStringSync();
  final home = File('lib/features/home/home_page.dart').readAsStringSync();
  final quick =
      File('lib/features/ledger/quick_bookkeeping_sheet.dart').readAsStringSync();

  test('privacy consent dialog only in capture_intake_actions', () {
    expect(actions.contains('截图识别说明'), isTrue);
    expect(actions.contains('hasImageAiConsent'), isTrue);
    // Pending page must not own a second consent dialog.
    expect(pending.contains('截图识别说明'), isFalse);
    expect(home.contains('截图识别说明'), isFalse);
    expect(quick.contains('截图识别说明'), isFalse);
  });

  test('home and quick sheet wire shared screenshot entry', () {
    expect(home.contains('document_scanner_outlined'), isTrue);
    expect(home.contains('importCaptureFromScreenshot'), isTrue);
    expect(quick.contains('截图识别'), isTrue);
    expect(quick.contains('剪贴板'), isTrue);
    expect(quick.contains('importCaptureFromClipboard'), isTrue);
    expect(pending.contains('importCaptureFromScreenshot'), isTrue);
  });
}
