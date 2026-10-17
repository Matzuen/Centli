import '../../core/utils/money.dart';

class NotiTemplate {
  const NotiTemplate({
    required this.id,
    this.name,
    required this.packages,
    this.defaultCurrency = 'CNY',
    this.titleRegex,
    this.mustContainRegex,
    this.excludeTextRegex,
    required this.amountRegex,
    this.merchantRegex,
    this.merchantFromTitle = false,
    this.defaultAccountHint,
    this.direction = 'out',
  });

  /// Allowed values: `in` | `out` | `refund`. Use [normalizeDirection].
  static const Set<String> kDirections = {'in', 'out', 'refund'};

  /// Illegal / missing → `'out'` (preserves pre-direction behavior).
  static String normalizeDirection(String? raw) {
    final v = raw?.trim();
    if (v != null && kDirections.contains(v)) return v;
    return 'out';
  }

  final String id;
  /// Optional display name (user rules / UI). Falls back to [id].
  final String? name;
  final List<String> packages;
  final String defaultCurrency;
  final String? titleRegex;
  final String? mustContainRegex;
  final String? excludeTextRegex;
  final String amountRegex;
  final String? merchantRegex;
  final bool merchantFromTitle;
  final String? defaultAccountHint;
  /// Flow direction: `in` (income), `out` (expense), `refund`.
  final String direction;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return kBuiltinTemplateNames[id] ?? id;
  }

  factory NotiTemplate.fromJson(Map<String, dynamic> j) {
    return NotiTemplate(
      id: j['id'] as String,
      name: j['name'] as String?,
      packages: (j['packages'] as List).cast<String>(),
      defaultCurrency: (j['defaultCurrency'] as String?) ?? 'CNY',
      titleRegex: j['titleRegex'] as String?,
      mustContainRegex: j['mustContainRegex'] as String?,
      excludeTextRegex: j['excludeTextRegex'] as String?,
      amountRegex: j['amountRegex'] as String,
      merchantRegex: j['merchantRegex'] as String?,
      merchantFromTitle: (j['merchantFromTitle'] as bool?) ?? false,
      defaultAccountHint: j['defaultAccountHint'] as String?,
      direction: normalizeDirection(j['direction'] as String?),
    );
  }

  /// Parse + validate regex fields. Returns null on schema/regex errors.
  static NotiTemplate? tryParse(Map<String, dynamic> j) {
    try {
      final t = NotiTemplate.fromJson(j);
      t.validateRegexes();
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Throws [FormatException] if any regex field is invalid.
  void validateRegexes() {
    for (final entry in [
      ('amountRegex', amountRegex),
      ('titleRegex', titleRegex),
      ('mustContainRegex', mustContainRegex),
      ('excludeTextRegex', excludeTextRegex),
      ('merchantRegex', merchantRegex),
    ]) {
      final raw = entry.$2?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        RegExp(raw);
      } catch (e) {
        throw FormatException('${entry.$1} 正则无效: $e');
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        'packages': packages,
        'defaultCurrency': defaultCurrency,
        'titleRegex': titleRegex,
        'mustContainRegex': mustContainRegex,
        'excludeTextRegex': excludeTextRegex,
        'amountRegex': amountRegex,
        'merchantRegex': merchantRegex,
        'merchantFromTitle': merchantFromTitle,
        'defaultAccountHint': defaultAccountHint,
        'direction': direction,
      };

  NotiTemplate copyWith({
    String? id,
    String? name,
    List<String>? packages,
    String? defaultCurrency,
    String? titleRegex,
    String? mustContainRegex,
    String? excludeTextRegex,
    String? amountRegex,
    String? merchantRegex,
    bool? merchantFromTitle,
    String? defaultAccountHint,
    String? direction,
    bool clearTitleRegex = false,
    bool clearMustContain = false,
    bool clearExclude = false,
    bool clearMerchantRegex = false,
    bool clearAccountHint = false,
    bool clearName = false,
  }) {
    return NotiTemplate(
      id: id ?? this.id,
      name: clearName ? null : (name ?? this.name),
      packages: packages ?? this.packages,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      titleRegex: clearTitleRegex ? null : (titleRegex ?? this.titleRegex),
      mustContainRegex:
          clearMustContain ? null : (mustContainRegex ?? this.mustContainRegex),
      excludeTextRegex:
          clearExclude ? null : (excludeTextRegex ?? this.excludeTextRegex),
      amountRegex: amountRegex ?? this.amountRegex,
      merchantRegex:
          clearMerchantRegex ? null : (merchantRegex ?? this.merchantRegex),
      merchantFromTitle: merchantFromTitle ?? this.merchantFromTitle,
      defaultAccountHint:
          clearAccountHint ? null : (defaultAccountHint ?? this.defaultAccountHint),
      direction: normalizeDirection(direction ?? this.direction),
    );
  }
}

/// Friendly names for builtin / official template ids.
const Map<String, String> kBuiltinTemplateNames = {
  'alipay_pay_success_zh': '支付宝交易/支付成功',
  'wechat_pay_success_zh': '微信支付成功',
  'alipay_receive_zh': '支付宝收款到账',
  'wechat_receive_zh': '微信收款到账',
  'alipay_refund_zh': '支付宝退款',
  'wechat_refund_zh': '微信退款',
};

class RawNotification {
  const RawNotification({
    required this.pkg,
    required this.title,
    required this.text,
    required this.whenMs,
    this.key,
  });

  final String pkg;
  final String title;
  final String text;
  final int whenMs;
  final String? key;

  String get fullText => '$title\n$text';

  factory RawNotification.fromMap(Map<String, dynamic> m) {
    return RawNotification(
      pkg: m['pkg'] as String? ?? '',
      title: m['title'] as String? ?? '',
      text: m['text'] as String? ?? '',
      whenMs: (m['when'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      key: m['key'] as String?,
    );
  }
}

class ParseResult {
  const ParseResult({
    this.amountMinor,
    this.currency,
    this.merchant,
    this.happenAt,
    required this.ok,
    this.templateId,
    this.accountHint,
    this.direction = 'out',
  });

  final int? amountMinor;
  final String? currency;
  final String? merchant;
  final DateTime? happenAt;
  final bool ok;
  final String? templateId;
  final String? accountHint;
  /// From matched [NotiTemplate.direction]; defaults to `'out'`.
  final String direction;
}

/// Shared amount pattern: ¥/￥/$/€ + optional currency code, capture group 1 = number.
const kAmountRegex =
    r'(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\s*|(?:\u00a5|\uffe5|\$|\u20ac))\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)';

/// Built-in templates (also mirrored in assets/noti_templates.json).
List<NotiTemplate> builtinNotiTemplates() => const [
      // Income / refund first so they win over expense when keywords overlap.
      NotiTemplate(
        id: 'alipay_receive_zh',
        name: '支付宝收款到账',
        packages: ['com.eg.android.AlipayGphone'],
        mustContainRegex: r'收款到账|收款成功|已收款|收到一笔|转入成功|余额.*转入',
        excludeTextRegex: r'验证码|登录|服务通知|生活号|退款',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:来自|从)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'alipay',
        direction: 'in',
      ),
      NotiTemplate(
        id: 'alipay_refund_zh',
        name: '支付宝退款',
        packages: ['com.eg.android.AlipayGphone'],
        mustContainRegex: r'退款成功|已退款|退款到账|退回成功|退款金额',
        excludeTextRegex: r'验证码|登录|服务通知|生活号',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:商户|来自)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'alipay',
        direction: 'refund',
      ),
      NotiTemplate(
        id: 'wechat_receive_zh',
        name: '微信收款到账',
        packages: ['com.tencent.mm'],
        // Prefer miss over wrong direction for 红包: only clear receive phrases.
        mustContainRegex:
            r'收款到账|收款成功|已收款|收到转账|零钱转入|微信收款|红包到账|你领取了.+红包|收到红包',
        excludeTextRegex:
            r'验证码|登录|朋友圈|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|语音通话|视频通话|发来一个红包|退款',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:来自|从)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'wechat',
        direction: 'in',
      ),
      NotiTemplate(
        id: 'wechat_refund_zh',
        name: '微信退款',
        packages: ['com.tencent.mm'],
        mustContainRegex: r'退款成功|已退款|退款到账|退回|退款金额',
        excludeTextRegex:
            r'验证码|登录|朋友圈|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|语音通话|视频通话',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:商户|来自)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'wechat',
        direction: 'refund',
      ),
      NotiTemplate(
        id: 'alipay_pay_success_zh',
        name: '支付宝交易/支付成功',
        packages: ['com.eg.android.AlipayGphone'],
        // Prefer occasional false positives into 待确认 over missing pay notices.
        // Do NOT use bare 「支付」 — it matches 「支付宝」 itself.
        // Income keywords removed from exclude (see receive/refund templates).
        mustContainRegex:
            r'支付成功|付款成功|交易成功|交易提醒|交易通知|消费成功|已支付|扣款成功|扣款提醒|已扣款|支出\s*[¥￥]|向.+付款|付款|支付金额|支付\s*[¥￥]|付款\s*[¥￥]|商户消费|成功付款',
        excludeTextRegex:
            r'验证码|登录|服务通知|余额宝收益|生活号|收款到账|收款成功|已收款|退款成功|已退款',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:向|给|商户)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'alipay',
        direction: 'out',
      ),
      NotiTemplate(
        id: 'wechat_pay_success_zh',
        name: '微信支付成功',
        packages: ['com.tencent.mm'],
        mustContainRegex:
            r'微信支付|支付成功|已支付|付款成功|商户消费|支付金额|付款金额|已付款|扣款成功',
        // Keep chat / peer-claimed 红包 excluded; income uses dedicated template.
        excludeTextRegex:
            r'验证码|登录|朋友圈|微信消息|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|语音通话|视频通话|收到一条|发来一个红包|领取了你的红包|收款到账|退款成功|已退款',
        amountRegex: kAmountRegex,
        merchantRegex: r'(.+?)(?:-微信支付|付款)',
        merchantFromTitle: true,
        defaultAccountHint: 'wechat',
        direction: 'out',
      ),
    ];

