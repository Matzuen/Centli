import 'package:centli/platform/notifications/notification_llm_parse.dart';
import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:centli/platform/notifications/recognition_rule_distill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exclude distill naming', () {
    test('软件名-排除-场景 + stable id', () {
      expect(
        distilledExcludeRuleDisplayName('com.tencent.mm'),
        '微信-排除',
      );
      expect(
        distilledExcludeRuleDisplayName('com.eg.android.AlipayGphone'),
        '支付宝-排除',
      );
      // 每个应用只有一条排除规则（场景并进去，才能真正收敛）
      expect(
        distilledExcludeRuleId('com.tencent.mm'),
        distilledExcludeRuleId('com.tencent.mm'),
      );
      expect(
        distilledExcludeRuleId('com.tencent.mm'),
        isNot(distilledExcludeRuleId('com.eg.android.AlipayGphone')),
      );
      expect(
        isDistillExcludeRuleId(distilledExcludeRuleId('com.tencent.mm')),
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
        id: distilledExcludeRuleId('com.tencent.mm'),
        name: distilledExcludeRuleDisplayName('com.tencent.mm'),
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
        id: distilledExcludeRuleId('com.tencent.mm'),
        name: '微信-排除',
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

  group('排除规则：循环收敛与安全边界', () {
    test('只有具体、且不含支付词的片段才可作为排除依据', () {
      // 太短 / 含支付词 / 含金额 → 一律拒绝（否则会吞掉真实账单）
      for (final bad in [
        '微信', '通知', '账单', '支付', '收款', '支付通知', '微信支付成功',
        '还款提醒', '转账给张三', '收入 12.00', '消费\u00a512.00',
      ]) {
        expect(
          isExcludeSafeFragment(bad),
          isFalse,
          reason: '「$bad」不能作为排除片段',
        );
      }
      for (final ok in ['张三', '家人群', '登录验证', '朋友圈点赞', '群聊消息（营销）']) {
        expect(isExcludeSafeFragment(ok), isTrue, reason: '「$ok」应可用于排除');
      }
    });

    test('同一场景的多个标题融进一条规则（越用越省）', () {
      var pattern = fuseMustPattern(
        mustHint: '张三',
        existingPattern: null,
        sceneFragments: const [],
        maxAlts: 64,
      );
      for (final name in ['李四', '王五', '赵六']) {
        pattern = fuseMustPattern(
          mustHint: '张三',
          existingPattern: pattern,
          sceneFragments: [name],
          maxAlts: 64,
        );
      }
      final re = RegExp(pattern);
      for (final name in ['张三', '李四', '王五', '赵六']) {
        expect(re.hasMatch(name), isTrue, reason: '$name 应被同一条规则命中');
      }
      // 支付类标题不会被这条规则命中
      expect(re.hasMatch('支付成功'), isFalse);
    });

    test('排除分支上限比捕获分支更宽', () {
      // 8 个以上的分支只有在 maxAlts 放宽后才保留
      var narrow = fuseMustPattern(
        mustHint: '场景种子',
        existingPattern: null,
        sceneFragments: const [],
      );
      var wide = narrow;
      for (var i = 0; i < 12; i++) {
        narrow = fuseMustPattern(
          mustHint: '场景种子',
          existingPattern: narrow,
          sceneFragments: ['场景$i'],
        );
        wide = fuseMustPattern(
          mustHint: '场景种子',
          existingPattern: wide,
          sceneFragments: ['场景$i'],
          maxAlts: 64,
        );
      }
      expect(
        splitMustAlternatives(narrow).length,
        lessThanOrEqualTo(8),
        reason: '捕获规则仍限制在 8 个分支',
      );
      expect(
        splitMustAlternatives(wide).length,
        greaterThan(8),
        reason: '排除规则应能容纳更多场景（64 上限）',
      );
    });
  });

  group('限频', () {
    test('每分钟调用上限', () {
      resetLlmParseRateLimit();
      final t0 = DateTime(2026, 10, 20, 12, 0, 0);
      for (var i = 0; i < kLlmParsePerMinuteCap; i++) {
        expect(
          noteLlmParseCall(now: t0.add(Duration(milliseconds: i * 10))),
          isTrue,
          reason: 'call $i should pass',
        );
      }
      expect(noteLlmParseCall(now: t0.add(const Duration(seconds: 59))), isFalse);
      expect(
        noteLlmParseCall(now: t0.add(const Duration(seconds: 61))),
        isTrue,
      );
      resetLlmParseRateLimit();
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
