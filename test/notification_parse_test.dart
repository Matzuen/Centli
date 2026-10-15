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
group('payment filter drops chat / non-pay', () {
    test('wechat chat message is not matched', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '张三',
        text: '发来一条消息：今晚吃饭吗',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
      expect(r.ok, isFalse);
    });

    test('wechat moments excluded', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信',
        text: '朋友圈：有人赞了你',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
    });

    test('wechat pay success still matches', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '星巴克-微信支付',
        text: '你已支付 ¥12.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'wechat_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 1200);
    });

    test('alipay otp with amount excluded', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '验证码',
        text: '登录验证码 123456，勿告诉他人 ¥0.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
    });

    test('alipay pay success without amount still matched (parse_ok false)', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '付款成功（无金额）',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isFalse);
    });
  });
}