ParseResult parseNotification(
  RawNotification raw, [
  List<NotiTemplate>? templates,
]) {
  final list = templates ?? builtinNotiTemplates();
  final matched = list.where((t) => t.packages.contains(raw.pkg)).toList();
  final when = DateTime.fromMillisecondsSinceEpoch(raw.whenMs, isUtc: false);

  for (final t in matched) {
    try {
      if (t.titleRegex != null &&
          !RegExp(t.titleRegex!).hasMatch(raw.title)) {
        continue;
      }
      final body = raw.fullText;
      if (t.excludeTextRegex != null &&
          RegExp(t.excludeTextRegex!).hasMatch(body)) {
        continue;
      }
      if (t.mustContainRegex != null &&
          !RegExp(t.mustContainRegex!).hasMatch(body)) {
        continue;
      }

      final extracted = _extractAmount(body, t.amountRegex, t.defaultCurrency);
      String? merchant;
      if (t.merchantFromTitle && raw.title.trim().isNotEmpty) {
        merchant = raw.title.trim();
        if (t.merchantRegex != null) {
          final m = RegExp(t.merchantRegex!).firstMatch(raw.title);
          if (m != null) merchant = (m.group(1) ?? merchant).trim();
        }
      } else if (t.merchantRegex != null) {
        final m = RegExp(t.merchantRegex!).firstMatch(body);
        if (m != null) merchant = (m.group(1) ?? '').trim();
      }

      return ParseResult(
        amountMinor: extracted?.minor,
        currency: extracted?.currency ?? t.defaultCurrency,
        merchant: merchant?.isEmpty == true ? null : merchant,
        happenAt: when,
        ok: extracted != null,
        templateId: t.id,
        accountHint: t.defaultAccountHint,
        direction: NotiTemplate.normalizeDirection(t.direction),
      );
    } catch (_) {
      // Bad regex / rule - skip and try next template (R1-3 resilience).
      continue;
    }
  }

  return ParseResult(ok: false, happenAt: when, currency: 'CNY');
}



