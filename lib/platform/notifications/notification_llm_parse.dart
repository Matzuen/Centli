/// Optional LLM parse for payment notifications (Flutter-alive path only).
///
/// Callers must fall back to [parseNotification] when this returns null
/// (AI off / no credentials / timeout / non-payment / error).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../core/utils/money.dart';
import '../../features/ledger/llm_text_fill.dart';
import 'notification_parse.dart';

/// Outcome of asking the model about one notification.
class NotificationLlmParseOutcome {
  const NotificationLlmParseOutcome({
    required this.isPayment,
    this.parse,
    this.mustHint,
  });

  final bool isPayment;
  final ParseResult? parse;
  /// Stable title/body fragment for distilling a local must-contain rule.
  final String? mustHint;
}

/// Display name for rule titles: 支付宝 / 微信 / package tail.
String notificationAppLabel(String pkg) {
  if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
  if (pkg.contains('tencent.mm')) return '微信';
  if (pkg.contains('unionpay') || pkg.contains('chinapay')) return '云闪付';
  final parts = pkg.split('.');
  final last = parts.isNotEmpty ? parts.last.trim() : '';
  if (last.isEmpty) return pkg;
  // Prefer a readable segment (skip common suffixes).
  if (last.length <= 2 && parts.length >= 2) {
    return parts[parts.length - 2];
  }
  return last;
}

/// Map AI / parse direction → rule name suffix（支出 / 收入）.
String notificationDirectionRuleLabel(String? direction) {
  switch (NotiTemplate.normalizeDirection(direction)) {
    case 'in':
    case 'refund':
      return '收入';
    default:
      return '支出'; // out / repay
  }
}

/// Normalize a scenario hint for id / dedupe (trim, lower, collapse space).
String normalizeDistillHint(String hint) =>
    hint.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Distilled **capture** rule id prefix.
const String kDistillCaptureIdPrefix = 'distill_';

/// Distilled **exclude** (non-payment) rule id prefix.
const String kDistillExcludeIdPrefix = 'distill_excl_';

bool isDistillExcludeRuleId(String? id) =>
    id != null && id.startsWith(kDistillExcludeIdPrefix);

bool isDistillExcludeTemplate(NotiTemplate t) => isDistillExcludeRuleId(t.id);

/// Capture distill id (`distill_…`) but not exclude (`distill_excl_…`).
bool isDistillCaptureRuleId(String? id) =>
    id != null &&
    id.startsWith(kDistillCaptureIdPrefix) &&
    !isDistillExcludeRuleId(id);

bool isDistillCaptureTemplate(NotiTemplate t) => isDistillCaptureRuleId(t.id);

bool isDistillRuleId(String? id) =>
    isDistillCaptureRuleId(id) || isDistillExcludeRuleId(id);

/// Stable id for one **capture** scenario (pkg + 支/收 + mustHint).
String distilledRuleId(String pkg, String? direction, String mustHint) {
  final bucket = notificationDirectionRuleLabel(direction) == '收入' ? 'in' : 'out';
  final safe = pkg.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final key = _scenarioKey(mustHint);
  return '$kDistillCaptureIdPrefix${safe}_${bucket}_$key';
}

/// Stable id for the **exclude** rule of one app.
///
/// 按应用一条（而不是按场景一条）：排除规则的价值是"这个应用的这类通知以后
/// 别再问模型了"，把场景都并进同一条规则才能真正收敛。
String distilledExcludeRuleId(String pkg) {
  final safe = pkg.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return '$kDistillExcludeIdPrefix$safe';
}

/// Display name: `支付宝-支出-支付成功`.
String distilledRuleDisplayName(String pkg, String? direction, String mustHint) {
  final app = notificationAppLabel(pkg);
  final label = notificationDirectionRuleLabel(direction);
  final scene = mustHint.trim();
  if (scene.isEmpty) return '$app-$label';
  return '$app-$label-$scene';
}

/// Display name: `微信-排除`.
String distilledExcludeRuleDisplayName(String pkg) {
  return '${notificationAppLabel(pkg)}-排除';
}

