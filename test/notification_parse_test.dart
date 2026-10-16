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

    test('alipay jiaoyi reminder with amount matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '交易提醒',
        text: '向 全家便利店 付款 ¥15.80',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 1580);
      expect(r.merchant, contains('全家'));
    });

    test('alipay jiaoyi notice with amount matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '交易通知',
        text: '交易成功，支出 ¥42.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 4200);
    });

    test('alipay non-pay message without keywords is dropped', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付宝',
        text: '你有一条新的生活号消息',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
      expect(r.ok, isFalse);
    });

    test('alipay 扣款 wording matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '扣款提醒',
        text: '已扣款 ¥36.00，商户 美团外卖',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 3600);
    });

    test('alipay 支出 yen matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付宝',
        text: '支出 ¥9.90',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 990);
    });

    test('alipay bare 付款 with amount matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '付款',
        text: '向 瑞幸咖啡 付款 ¥18.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 1800);
    });

    test('alipay 生活号 still excluded even with amount', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '生活号',
        text: '生活号：本周优惠，支付 ¥1.00 即可领取',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
    });

    test('wechat 商户消费 matches', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '某某超市',
        text: '商户消费，支付金额 ¥25.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'wechat_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 2550);
    });

    test('wechat 付款成功 matches', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '肯德基-微信支付',
        text: '付款成功 ¥32.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'wechat_pay_success_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 3200);
    });

    test('wechat chat with 付款 word still excluded', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '李四',
        text: '发来一条消息：你付款了吗',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
    });
  });


group('manual capture parser (share/OCR/clipboard)', () {
  test('parses wechat transfer send-out', () {
    final r = parseManualCaptureText('向张三转账成功 ¥20.00');
    expect(r.templateId, isNotNull);
    expect(r.ok, isTrue);
    expect(r.amountMinor, 2000);
    expect(r.merchant, contains('张三'));
  });

  test('parses red packet text', () {
    final r = parseManualCaptureText('微信红包 ¥8.88');
    expect(r.templateId, 'manual_transfer_zh');
    expect(r.ok, isTrue);
    expect(r.amountMinor, 888);
  });

  test('rejects chat-like text', () {
    final r = parseManualCaptureText('张三发来一条消息：今晚吃饭吗');
    expect(r.templateId, isNull);
    expect(r.ok, isFalse);
  });

  test('accepts amount with money mark without keyword', () {
    final r = parseManualCaptureText('星巴克 ¥28.50');
    expect(r.templateId, isNotNull);
    expect(r.ok, isTrue);
  });

  test('transfer with merchant line', () {
    final r = parseManualCaptureText('转账成功\n向 李四 转账\n¥15.00');
    expect(r.ok, isTrue);
    expect(r.amountMinor, 1500);
  });
});

}