/// Diagnostic result for the 「试一试」 UI.
class ParseExplainResult {
  const ParseExplainResult({
    required this.result,
    required this.reason,
    required this.steps,
  });

  final ParseResult result;
  /// Short Chinese summary: matched / ignored reason.
  final String reason;
  final List<String> steps;
}

/// Walk templates like [parseNotification], recording skip reasons.
ParseExplainResult explainNotificationParse(
  RawNotification raw, [
  List<NotiTemplate>? templates,
]) {
  final list = templates ?? builtinNotiTemplates();
  final when = DateTime.fromMillisecondsSinceEpoch(raw.whenMs, isUtc: false);
  final steps = <String>[];

  if (raw.title.trim().isEmpty && raw.text.trim().isEmpty) {
    return ParseExplainResult(
      result: ParseResult(ok: false, happenAt: when, currency: 'CNY'),
      reason: '标题与正文均为空',
      steps: const ['输入为空'],
    );
  }

  final matchedPkgs = list.where((t) => t.packages.contains(raw.pkg)).toList();
  if (matchedPkgs.isEmpty) {
    steps.add('无模板监听包名 ${raw.pkg}');
    return ParseExplainResult(
      result: ParseResult(ok: false, happenAt: when, currency: 'CNY'),
      reason: '没有匹配该包名的规则',
      steps: steps,
    );
  }

  for (final t in matchedPkgs) {
    final label = t.displayName;
    if (t.titleRegex != null &&
        !RegExp(t.titleRegex!).hasMatch(raw.title)) {
      steps.add('「$label」标题未匹配 titleRegex');
      continue;
    }
    final body = raw.fullText;
    if (t.excludeTextRegex != null &&
        RegExp(t.excludeTextRegex!).hasMatch(body)) {
      steps.add('「$label」命中排除词 excludeTextRegex');
      continue;
    }
    if (t.mustContainRegex != null &&
        !RegExp(t.mustContainRegex!).hasMatch(body)) {
      steps.add('「$label」未含必须关键词 mustContainRegex');
      continue;
    }

    final extracted = _extractAmount(body, t.amountRegex, t.defaultCurrency);
    String? merchant;
    if (t.merchantFromTitle && raw.title.trim().isNotEmpty) {
      merchant = raw.title.trim();
      if (t.merchantRegex != null) {
        final m = RegExp(t.merchantRegex!).firstMatch(raw.title);
        if (m != null) merchant = (m.group(1) ?? merchant).trim();
      }
    } else if (t.merchantRegex != null) {
      final m = RegExp(t.merchantRegex!).firstMatch(body);
      if (m != null) merchant = (m.group(1) ?? '').trim();
    }

    final result = ParseResult(
      amountMinor: extracted?.minor,
      currency: extracted?.currency ?? t.defaultCurrency,
      merchant: merchant?.isEmpty == true ? null : merchant,
      happenAt: when,
      ok: extracted != null,
      templateId: t.id,
      accountHint: t.defaultAccountHint,
      direction: NotiTemplate.normalizeDirection(t.direction),
    );
    steps.add('命中「$label」(${t.id})');
    final reason = extracted == null
        ? '已匹配规则，但未解析出金额'
        : '解析成功';
    return ParseExplainResult(result: result, reason: reason, steps: steps);
  }

  steps.add('所有候选规则均未通过');
  return ParseExplainResult(
    result: ParseResult(ok: false, happenAt: when, currency: 'CNY'),
    reason: '未匹配任何规则（见步骤）',
    steps: steps,
  );
}

