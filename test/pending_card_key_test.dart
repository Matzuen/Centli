import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PendingPage itemBuilder passes ValueKey(capture.id) to _PendingCard', () {
    final src = File('lib/features/pending/pending_page.dart').readAsStringSync();
    expect(
      RegExp(
        r'_PendingCard\(\s*key:\s*ValueKey\(capture\.id\)',
        multiLine: true,
      ).hasMatch(src),
      isTrue,
      reason:
          'Missing ValueKey(capture.id) causes State reuse after delete/confirm '
          '(controllers keep previous card data)',
    );
    expect(
      RegExp(r'_PendingCard\(\{[^}]*super\.key', multiLine: true, dotAll: true)
          .hasMatch(src),
      isTrue,
      reason: '_PendingCard must accept super.key so ValueKey can be applied',
    );
  });
}
