import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse foreign currency symbols', () {
    test('parses dollar amount as USD', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '付款成功 \$15.99',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.ok, isTrue);
      expect(r.currency, 'USD');
      expect(r.amountMinor, 1599);
    });

    test('parses euro amount as EUR', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '付款成功 €9.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.ok, isTrue);
      expect(r.currency, 'EUR');
      expect(r.amountMinor, 950);
    });

    test('still parses yen as CNY default', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '向 星巴克 付款成功 ¥28.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.ok, isTrue);
      expect(r.currency, 'CNY');
      expect(r.amountMinor, 2850);
    });

    test('detectCurrencyNearMatch helpers', () {
      final re = RegExp(kAmountRegex);
      final body = 'paid \$12.00 today';
      final m = re.firstMatch(body)!;
      expect(detectCurrencyNearMatch(body, m, 'CNY'), 'USD');

      final body2 = 'paid €3.00';
      final m2 = re.firstMatch(body2)!;
      expect(detectCurrencyNearMatch(body2, m2, 'CNY'), 'EUR');
    });
  });
}