class _ExtractedAmount {
  const _ExtractedAmount({required this.minor, required this.currency});
  final int minor;
  final String currency;
}

/// Detect currency from symbol / code near the matched amount (P1: $/€).
String detectCurrencyNearMatch(String body, RegExpMatch m, String fallback) {
  final start = m.start;
  final end = m.end;
  final windowStart = start > 12 ? start - 12 : 0;
  final window = body.substring(windowStart, end);
  final matched = m.group(0) ?? '';

  if (window.contains('€') ||
      matched.contains('€') ||
      RegExp(r'\bEUR\b', caseSensitive: false).hasMatch(window)) {
    return 'EUR';
  }
  // Prefer explicit codes over bare $.
  if (RegExp(r'\bUSD\b', caseSensitive: false).hasMatch(window) ||
      matched.toUpperCase().contains('USD')) {
    return 'USD';
  }
  if (RegExp(r'\bHKD\b', caseSensitive: false).hasMatch(window) ||
      window.contains('HK\$') ||
      matched.contains('HK\$')) {
    return 'HKD';
  }
  if (RegExp(r'\bTWD\b', caseSensitive: false).hasMatch(window) ||
      window.contains('NT\$') ||
      matched.contains('NT\$')) {
    return 'TWD';
  }
  if (RegExp(r'\bJPY\b', caseSensitive: false).hasMatch(window)) {
    return 'JPY';
  }
  if (window.contains('\$') || matched.contains('\$')) {
    return 'USD';
  }
  if (window.contains('¥') ||
      window.contains('￥') ||
      RegExp(r'\bCNY\b', caseSensitive: false).hasMatch(window)) {
    return fallback.isNotEmpty ? fallback : 'CNY';
  }
  return fallback;
}

