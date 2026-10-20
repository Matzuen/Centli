import 'package:centli/platform/notifications/notification_llm_parse.dart';
import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:centli/platform/notifications/recognition_rule_distill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exclude distill naming', () {
    test('软件名-排除-场景 + stable id', () {
      expect(
        distilledExcludeRuleDisplayName('com.tencent.mm', '验证码'),
        '微信-排除-验证码',
      );
      expect(
        distilledExcludeRuleDisplayName('com.eg.android.AlipayGphone', ''),
        '支付宝-排除',
      );
      expect(
        distilledExcludeRuleId('com.tencent.mm', '验证码'),
        distilledExcludeRuleId('com.tencent.mm', '验证码'),
      );
      expect(
        distilledExcludeRuleId('com.tencent.mm', '验证码'),
        isNot(distilledExcludeRuleId('com.tencent.mm', '登录')),
      );
      expect(
        isDistillExcludeRuleId(distilledExcludeRuleId('com.tencent.mm', '验证码')),
        isTrue,
      );
      expect(
        isDistillExcludeRuleId(distilledRuleId('com.tencent.mm', 'out', '支付成功')),
        isFalse,
      );
    });

    test('fuse same exclude mustHint → one pattern matches both scenes', () {
      final afterA = fuseMustPattern(
        mustHint: '验证码',
        existingPattern: null,
        sceneFragments: const [],
      );
      final fused = fuseMustPattern(
        mustHint: '验证码',
        existingPattern: afterA,
        sceneFragments: const ['登录验证'],
      );
      final re = RegExp(fused);
      expect(re.hasMatch('验证码'), isTrue);
      expect(re.hasMatch('登录验证'), isTrue);
    });

    test('matchDistillExcludeRule hits drop template', () {
      final t = NotiTemplate(
        id: distilledExcludeRuleId('com.tencent.mm', '验证码'),
        name: distilledExcludeRuleDisplayName('com.tencent.mm', '验证码'),
        packages: const ['com.tencent.mm'],
        mustContainRegex: escapeForNotiRegex('验证码'),
        amountRegex: kAmountRegex,
        matchOn: 'title',
      );
      final hit = matchDistillExcludeRule(
        const RawNotification(
          pkg: 'com.tencent.mm',
          title: '登录验证码',
          text: '123456',
          whenMs: 0,
        ),
        [t],
      );
      expect(hit?.id, t.id);

      final miss = matchDistillExcludeRule(
        const RawNotification(
          pkg: 'com.tencent.mm',
          title: '支付成功',
          text: '¥12',
          whenMs: 0,
        ),
        [t],
      );
      expect(miss, isNull);
    });

    test('parseNotification skips distill_excl_ templates', () {
      final excl = NotiTemplate(
        id: distilledExcludeRuleId('com.tencent.mm', '验证码'),
        name: '微信-排除-验证码',
        packages: const ['com.tencent.mm'],
        mustContainRegex: escapeForNotiRegex('验证码'),
        amountRegex: kAmountRegex,
        matchOn: 'title',
      );
      final capture = NotiTemplate(
        id: 'wechat_pay_success_zh',
        name: '微信支付成功',
        packages: const ['com.tencent.mm'],
        mustContainRegex: '支付成功',
        amountRegex: kAmountRegex,
        matchOn: 'title',
      );
      final parsed = parseNotification(
        const RawNotification(
          pkg: 'com.tencent.mm',
          title: '验证码',
          text: '¥99',
          whenMs: 0,
        ),
        [excl, capture],
      );
      // Exclude template must not be treated as a payment match.
      expect(parsed.templateId, isNull);
    });
  });

  group('fuse same 「支付成功」 into one named rule', () {
    test('two titles under one mustHint → one pattern matches both', () {
      // Scene A: title 支付成功
      final afterA = fuseMustPattern(
        mustHint: '支付成功',
        existingPattern: null,
        sceneFragments: const [],
      );
      expect(afterA, escapeForNotiRegex('支付成功'));

      // Scene B: title 交易提醒 (AI still said mustHint=支付成功)
      final fused = fuseMustPattern(
        mustHint: '支付成功',
        existingPattern: afterA,
        sceneFragments: const ['交易提醒'],
      );
      expect(fused, isNot(afterA));
      final re = RegExp(fused);
      expect(re.hasMatch('支付成功'), isTrue);
      expect(re.hasMatch('交易提醒'), isTrue);
      expect(
        distilledRuleDisplayName('com.tencent.mm', 'out', '支付成功'),
        '微信-支出-支付成功',
      );
      // Same bucket id — not a second rule name.
      expect(
        distilledRuleId('com.tencent.mm', 'out', '支付成功'),
        distilledRuleId('com.tencent.mm', 'out', '支付成功'),
      );
    });

    test('mustHint always kept as a branch', () {
      final fused = fuseMustPattern(
        mustHint: '支付成功',
        existingPattern: escapeForNotiRegex('交易提醒'),
        sceneFragments: const ['商户收款通知'],
      );
      final literals =
          splitMustAlternatives(fused).map(unescapeNotiRegexLiteral).toSet();
      expect(literals, contains('支付成功'));
      expect(literals, contains('交易提醒'));
      expect(literals, contains('商户收款通知'));
    });

    test('different mustHint → different rule ids', () {
      expect(
        distilledRuleId('com.tencent.mm', 'out', '支付成功'),
        isNot(distilledRuleId('com.tencent.mm', 'out', '付款成功')),
      );
    });
  });

  group('helpers', () {
    test('sceneFragmentsForFusion uses distinct title', () {
      final raw = RawNotification(
        pkg: 'com.tencent.mm',
        title: '交易提醒',
        text: '支付成功 ￥12',
        whenMs: 0,
      );
      expect(sceneFragmentsForFusion(raw, '支付成功'), ['交易提醒']);
    });

    test('escape round-trip', () {
      expect(unescapeNotiRegexLiteral(escapeForNotiRegex('a.b')), 'a.b');
    });
  });
}
