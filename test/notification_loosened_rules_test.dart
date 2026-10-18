import 'dart:convert';
import 'dart:io';

import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:flutter_test/flutter_test.dart';

/// v9 规则：微信 / 支付宝通知**只看标题**——标题含支付 / 交易 / 收款 / 退款 /
/// 转账 / 到账 / 还款等词就解析，正文不参与过滤（正文只用来取金额）。
/// 因此这里所有用例都把关键词放在 `title`，并额外验证「关键词只在正文」
/// 时不会再被抓。
void main() {
  const alipay = 'com.eg.android.AlipayGphone';
  const wechat = 'com.tencent.mm';

  RawNotification raw(String pkg, String text, {String title = ''}) =>
      RawNotification(pkg: pkg, title: title, text: text, whenMs: 1);

  group('标题含关键词就抓 (v9)', () {
    final cases = <String, (String, String, String, int)>{
      // text -> (pkg, expected template, expected direction, minor)
      '花呗付款（无“成功”）': ('你已于 10-17 12:03 通过花呗付款 25.00 元', alipay, 'out', 2500),
      '扣款（无“成功”）': ('你有一笔 ¥12.50 的扣款，来自 星巴克', alipay, 'out', 1250),
      '纯支出': ('您有一笔 30.00 元的支出，余额 88.00 元', alipay, 'out', 3000),
      '缴费': ('电费缴费成功 ¥120.30', alipay, 'out', 12030),
      '充值': ('话费充值成功，实际支付 ¥50.00', alipay, 'out', 5000),
      '无金额符号、只有元': ('交易提醒：你消费了 18.80 元', alipay, 'out', 1880),
      '收款（无“到账”）': ('收到一笔转账 ¥200.00', alipay, 'in', 20000),
      '已退款': ('商家已退款，¥9.90 将退回余额', alipay, 'refund', 990),
      '还款代扣': ('借呗还款 ¥500.00', alipay, 'repay', 50000),
      '只含“微信支付”': ('微信支付凭证：商户 全家便利店 金额 15.80 元', wechat, 'out', 1580),
      '对方已收款回执': ('微信支付转账成功，对方已收款 ¥50.00', wechat, 'in', 5000),
      '领取了自己的红包回执': ('你领取了你的红包 ¥8.88', wechat, 'in', 888),
    };

    cases.forEach((label, c) {
      test(label, () {
        // 标题 = 关键词短语（真实通知的标题就是这个），正文是完整句子。
        final r = parseNotification(raw(c.$2, c.$1, title: c.$1));
        expect(r.templateId, isNotNull, reason: 'should be captured');
        expect(r.ok, isTrue, reason: 'amount should parse');
        expect(r.direction, c.$3);
        expect(r.amountMinor, c.$4);
      });
    });
  });

  group('标题即噪音时仍排除 (v9)', () {
    final excluded = <String, String>{
      '验证码': '验证码 123456，5 分钟内有效',
      '设备登录': '您在 Android 设备登录了支付宝',
      '待还提醒': '待还金额 ¥520.00，请于 10 月 20 日前还款',
      '应还提醒': '本月应还 99.00 元',
      '账单日说明': '你的账单日为每月 5 日，还款日为 20 日',
      '普通聊天': '我在忙，晚点回你',
      '拍一拍': '张三 拍了拍我',
    };

    excluded.forEach((label, text) {
      test(label, () {
        // Noise words must be in the TITLE to be excluded (title-only rules).
        final alipayR = parseNotification(raw(text, text, title: text));
        final wechatR = parseNotification(raw(wechat, text, title: text));
        expect(alipayR.templateId, isNull, reason: 'alipay: $text');
        expect(wechatR.templateId, isNull, reason: 'wechat: $text');
      });
    });
  });

  test('assets/noti_templates.json mirrors the builtin rules (v9)', () async {
    final rawJson = await File('assets/noti_templates.json').readAsString();
    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    expect(map['version'], 9);
    final list = (map['templates'] as List).cast<Map<String, dynamic>>();
    final assets = {
      for (final item in list) item['id'] as String: NotiTemplate.fromJson(item),
    };
    final builtins = {for (final t in builtinNotiTemplates()) t.id: t};

    expect(assets.keys.toSet(), builtins.keys.toSet());
    for (final entry in builtins.entries) {
      final a = assets[entry.key]!;
      final b = entry.value;
      expect(a.mustContainRegex, b.mustContainRegex, reason: entry.key);
      expect(a.excludeTextRegex, b.excludeTextRegex, reason: entry.key);
      expect(a.direction, b.direction, reason: entry.key);
      expect(a.matchOn, b.matchOn, reason: entry.key);
      expect(b.matchOn, 'title', reason: '${entry.key} must be title-only');
      expect(a.defaultAccountHint, b.defaultAccountHint, reason: entry.key);
      expect(a.packages, b.packages, reason: entry.key);
      // The amount pattern must accept a bare number (no ¥ / $ prefix).
      final re = RegExp(a.amountRegex);
      expect(re.firstMatch('金额 15.80 元')?.group(1), '15.80', reason: entry.key);
      expect(re.firstMatch('付款成功 12.50')?.group(1), '12.50', reason: entry.key);
    }
    // Order matters: repay must be tried before pay (「还款…扣款」).
    final ids = [for (final item in list) item['id'] as String];
    expect(
      ids.indexOf('alipay_repay_zh'),
      lessThan(ids.indexOf('alipay_pay_success_zh')),
    );
  });
}