_ExtractedAmount? _extractAmount(
  String body,
  String amountRegex,
  String defaultCcy,
) {
  final re = RegExp(amountRegex);
  for (final m in re.allMatches(body)) {
    // Skip date fragments like 10月 / 15日 even if somehow matched.
    final end = m.end;
    final after = end < body.length ? body.substring(end, end + 1) : '';
    if (after.isNotEmpty && RegExp(r'[月日号时分秒]').hasMatch(after)) {
      continue;
    }
    final raw = (m.group(1) ?? '').replaceAll(',', '');
    final major = double.tryParse(raw);
    if (major == null) continue;
    final ccy = detectCurrencyNearMatch(body, m, defaultCcy);
    return _ExtractedAmount(minor: toMinor(ccy, major), currency: ccy);
  }
  return null;
}

String dedupeKey(RawNotification raw, ParseResult r) {
  final amt = r.amountMinor?.toString() ?? 'na';
  final bucket = raw.whenMs ~/ 120000; // 2-minute window
  // Failed parses must not collapse all same-pkg notices in the window
  // into one key (that caused "first capture works, later ones vanish").
  if (!r.ok || r.amountMinor == null) {
    final tip = '${raw.title}\n${raw.text}'.trim();
    final tipKey = tip.isEmpty ? 'empty' : tip.hashCode.toRadixString(16);
    return '${raw.pkg}|raw|$tipKey|$bucket';
  }
  // T2-3: omit merchant so native/Dart keys stay aligned when extractors differ.
  return '${raw.pkg}|$amt|$bucket';
}

String normalizeMerchantKey(String merchant) =>
    merchant.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Map package / hint → seeded account name.
String? defaultAccountNameForPkg(String pkg, {String? hint}) {
  final h = hint ?? '';
  if (h == 'alipay' || pkg.contains('Alipay') || pkg.contains('alipay')) {
    return '支付宝';
  }
  if (h == 'wechat' || pkg.contains('tencent.mm')) {
    return '微信';
  }
  return null;
}

/// Known capture apps for mapping UI (hint → display + packages).
const List<({String hint, String label, List<String> packages})>
    kCaptureAppDefs = [
  (
    hint: 'alipay',
    label: '支付宝',
    packages: ['com.eg.android.AlipayGphone'],
  ),
  (
    hint: 'wechat',
    label: '微信',
    packages: ['com.tencent.mm'],
  ),
];

