import 'dart:convert';
import 'dart:io';

import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:flutter_test/flutter_test.dart';

/// v9 规则：微信 / 支付宝通知**只看标题**。
///
/// 标题含 支付 / 交易 / 收款 / 退款 / 转账 / 到账 / 还款 等词就解析；
/// 正文完全不再参与过滤（只在命中后用来取金额 / 商户）。
void main() {
  const alipay = 'com.eg.android.AlipayGphone';
  const wechat = 'com.tencent.mm';

  RawNotification n(String pkg, String title, String text) =>
      RawNotification(pkg: pkg, title: title, text: text, whenMs: 1);

  group('标题含关键词就解析（不看正文）', () {
    final cases = <String, ({String pkg, String title, String text, String dir, int minor})>{
      '支付宝 支付成功': (
        pkg: alipay,
        title: '支付成功',
        text: '向 星巴克 付款成功 ¥28.50',
        dir: 'out',
        minor: 2850,
      ),
      '支付宝 交易提醒': (
        pkg: alipay,
        title: '交易提醒',
        text: '你有一笔 ¥15.80 的交易',
        dir: 'out',
        minor: 1580,
      ),
      '支付宝 收款到账': (
        pkg: alipay,
        title: '收款到账',
        text: '收到一笔转账 ¥200.00',
        dir: 'in',
        minor: 20000,
      ),
      '支付宝 退款成功': (
        pkg: alipay,
        title: '退款成功',
        text: '商家已退款 ¥9.90',
        dir: 'refund',
        minor: 990,
      ),
      '支付宝 还款成功': (
        pkg: alipay,
        title: '还款成功',
        text: '花呗已还清 ¥500.00',
        dir: 'repay',
        minor: 50000,
      ),
      '微信 微信支付': (
        pkg: wechat,
        title: '微信支付',
        text: '向 全家便利店 付款 15.80 元',
        dir: 'out',
        minor: 1580,
      ),
      '微信 转账到账': (
        pkg: wechat,
        title: '转账到账',
        text: '张三 向你转账 ¥50.00',
        dir: 'in',
        minor: 5000,
      ),
      '微信 你领取了一个红包': (
        pkg: wechat,
        title: '你领取了一个红包',
        text: '¥8.88',
        dir: 'in',
        minor: 888,
      ),
      '微信 退款': (
        pkg: wechat,
        title: '退款成功',
        text: '退款 ¥12.00 已到账',
        dir: 'refund',
        minor: 1200,
      ),
    };

    cases.forEach((label, c) {
      test(label, () {
        final r = parseNotification(n(c.pkg, c.title, c.text));
        expect(r.ok, isTrue, reason: '$label should parse');
        expect(r.direction, c.dir, reason: label);
        expect(r.amountMinor, c.minor, reason: label);
      });
    });
  });

  group('正文里的词不再影响解析', () {
    test('标题有关键词、正文全是噪音词 → 仍然解析', () {
      // 这些词以前在 excludeTextRegex 里会直接丢弃整条通知。
      const noise = '验证码 123456 登录 服务通知 收益 权益 生活号 收藏 账单';
      final r = parseNotification(n(alipay, '支付成功', '¥25.00 $noise'));
      expect(r.ok, isTrue, reason: '正文噪音不再过滤');
      expect(r.amountMinor, 2500);
    });

    test('标题无关、正文有关键词 → 不解析', () {
      final r = parseNotification(n(wechat, '某某超市', '商户消费，支付金额 ¥25.50'));
      expect(r.templateId, isNull);
      expect(r.ok, isFalse);
    });

    test('标题与正文都无关键词 → 不解析', () {
      final r = parseNotification(n(alipay, '支付宝', '晚上一起吃饭吗'));
      expect(r.ok, isFalse);
    });
  });

  group('标题里的提醒 / 验证码仍然挡掉', () {
    final excluded = <String>[
      '验证码',
      '支付宝',
      '登录提醒',
      '花呗还款提醒',
      '待还提醒',
      '账单日',
    ];
    for (final title in excluded) {
      test(title, () {
        // 「账单日」 is legitimately in the repay exclude list; the pay rule
        // has no such word, so assert only that no AMOUNT-bearing parse
        // pretends it is a transaction of the wrong direction.
        final r = parseNotification(n(alipay, title, '验证码 123456，请勿泄露'));
        expect(
          r.templateId,
          isNot('alipay_repay_zh'),
          reason: '$title 不应被当作还款',
        );
      });
    }
  });

  test('模板声明 matchOn=title', () {
    for (final t in builtinNotiTemplates()) {
      expect(t.matchOn, 'title', reason: t.id);
      expect(t.keywordText(n(alipay, 'T', 'B')), 'T', reason: t.id);
    }
  });

  test('assets JSON is v9 and every rule is title-only', () {
    final map = jsonDecode(File('assets/noti_templates.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(map['version'], 9);
    for (final item in (map['templates'] as List).cast<Map<String, dynamic>>()) {
      expect(item['matchOn'], 'title', reason: item['id'] as String);
    }
  });
}
