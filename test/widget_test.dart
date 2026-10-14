import 'package:centli/core/utils/date_range.dart';
import 'package:centli/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('CNY minor round-trip', () {
      expect(toMinor('CNY', 12.34), 1234);
      expect(fromMinor('CNY', 1234), 12.34);
      expect(formatMinor('CNY', 1234), contains('12.34'));
    });

    test('JPY has 0 decimals', () {
      expect(toMinor('JPY', 100), 100);
      expect(fromMinor('JPY', 100), 100);
      expect(formatMinor('JPY', 100), contains('100'));
      expect(formatMinor('JPY', 100), isNot(contains('.')));
    });

    test('hide amount', () {
      expect(formatMinor('CNY', 100, hide: true), '****');
    });
  });

  group('DateRangeWindow', () {
    test('last 30 days covers through today', () {
      final now = DateTime(2026, 10, 13, 15, 30);
      final w = DateRangeWindow.lastDays(days: 30, nowLocal: now);
      expect(w.endLocal, DateTime(2026, 10, 14));
      expect(w.startLocal, DateTime(2026, 9, 14));
      expect(w.isLatest, isTrue);
      expect(w.label, '\u8fd1\u0033\u0030\u5929');
    });

    test('prev shifts window back', () {
      final now = DateTime(2026, 10, 13);
      final w = DateRangeWindow.lastDays(days: 30, nowLocal: now).prev();
      expect(w.endLocal, DateTime(2026, 9, 14));
      expect(w.isLatest, isFalse);
    });
  });
}