String captureHintForPkg(String pkg) {
  for (final def in kCaptureAppDefs) {
    if (def.packages.contains(pkg)) return def.hint;
  }
  if (pkg.contains('Alipay') || pkg.contains('alipay')) return 'alipay';
  if (pkg.contains('tencent.mm')) return 'wechat';
  return pkg;
}

typedef PendingIngest = Future<String?> Function({
  required String ledgerId,
  required String sourcePkg,
  String? rawTitle,
  required String rawText,
  required String dedupeKey,
  int? amountMinor,
  String? currency,
  String? merchant,
  int? happenAt,
  bool parseOk,
  String? accountHint,
});

/// Debug: parse + ingest a few Alipay/WeChat samples. Returns inserted count.
Future<int> seedSamplePendingCaptures({
  required String ledgerId,
  required PendingIngest ingest,
  int Function()? nowMs,
  List<NotiTemplate>? templates,
}) async {
  final now = nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;
  final samples = <RawNotification>[
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: '支付成功',
      text: '向 星巴克咖啡 付款成功 ¥28.50',
      whenMs: now - 3600000,
    ),
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: '交易提醒',
      text: '向 全家便利店 付款 ¥15.80',
      whenMs: now - 5400000,
    ),
    RawNotification(
      pkg: 'com.tencent.mm',
      title: '星巴克咖啡-微信支付',
      text: '你已支付 ¥12.00',
      whenMs: now - 7200000,
    ),
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: '支付成功',
      text: '付款成功（无金额示例，便于测试解析失败）',
      whenMs: now - 1800000,
    ),
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: '支付成功',
      text: '付款成功 \$15.99',
      whenMs: now - 900000,
    ),
    RawNotification(
      pkg: 'com.eg.android.AlipayGphone',
      title: '支付成功',
      text: '付款成功 €9.50',
      whenMs: now - 600000,
    ),
  ];

  var added = 0;
  for (final raw in samples) {
    final parsed = parseNotification(raw, templates);
    final key = dedupeKey(raw, parsed);
    final id = await ingest(
      ledgerId: ledgerId,
      sourcePkg: raw.pkg,
      rawTitle: raw.title,
      rawText: raw.text,
      dedupeKey: key,
      amountMinor: parsed.amountMinor,
      currency: parsed.currency ?? 'CNY',
      merchant: parsed.merchant,
      happenAt: parsed.happenAt?.millisecondsSinceEpoch ?? raw.whenMs,
      parseOk: parsed.ok,
      accountHint: parsed.accountHint,
    );
    if (id != null) added++;
  }
  return added;
}


// ---------------------------------------------------------------------------
// Manual intake (share / OCR / clipboard / URL scheme)
// Slightly looser than NotificationListener: user explicitly chose the content.
// Still requires an amount OR clear payment/transfer keywords.
// ---------------------------------------------------------------------------

/// Keywords that indicate a payment / transfer / red-packet bill (send-out OK).
const kManualPayKeywords =
    r'转账成功|已转账|转账|红包|微信红包|付款给|支付成功|付款成功|已支付|微信支付|支付宝|向.+转账|收款方|交易成功|支出';

/// Chat / OTP noise to reject even on manual paths.
const kManualExcludeKeywords =
    r'验证码|登录验证|朋友圈|发来一条|拍了拍|互动消息|新的朋友|语音通话|视频通话|收到一条|发来一个红包|会话消息';

/// Guess source package from bill text (微信 / 支付宝).
String guessPkgFromText(String text) {
  final t = text;
  if (t.contains('支付宝') || t.contains('Alipay') || t.contains('alipay')) {
    return 'com.eg.android.AlipayGphone';
  }
  if (t.contains('微信') ||
      t.contains('WeChat') ||
      t.contains('微信支付') ||
      t.contains('微信红包')) {
    return 'com.tencent.mm';
  }
  return 'manual';
}

String? guessAccountHintFromText(String text) {
  final pkg = guessPkgFromText(text);
  if (pkg.contains('Alipay')) return 'alipay';
  if (pkg.contains('tencent.mm')) return 'wechat';
  return null;
}

