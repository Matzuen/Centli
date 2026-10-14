import 'package:centli/core/utils/fx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FxBook', () {
    test('identity rate and convert', () {
      final book = FxBook(const []);
      expect(book.rate(fromCcy: 'CNY', toCcy: 'CNY', onDay: '2026-10-14'), 1.0);
      expect(
        book.convertMinor(
          fromCcy: 'CNY',
          toCcy: 'CNY',
          amountMinor: 12345,
          onDay: '2026-10-14',
        ),
        12345,
      );
    });

    test('exact forward quote', () {
      final book = FxBook(const [
        FxQuote(day: '2026-10-10', fromCcy: 'USD', toCcy: 'CNY', rate: 7.2),
      ]);
      expect(
        book.rate(fromCcy: 'USD', toCcy: 'CNY', onDay: '2026-10-14'),
        7.2,
      );
      // $10.00 -> ¥72.00
      expect(
        book.convertMinor(
          fromCcy: 'USD',
          toCcy: 'CNY',
          amountMinor: 1000,
          onDay: '2026-10-14',
        ),
        7200,
      );
    });

    test('inverse quote', () {
      final book = FxBook(const [
        FxQuote(day: '2026-10-10', fromCcy: 'CNY', toCcy: 'USD', rate: 0.14),
      ]);
      final r = book.rate(fromCcy: 'USD', toCcy: 'CNY', onDay: '2026-10-14');
      expect(r, closeTo(1 / 0.14, 1e-9));
    });

    test('nearest prior day, not future', () {
      final book = FxBook(const [
        FxQuote(day: '2026-10-01', fromCcy: 'USD', toCcy: 'CNY', rate: 7.0),
        FxQuote(day: '2026-10-20', fromCcy: 'USD', toCcy: 'CNY', rate: 8.0),
      ]);
      expect(
        book.rate(fromCcy: 'USD', toCcy: 'CNY', onDay: '2026-10-14'),
        7.0,
      );
      expect(
        book.rate(fromCcy: 'USD', toCcy: 'CNY', onDay: '2026-10-20'),
        8.0,
      );
    });

    test('missing rate returns null', () {
      final book = FxBook(const []);
      expect(
        book.convertMinor(
          fromCcy: 'USD',
          toCcy: 'CNY',
          amountMinor: 100,
          onDay: '2026-10-14',
        ),
        isNull,
      );
    });

    test('JPY zero-decimal conversion', () {
      final book = FxBook(const [
        FxQuote(day: '2026-10-01', fromCcy: 'JPY', toCcy: 'CNY', rate: 0.05),
      ]);
      // 100 JPY -> 5.00 CNY = 500 minor
      expect(
        book.convertMinor(
          fromCcy: 'JPY',
          toCcy: 'CNY',
          amountMinor: 100,
          onDay: '2026-10-14',
        ),
        500,
      );
    });

    test('dayFromHappenAtMs formats local day', () {
      final utc = DateTime.utc(2026, 10, 14, 4, 0);
      final day = FxBook.dayFromHappenAtMs(utc.millisecondsSinceEpoch);
      expect(day, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });
}
