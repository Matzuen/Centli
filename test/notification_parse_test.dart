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
      expect(r.templateId, 'wechat_expense_zh');
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
      expect(r.templateId, 'alipay_expense_zh');
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
      expect(r.templateId, 'alipay_expense_zh');
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
      expect(r.templateId, 'alipay_expense_zh');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 4200);
    });

    test('alipay 标题含「支付宝」→ 会被抓进待确认（v9 只看标题）', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付宝',
        text: '你有一条新的生活号消息',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      // 「支付宝」本身含「支付」；宁可多抓进待确认，也不再靠正文过滤。
      expect(r.templateId, 'alipay_expense_zh');
      expect(r.ok, isFalse, reason: '无金额 → 解析失败但保留待确认');
    });

    test('alipay 扣款 wording matches', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '扣款提醒',
        text: '已扣款 ¥36.00，商户 美团外卖',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_expense_zh');
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
      expect(r.templateId, 'alipay_expense_zh');
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
      expect(r.templateId, 'alipay_expense_zh');
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

    test('wechat 关键词只在正文 → 不解析（v9 只看标题）', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '某某超市',
        text: '商户消费，支付金额 ¥25.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
      expect(r.ok, isFalse);
    });

    test('wechat 付款成功 matches', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '肯德基-微信支付',
        text: '付款成功 ¥32.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'wechat_expense_zh');
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


  group('ParseResult.direction', () {
    test('expense pay success carries direction out', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '向 星巴克 付款成功 ¥28.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNotNull);
      expect(r.direction, 'out');
    });

    test('unmatched returns direction out default', () {
      final raw = RawNotification(
        pkg: 'com.unknown.app',
        title: 'hi',
        text: 'hello',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, isNull);
      expect(r.direction, 'out');
    });

    test('template direction in is forwarded', () {
      final t = NotiTemplate(
        id: 'income_test',
        packages: const ['com.eg.android.AlipayGphone'],
        mustContainRegex: '收款到账',
        amountRegex: r'¥\s*([0-9]+(?:\.[0-9]{1,2})?)',
        direction: 'in',
      );
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '',
        text: '收款到账 ¥200.00',
        whenMs: 1,
      );
      final r = parseNotification(raw, [t]);
      expect(r.templateId, 'income_test');
      expect(r.direction, 'in');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 20000);
    });
  });


  group('T1-3 income and refund templates', () {
    test('alipay 收款到账 is direction in', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '收款到账',
        text: '收款到账 ¥200',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_income_zh');
      expect(r.direction, 'in');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 20000);
    });

    test('alipay 退款成功 is direction in (tag/note, not type refund)', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '退款成功',
        text: '退款成功 ¥28.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_income_zh');
      expect(r.direction, 'in');
      expect(isRefundSignal(templateId: r.templateId, title: raw.title), isTrue);
      expect(r.ok, isTrue);
      expect(r.amountMinor, 2850);
    });

    test('alipay pay success still out (regression)', () {
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '向 星巴克 付款成功 ¥28.50',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'alipay_expense_zh');
      expect(r.direction, 'out');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 2850);
    });

    test('wechat receive 收款到账 is in', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信收款',
        text: '收款到账¥88.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      expect(r.templateId, 'wechat_income_zh');
      expect(r.direction, 'in');
      expect(r.ok, isTrue);
    });

    test('wechat peer-claimed red packet still not income', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '微信',
        text: '张三领取了你的红包 ¥5.00',
        whenMs: 1,
      );
      final r = parseNotification(raw);
      // Prefer miss over wrong direction.
      expect(r.templateId, isNull);
    });
  });

  group('微信红包 income phrasing (T0)', () {
    // v9：关键词只看标题。真实微信通知的标题就是「微信支付」「收款到账」
  // 「你领取了一个红包」这类，所以 helper 默认把正文当作标题。
  RawNotification wx(String text, {String? title}) => RawNotification(
        pkg: 'com.tencent.mm',
        title: title ?? text,
        text: text,
        whenMs: 1,
      );

    test('你领取了张三的红包 is in', () {
      final r = parseNotification(wx('你领取了张三的红包 ¥8.88'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
      expect(r.templateId, 'wechat_income_zh');
      expect(r.amountMinor, 888);
    });

    test('你领取了一个红包 is in', () {
      final r = parseNotification(wx('你领取了一个红包 ¥8.88'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
      expect(r.amountMinor, 888);
    });

    // Loosened rules (v8): receipts for money *sent away*（对方领取了你的红包）
    // are captured too — a duplicate in 待确认 beats a missed real income.
    test('你领取了你的红包 is in (loosened v8)', () {
      final r = parseNotification(wx('你领取了你的红包 ¥8.88'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
      expect(r.templateId, 'wechat_income_zh');
      expect(r.amountMinor, 888);
    });

    test('对方已收款的转账回执 is captured as income (v8)', () {
      final r = parseNotification(wx('微信支付转账成功，对方已收款 ¥50.00'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
      expect(r.templateId, 'wechat_income_zh');
      expect(r.amountMinor, 5000);
    });

    test('你发起了…转账：标题含「转账」→ 抓（v9 只看标题）', () {
      final r = parseNotification(wx('你发起了 ¥30.00 的转账'));
      // 标题里出现「转账」→ 进待确认；「你发起」是钱发出去，按支出。
      expect(r.ok, isTrue);
      expect(r.direction, 'out');
    });

    test('你收到一个红包 is in (T0-2)', () {
      final r = parseNotification(wx('你收到一个红包 ¥6.66'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
      expect(r.templateId, 'wechat_income_zh');
      expect(r.amountMinor, 666);
    });

    test('你收到红包 adjacent still in', () {
      final r = parseNotification(wx('你收到红包 ¥1.23'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
    });

    test('红包到账 is in', () {
      final r = parseNotification(wx('红包到账 ¥10.00'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
    });

    test('你收到了红包 is in', () {
      final r = parseNotification(wx('你收到了红包 ¥2.00'));
      expect(r.ok, isTrue);
      expect(r.direction, 'in');
    });

    test('发来一个红包 not captured (anti-regression)', () {
      final r = parseNotification(wx('张三发来一个红包 ¥1.00'));
      expect(r.templateId, isNull);
      expect(r.ok, isFalse);
    });

    test('朋友圈 noise not captured', () {
      final r = parseNotification(wx('朋友圈 ¥9.99 红包'));
      expect(r.templateId, isNull);
    });

    test('拍了拍 noise not captured', () {
      final r = parseNotification(wx('张三拍了拍你的头 ¥1.00 红包'));
      expect(r.templateId, isNull);
    });
  });

  group('T0B repay + yuan amount', () {
    test('huabei repay notice → out 12.54 (tag/note, not type repay)', () {
      final r = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '10月花呗账单还清啦',
          text: '10月花呗账单还清啦，从银行卡还款12.54元，本月账单已还清',
          whenMs: DateTime(2026, 10, 17, 11, 43).millisecondsSinceEpoch,
        ),
      );
      expect(r.ok, isTrue);
      expect(r.direction, 'out');
      expect(
        isRepaySignal(templateId: r.templateId, title: '10月花呗账单还清啦'),
        isTrue,
      );
      expect(r.amountMinor, 1254);
      expect(r.templateId, 'alipay_expense_zh');
    });

    test('待还 reminder is excluded', () {
      final r = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '花呗还款提醒',
          text: '本月待还 1234.56 元，请于 10 月 8 日前还款',
          whenMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        ),
      );
      expect(r.templateId, isNull);
    });

    test('应还 reminder is excluded', () {
      final r = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '账单提醒',
          text: '本月应还 99.00 元',
          whenMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        ),
      );
      expect(r.templateId, isNull);
    });

    test('yuan suffix extracts 12.54 and 1,234.56', () {
      final a = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '还清',
          text: '还款12.54元',
          whenMs: 1,
        ),
      );
      expect(a.ok, isTrue);
      expect(a.amountMinor, 1254);

      final b = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '还清',
          text: '还款1,234.56元已还清',
          whenMs: 2,
        ),
      );
      expect(b.ok, isTrue);
      expect(b.amountMinor, 123456);
    });

    test('10月 / ISO date not mistaken for amount', () {
      final a = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '10月花呗账单还清啦',
          text: '10月花呗账单还清啦',
          whenMs: 3,
        ),
      );
      // May match repay template but must not invent amount 10.
      expect(a.amountMinor, isNull);

      final b = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '还清',
          text: '账单还清 2026-10-17 12:00',
          whenMs: 4,
        ),
      );
      expect(b.amountMinor, isNull);
    });

    // Loosened rules (v8): 红包 discounts are no longer excluded, so the
    // notice is captured and the first (paid) amount beats the discount.
    test('currency symbol wins over yuan fallback', () {
      final r = parseNotification(
        RawNotification(
          pkg: 'com.eg.android.AlipayGphone',
          title: '支付成功',
          text: '实付¥16.93，0.5元红包',
          whenMs: 5,
        ),
      );
      expect(r.ok, isTrue);
      expect(r.amountMinor, 1693);
      expect(r.direction, 'out');
    });

    test('normalizeDirection maps legacy repay/refund', () {
      expect(NotiTemplate.normalizeDirection('repay'), 'out');
      expect(NotiTemplate.normalizeDirection('refund'), 'in');
      expect(NotiTemplate.normalizeDirection('nope'), 'out');
    });
  });

}
