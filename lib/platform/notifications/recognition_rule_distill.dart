/// Distill AI notification parses into local user rules for kill-path reuse.
///
/// **Capture** grouping key = 包名 + 支/收 + AI mustHint（如「支付成功」）。
/// 同一组融成一条 `软件名-支出-支付成功`；mustContain 用 `|` OR 合并。
///
/// **Exclude**（AI isPayment=false）grouping key = 包名 + mustHint。
/// 融成一条 `软件名-排除-验证码`；命中后丢弃，不入账。
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'notification_llm_parse.dart';
import 'notification_parse.dart';
import 'noti_template_store.dart';

const int _kMaxMustAlts = 8;

/// Escape a literal for use inside a Dart [RegExp] pattern.
@visibleForTesting
String escapeForNotiRegex(String literal) {
  return literal.replaceAllMapped(
    RegExp(r'[.\\+*?\[\](){}^$|:]'),
    (m) => '\\${m[0]}',
  );
}

/// Best-effort unescape of a single alternative we previously escaped.
@visibleForTesting
String unescapeNotiRegexLiteral(String escaped) {
  return escaped
      .replaceAll(r'\.', '.')
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\[', '[')
      .replaceAll(r'\]', ']')
      .replaceAll(r'\+', '+')
      .replaceAll(r'\*', '*')
      .replaceAll(r'\?', '?')
      .replaceAll(r'\{', '{')
      .replaceAll(r'\}', '}')
      .replaceAll(r'\^', '^')
      .replaceAll(r'\$', r'$')
      .replaceAll(r'\|', '|')
      .replaceAll(r'\\', r'\');
}

/// Split a must pattern into top-level `|` alternatives.
@visibleForTesting
List<String> splitMustAlternatives(String? pattern) {
  final raw = pattern?.trim() ?? '';
  if (raw.isEmpty) return const [];
  final parts = <String>[];
  final buf = StringBuffer();
  var escaped = false;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (escaped) {
      buf.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\') {
      buf.write(ch);
      escaped = true;
      continue;
    }
    if (ch == '|') {
      final p = buf.toString().trim();
      if (p.isNotEmpty) parts.add(p);
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  final last = buf.toString().trim();
  if (last.isNotEmpty) parts.add(last);
  return parts;
}

/// Build / widen mustContain so every [incoming] literal can match.
///
/// Always keeps [mustHint] as a branch. Returns the pattern string.
@visibleForTesting
String fuseMustPattern({
  required String mustHint,
  required String? existingPattern,
  required Iterable<String> sceneFragments,
}) {
  final literals = <String>[];
  final seen = <String>{};

  void addLiteral(String? s) {
    final t = s?.trim() ?? '';
    if (t.isEmpty || t.length > 24) return;
    final key = normalizeDistillHint(t);
    if (key.isEmpty || seen.contains(key)) return;
    // Drop alts that are strict supersets of a shorter already-kept alt
    // only when equal — keep both 支付成功 and 交易提醒.
    seen.add(key);
    literals.add(t);
  }

  // Canonical hint first — this is the shared scene name.
  addLiteral(mustHint);
  for (final part in splitMustAlternatives(existingPattern)) {
    addLiteral(unescapeNotiRegexLiteral(part));
  }
  for (final s in sceneFragments) {
    addLiteral(s);
  }

  if (literals.isEmpty) return escapeForNotiRegex(mustHint);

  // Prefer shorter (broader) alts first; cap length.
  literals.sort((a, b) {
    final byLen = a.length.compareTo(b.length);
    return byLen != 0 ? byLen : a.compareTo(b);
  });
  final capped = literals.length <= _kMaxMustAlts
      ? literals
      : literals.sublist(0, _kMaxMustAlts);

  if (capped.length == 1) return escapeForNotiRegex(capped.first);
  return [for (final s in capped) escapeForNotiRegex(s)].join('|');
}

@visibleForTesting
NotiTemplate? findDistillRule({
  required List<NotiTemplate> userRules,
  required String pkg,
  required String direction,
  required String mustHint,
}) {
  final id = distilledRuleId(pkg, direction, mustHint);
  for (final t in userRules) {
    if (t.id == id) return t;
  }
  return null;
}

@visibleForTesting
NotiTemplate? findDistillExcludeRule({
  required List<NotiTemplate> userRules,
  required String pkg,
  required String mustHint,
}) {
  final id = distilledExcludeRuleId(pkg, mustHint);
  for (final t in userRules) {
    if (t.id == id) return t;
  }
  return null;
}

/// First matching AI-distilled **exclude** rule for [raw], if any.
NotiTemplate? matchDistillExcludeRule(
  RawNotification raw, [
  List<NotiTemplate>? templates,
]) {
  final list = templates ?? const <NotiTemplate>[];
  for (final t in list) {
    if (!isDistillExcludeTemplate(t)) continue;
    if (!t.packages.contains(raw.pkg)) continue;
    final must = t.mustContainRegex?.trim() ?? '';
    if (must.isEmpty) continue;
    try {
      final keywordText = t.keywordText(raw);
      if (notiRegex(must).hasMatch(keywordText)) return t;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Title (or short body line) that characterizes this concrete notification.
@visibleForTesting
List<String> sceneFragmentsForFusion(RawNotification raw, String mustHint) {
  final out = <String>[];
  final title = raw.title.trim();
  if (title.isNotEmpty && title.length <= 24) {
    if (normalizeDistillHint(title) != normalizeDistillHint(mustHint)) {
      out.add(title);
    }
  }
  // If title is empty / too long, take a short body head (rare).
  if (out.isEmpty) {
    final body = raw.text.trim();
    if (body.isNotEmpty) {
      final head = body.length <= 24 ? body : body.substring(0, 24);
      if (normalizeDistillHint(head) != normalizeDistillHint(mustHint)) {
        out.add(head);
      }
    }
  }
  return out;
}

@visibleForTesting
bool patternCoversSample(String? pattern, String sample) {
  final p = pattern?.trim() ?? '';
  final s = sample.trim();
  if (p.isEmpty || s.isEmpty) return false;
  try {
    return RegExp(p).hasMatch(s);
  } catch (_) {
    return false;
  }
}

String _pickMatchOn(String must, RawNotification raw) {
  if (patternCoversSample(must, raw.title)) return 'title';
  if (patternCoversSample(must, raw.fullText)) return 'body';
  return 'title';
}

/// Fuse into the single rule named `软件名-支出-支付成功` (shared mustHint).
///
/// Two real scenes both tagged 「支付成功」→ one rule; must OR-merges so both
/// parse. Different mustHint still creates a separate rule.
Future<String?> distillRecognitionRuleFromAi({
  required RawNotification raw,
  required ParseResult parsed,
  String? mustHint,
}) async {
  final pkg = raw.pkg.trim();
  if (pkg.isEmpty) return null;

  final direction = NotiTemplate.normalizeDirection(parsed.direction);
  final hint = (mustHint != null && mustHint.trim().isNotEmpty)
      ? mustHint.trim()
      : _fallbackMust(raw, direction);
  if (hint == null || hint.isEmpty) return null;

  await NotiTemplateStore.load();
  final users = NotiTemplateStore.peekUser();
  final id = distilledRuleId(pkg, direction, hint);
  // Fixed display name for the fused bucket (not per-title).
  final name = distilledRuleDisplayName(pkg, direction, hint);
  final fragments = sceneFragmentsForFusion(raw, hint);
  final prev = findDistillRule(
    userRules: users,
    pkg: pkg,
    direction: direction,
    mustHint: hint,
  );

  final must = fuseMustPattern(
    mustHint: hint,
    existingPattern: prev?.mustContainRegex,
    sceneFragments: fragments,
  );
  final matchOn = _pickMatchOn(must, raw);

  // Nothing new vs existing fused rule.
  if (prev != null &&
      prev.mustContainRegex == must &&
      prev.matchOn == matchOn) {
    return id;
  }

  final template = NotiTemplate(
    id: id,
    name: name,
    packages: [pkg],
    defaultCurrency: parsed.currency ?? prev?.defaultCurrency ?? 'CNY',
    mustContainRegex: must,
    excludeTextRegex: prev?.excludeTextRegex ??
        (r'验证码|登录|朋友圈|微信消息|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|'
            r'语音通话|视频通话|余额宝收益|生活号|待还|应还|请于|即将到期|还款提醒|账单提醒'),
    amountRegex: prev?.amountRegex ?? kAmountRegex,
    merchantFromTitle: prev?.merchantFromTitle ?? true,
    defaultAccountHint: parsed.accountHint ?? prev?.defaultAccountHint,
    direction: direction,
    matchOn: matchOn,
  );

  try {
    template.validateRegexes();
  } catch (_) {
    return prev != null ? id : null;
  }

  await NotiTemplateStore.upsertUserTemplate(template);
  return id;
}

/// Fuse into the single rule named `软件名-排除-验证码` (shared mustHint).
///
/// Same mustHint → one drop rule; must OR-merges so all scenes are skipped.
Future<String?> distillExcludeRecognitionRuleFromAi({
  required RawNotification raw,
  String? mustHint,
}) async {
  final pkg = raw.pkg.trim();
  if (pkg.isEmpty) return null;

  final hint = (mustHint != null && mustHint.trim().isNotEmpty)
      ? mustHint.trim()
      : _fallbackExcludeMust(raw);
  if (hint == null || hint.isEmpty) return null;

  await NotiTemplateStore.load();
  final users = NotiTemplateStore.peekUser();
  final id = distilledExcludeRuleId(pkg, hint);
  final name = distilledExcludeRuleDisplayName(pkg, hint);
  final fragments = sceneFragmentsForFusion(raw, hint);
  final prev = findDistillExcludeRule(
    userRules: users,
    pkg: pkg,
    mustHint: hint,
  );

  final must = fuseMustPattern(
    mustHint: hint,
    existingPattern: prev?.mustContainRegex,
    sceneFragments: fragments,
  );
  final matchOn = _pickMatchOn(must, raw);

  if (prev != null &&
      prev.mustContainRegex == must &&
      prev.matchOn == matchOn) {
    return id;
  }

  final template = NotiTemplate(
    id: id,
    name: name,
    packages: [pkg],
    defaultCurrency: 'CNY',
    mustContainRegex: must,
    amountRegex: prev?.amountRegex ?? kAmountRegex,
    merchantFromTitle: false,
    direction: 'out',
    matchOn: matchOn,
  );

  try {
    template.validateRegexes();
  } catch (_) {
    return prev != null ? id : null;
  }

  await NotiTemplateStore.upsertUserTemplate(template);
  return id;
}

String? _fallbackExcludeMust(RawNotification raw) {
  final title = raw.title.trim();
  const needles = [
    '验证码',
    '登录',
    '朋友圈',
    '微信消息',
    '发来一条',
    '拍了拍',
    '互动消息',
    '服务通知',
    '群聊',
  ];
  for (final n in needles) {
    if (title.contains(n) || raw.fullText.contains(n)) return n;
  }
  if (title.isEmpty) return '排除';
  if (title.length <= 16) return title;
  return title.substring(0, 12);
}

String? _fallbackMust(RawNotification raw, String direction) {
  final title = raw.title.trim();
  if (title.isEmpty) return null;
  switch (direction) {
    case 'in':
      if (title.contains('收款') || title.contains('到账')) {
        return title.contains('收款') ? '收款' : '到账';
      }
      break;
    case 'refund':
      if (title.contains('退款')) return '退款';
      break;
    case 'repay':
      if (title.contains('还款')) return '还款';
      break;
    default:
      if (title.contains('支付成功')) return '支付成功';
      if (title.contains('支付')) return '支付';
      if (title.contains('付款')) return '付款';
      if (title.contains('交易')) return '交易';
  }
  if (title.length <= 16) return title;
  return title.substring(0, 12);
}