String _scenarioKey(String hint) {
  final n = normalizeDistillHint(hint);
  var h = 0;
  for (final c in n.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h.toRadixString(16);
}

/// 这段文字能否作为排除规则的匹配片段。
///
/// 排除规则命中即丢弃、且发生在问模型之前，所以片段必须**足够具体**：
/// - 太短（<4 字，如「微信」「通知」）会误伤一大片；
/// - 含支付类词（支付/收款/退款…）更危险，会把真实账单一起吞掉；
/// - 含金额/币种同理。
///
/// 片段通常取实际通知的标题（如联系人名、群名），天然具体。
bool isExcludeSafeFragment(String fragment) {
  final t = fragment.trim();
  // 单字太短，几乎必然误伤。
  if (t.length < 2) return false;
  if (RegExp(r'[¥￥$€]|\d+(?:[.,]\d{1,2})?\s*元').hasMatch(t)) return false;
  const paymentWords = [
    '支付', '付款', '收款', '到账', '退款', '还款', '转账', '转帐',
    '消费', '扣款', '交易', '支出', '收入', '缴费', '充值', '提现',
  ];
  for (final w in paymentWords) {
    if (t.contains(w)) return false;
  }
  // 通用容器词：本身不具体，拿它排除等于整片丢掉。
  const genericWords = [
    '微信', '支付宝', '云闪付', '消息', '通知', '提醒', '服务', '账单',
    '系统', '官方', '群聊', '聊天', '新消息', '订阅号', '服务号',
  ];
  for (final w in genericWords) {
    if (t == w) return false;
  }
  return true;
}

/// 每分钟最多问几次 AI：通知密集时（群聊刷屏）宁可回落本地解析。
const int kLlmParsePerMinuteCap = 24;

final List<int> _llmCallStamps = <int>[];

/// 记录一次调用；超限返回 false（调用方应回落本地解析）。
@visibleForTesting
bool noteLlmParseCall({DateTime? now}) {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
  _llmCallStamps.removeWhere((s) => t - s > 60000);
  if (_llmCallStamps.length >= kLlmParsePerMinuteCap) return false;
  _llmCallStamps.add(t);
  return true;
}

@visibleForTesting
void resetLlmParseRateLimit() => _llmCallStamps.clear();

/// Ask the configured LLM to classify + extract a payment notification.
///
/// Returns null when [config] is not ready or the request fails — never throws
/// for network/parse errors (throws only on programmer misuse).
Future<NotificationLlmParseOutcome?> parseNotificationWithLlm(
  RawNotification raw, {
  required SmartFillLlmConfig config,
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!config.isNotifyAiReady) return null;
  if (raw.title.trim().isEmpty && raw.text.trim().isEmpty) return null;
  // 频率上限：通知密集时宁可这一条回落本地解析，也不把额度打满。
  if (!noteLlmParseCall()) return null;

  final base = config.normalizedBaseUrl;
  final model =
      config.model.trim().isEmpty ? kDefaultLlmModel : config.model.trim();
  final uri = Uri.parse('$base/chat/completions');
  final app = notificationAppLabel(raw.pkg);
  final system = '''
你是支付通知解析器。根据 Android 通知的包名、标题、正文判断是否为真实收付款，并提取字段。
只输出一个 JSON 对象，不要 markdown。
字段：
- isPayment: boolean（营销/验证码/聊天/登录/朋友圈等为 false）
- direction: "out"|"in"|"refund"|"repay"（仅 isPayment=true 时需要；不确定用 out）
- amount: number 元（可空）
- currency: 默认 "CNY"
- merchant: 商户或对方（可空）
- mustHint: 适合做本地规则关键词的短片段（2～16 字，勿写金额）。
  isPayment=true 时取支付类词（如「支付成功」）；
  isPayment=false 时取排除类词（如「验证码」「登录」「朋友圈」「微信消息」）。
''';
  final user = '''
包名: ${raw.pkg}
应用名: $app
标题: ${raw.title}
正文: ${raw.text}
''';

  final body = <String, dynamic>{
    'model': model,
    'temperature': 0,
    'max_tokens': 220,
    'messages': [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ],
  };

  final httpClient = client ?? http.Client();
  final owned = client == null;
  try {
    final resp = await httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final msg = choices.first is Map ? choices.first['message'] : null;
    final content = msg is Map ? msg['content'] : null;
    if (content is! String || content.trim().isEmpty) return null;

    final jsonStr = _extractJsonObject(content);
    if (jsonStr == null) return null;
    final map = jsonDecode(jsonStr);
    if (map is! Map) return null;

    final isPayment = map['isPayment'] == true;
    final mustHint = _sanitizeMustHint(map['mustHint']?.toString()) ??
        (isPayment ? _guessMustHint(raw) : _guessExcludeHint(raw));

    if (!isPayment) {
      final scene = mustHint ?? '排除';
      final when =
          DateTime.fromMillisecondsSinceEpoch(raw.whenMs, isUtc: false);
      return NotificationLlmParseOutcome(
        isPayment: false,
        mustHint: mustHint ?? scene,
        parse: ParseResult(
          ok: false,
          happenAt: when,
          currency: 'CNY',
          templateId: distilledExcludeRuleId(raw.pkg),
        ),
      );
    }

    final direction = NotiTemplate.normalizeDirection(
      map['direction']?.toString(),
    );
    double? amountMajor;
    final amountRaw = map['amount'];
    if (amountRaw is num) {
      amountMajor = amountRaw.toDouble();
    } else if (amountRaw is String) {
      amountMajor = double.tryParse(amountRaw.replaceAll(',', ''));
    }
    if (amountMajor != null && amountMajor <= 0) amountMajor = null;

    final currency = (map['currency']?.toString().trim().isNotEmpty == true)
        ? map['currency'].toString().trim().toUpperCase()
        : 'CNY';
    final merchant = _nullIfBlank(map['merchant']?.toString());

    final amountMinor =
        amountMajor == null ? null : toMinor(currency, amountMajor);
    final when = DateTime.fromMillisecondsSinceEpoch(raw.whenMs, isUtc: false);
    final scene = mustHint ?? '支付';
    final ruleId = distilledRuleId(raw.pkg, direction, scene);
    final accountHint = raw.pkg.contains('Alipay') || raw.pkg.contains('alipay')
        ? 'alipay'
        : raw.pkg.contains('tencent.mm')
            ? 'wechat'
            : null;

    return NotificationLlmParseOutcome(
      isPayment: true,
      mustHint: mustHint,
      parse: ParseResult(
        amountMinor: amountMinor,
        currency: currency,
        merchant: merchant,
        happenAt: when,
        ok: amountMinor != null,
        templateId: ruleId,
        accountHint: accountHint,
        direction: direction,
      ),
    );
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (owned) httpClient.close();
  }
}

String? _sanitizeMustHint(String? raw) {
  final t = raw?.trim() ?? '';
  if (t.length < 2 || t.length > 16) return null;
  if (RegExp(r'^\d').hasMatch(t)) return null;
  if (RegExp(r'[¥￥\$€]').hasMatch(t)) return null;
  return t;
}

String? _guessMustHint(RawNotification raw) {
  final title = raw.title.trim();
  if (title.isEmpty) return null;
  const needles = [
    '支付成功',
    '付款成功',
    '交易成功',
    '收款到账',
    '已收款',
    '退款',
    '还款',
    '到账',
    '扣款',
    '消费',
  ];
  for (final n in needles) {
    if (title.contains(n)) return n;
  }
  if (title.length <= 16) return title;
  return title.substring(0, 12);
}

String? _guessExcludeHint(RawNotification raw) {
  final title = raw.title.trim();
  final body = raw.fullText;
  const needles = [
    '验证码',
    '登录',
    '朋友圈',
    '微信消息',
    '发来一条',
    '拍了拍',
    '互动消息',
    '新的朋友',
    '群聊',
    '语音通话',
    '视频通话',
    '服务通知',
    '余额宝收益',
    '生活号',
    '还款提醒',
    '账单提醒',
  ];
  for (final n in needles) {
    if (title.contains(n) || body.contains(n)) return n;
  }
  if (title.isNotEmpty) {
    return title.length <= 16 ? title : title.substring(0, 12);
  }
  return '排除';
}

String? _extractJsonObject(String content) {
  final t = content.trim();
  if (t.startsWith('{') && t.endsWith('}')) return t;
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) return t.substring(start, end + 1);
  return null;
}

String? _nullIfBlank(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty || t.toLowerCase() == 'null') return null;
  return t;
}
