import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consecutive payment dedupe', () {
    test('same StatusBarNotification key + different body → distinct keys', () {
      final a = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信支付',
        text: '付款给商家A ¥12.00',
        whenMs: 1_700_000_000_000,
        key: '0|com.tencent.mm|1|null|10234',
      );
      final b = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信支付',
        text: '付款给商家B ¥28.50',
        whenMs: 1_700_000_030_000,
        key: '0|com.tencent.mm|1|null|10234', // reused key
      );
      final pa = ParseResult(
        ok: true,
        amountMinor: 1200,
        currency: 'CNY',
        direction: 'out',
      );
      final pb = ParseResult(
        ok: true,
        amountMinor: 2850,
        currency: 'CNY',
        direction: 'out',
      );
      expect(dedupeKey(a, pa), isNot(equals(dedupeKey(b, pb))));
    });

    test('same amount within 2 minutes + different body → distinct keys', () {
      final a = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '交易提醒',
        text: '你向甲付款28.00元',
        whenMs: 1_700_000_000_000,
      );
      final b = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '交易提醒',
        text: '你向乙付款28.00元',
        whenMs: 1_700_000_060_000,
      );
      final p = ParseResult(
        ok: true,
        amountMinor: 2800,
        currency: 'CNY',
        direction: 'out',
      );
      expect(dedupeKey(a, p), isNot(equals(dedupeKey(b, p))));
    });

    test('identical notice twice → same key (true duplicate)', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信支付',
        text: '付款成功 ¥9.90',
        whenMs: 1_700_000_000_000,
        key: 'same-key',
      );
      final p = ParseResult(
        ok: true,
        amountMinor: 990,
        currency: 'CNY',
        direction: 'out',
      );
      expect(dedupeKey(raw, p), equals(dedupeKey(raw, p)));
    });
  });
}