String? _extractMerchantLoose(String body) {
  final patterns = <String>[
    r'向\s*(.+?)转账',
    r'付款给\s*(.+?)(?:\s|$|¥|￥|\d)',
    r'给\s*(.+?)\s*(?:转账|发红包|红包)',
    r'(?:商户|收款方|对方|收款人)[:：\s]*(.+?)(?:\s|$|¥|￥)',
    r'转账给\s*(.+?)(?:\s|$|¥|￥|\d)',
  ];
  for (final p in patterns) {
    final m = RegExp(p).firstMatch(body);
    if (m != null) {
      final name = (m.group(1) ?? '').trim();
      if (name.isNotEmpty && name.length < 40) return name;
    }
  }
  return null;
}

/// Parse user-chosen bill text (share / OCR / clipboard / deep link).
///
/// Returns [ParseResult] with [ParseResult.templateId] set to a synthetic id
/// like `manual_transfer_zh` when accepted, or null when rejected.
ParseResult parseManualCaptureText(
  String text, {
  String? title,
  String? pkgHint,
  DateTime? happenAt,
}) {
  final body = [
    if (title != null && title.trim().isNotEmpty) title.trim(),
    text.trim(),
  ].where((s) => s.isNotEmpty).join('\n');
  final when = happenAt ?? DateTime.now();

  if (body.trim().isEmpty) {
    return ParseResult(ok: false, happenAt: when, currency: 'CNY');
  }

  if (RegExp(kManualExcludeKeywords).hasMatch(body)) {
    return ParseResult(ok: false, happenAt: when, currency: 'CNY');
  }

  final hasKeyword = RegExp(kManualPayKeywords).hasMatch(body);
  final extracted = _extractAmount(body, kAmountRegex, 'CNY');
  final hasAmount = extracted != null;

  if (!hasAmount && !hasKeyword) {
    return ParseResult(ok: false, happenAt: when, currency: 'CNY');
  }
  if (!hasKeyword && hasAmount) {
    final hasMoneyMark =
        RegExp(r'¥|￥|\$|€|USD|CNY|金额|元').hasMatch(body);
    if (!hasMoneyMark) {
      return ParseResult(ok: false, happenAt: when, currency: 'CNY');
    }
  }

  final pkg = (pkgHint != null && pkgHint.isNotEmpty)
      ? pkgHint
      : guessPkgFromText(body);
  if (pkg != 'manual') {
    final raw = RawNotification(
      pkg: pkg,
      title: title ?? '',
      text: text,
      whenMs: when.millisecondsSinceEpoch,
    );
    final strict = parseNotification(raw);
    if (strict.templateId != null) {
      return strict;
    }
  }

  final merchant = _extractMerchantLoose(body);
  final hint = guessAccountHintFromText(body);
  final isTransfer = RegExp(r'转账|红包').hasMatch(body);

  return ParseResult(
    amountMinor: extracted?.minor,
    currency: extracted?.currency ?? 'CNY',
    merchant: merchant,
    happenAt: when,
    ok: extracted != null,
    templateId: isTransfer ? 'manual_transfer_zh' : 'manual_pay_zh',
    accountHint: hint,
    direction: 'out',
  );
}

/// Build a dedupe key for manual intake (share / OCR / clipboard / URL).
String manualDedupeKey({
  required String sourceKind,
  required String body,
  required ParseResult parsed,
  int? whenMs,
}) {
  final ms = whenMs ?? DateTime.now().millisecondsSinceEpoch;
  final bucket = ms ~/ 120000;
  final tip = body.trim();
  final tipKey = tip.isEmpty ? 'empty' : tip.hashCode.toRadixString(16);
  final amt = parsed.amountMinor?.toString() ?? 'na';
  final merchant = (parsed.merchant ?? '').trim().toLowerCase();
  return 'manual|$sourceKind|$merchant|$amt|$tipKey|$bucket';
}
