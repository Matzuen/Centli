import '../../core/utils/money.dart';

class NotiTemplate {
  const NotiTemplate({
    required this.id,
    required this.packages,
    this.defaultCurrency = 'CNY',
    this.titleRegex,
    this.mustContainRegex,
    this.excludeTextRegex,
    required this.amountRegex,
    this.merchantRegex,
    this.merchantFromTitle = false,
    this.defaultAccountHint,
  });

  final String id;
  final List<String> packages;
  final String defaultCurrency;
  final String? titleRegex;
  final String? mustContainRegex;
  final String? excludeTextRegex;
  final String amountRegex;
  final String? merchantRegex;
  final bool merchantFromTitle;
  final String? defaultAccountHint;

  factory NotiTemplate.fromJson(Map<String, dynamic> j) {
    return NotiTemplate(
      id: j['id'] as String,
      packages: (j['packages'] as List).cast<String>(),
      defaultCurrency: (j['defaultCurrency'] as String?) ?? 'CNY',
      titleRegex: j['titleRegex'] as String?,
      mustContainRegex: j['mustContainRegex'] as String?,
      excludeTextRegex: j['excludeTextRegex'] as String?,
      amountRegex: j['amountRegex'] as String,
      merchantRegex: j['merchantRegex'] as String?,
      merchantFromTitle: (j['merchantFromTitle'] as bool?) ?? false,
      defaultAccountHint: j['defaultAccountHint'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'packages': packages,
        'defaultCurrency': defaultCurrency,
        'titleRegex': titleRegex,
        'mustContainRegex': mustContainRegex,
        'excludeTextRegex': excludeTextRegex,
        'amountRegex': amountRegex,
        'merchantRegex': merchantRegex,
        'merchantFromTitle': merchantFromTitle,
        'defaultAccountHint': defaultAccountHint,
      };
}

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
  });

  final int? amountMinor;
  final String? currency;
  final String? merchant;
  final DateTime? happenAt;
  final bool ok;
  final String? templateId;
  final String? accountHint;
}

/// Shared amount pattern: ¥/￥/$/€ + optional currency code, capture group 1 = number.
const kAmountRegex =
    r'(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\s*)?(?:¥|￥|\$|€)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)';

/// Built-in templates (also mirrored in assets/noti_templates.json).
List<NotiTemplate> builtinNotiTemplates() => const [
      NotiTemplate(
        id: 'alipay_pay_success_zh',
        packages: ['com.eg.android.AlipayGphone'],
        mustContainRegex: '支付成功|付款成功',
        excludeTextRegex: '验证码|登录|收款到账提醒',
        amountRegex: kAmountRegex,
        merchantRegex: r'(?:向|给|商户)\s*(.+?)(?:\s|$)',
        defaultAccountHint: 'alipay',
      ),
      NotiTemplate(
        id: 'wechat_pay_success_zh',
        packages: ['com.tencent.mm'],
        mustContainRegex: '微信支付|支付成功|已支付',
        excludeTextRegex: '验证码|登录|朋友圈',
        amountRegex: kAmountRegex,
        merchantRegex: r'(.+?)(?:-微信支付|付款)',
        merchantFromTitle: true,
        defaultAccountHint: 'wechat',
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
    );
  }

  return ParseResult(ok: false, happenAt: when, currency: 'CNY');
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
  final m = RegExp(amountRegex).firstMatch(body);
  if (m == null) return null;
  final raw = (m.group(1) ?? '').replaceAll(',', '');
  final major = double.tryParse(raw);
  if (major == null) return null;
  final ccy = detectCurrencyNearMatch(body, m, defaultCcy);
  return _ExtractedAmount(minor: toMinor(ccy, major), currency: ccy);
}

String dedupeKey(RawNotification raw, ParseResult r) {
  final merchant = (r.merchant ?? '').trim().toLowerCase();
  final amt = r.amountMinor?.toString() ?? 'na';
  final bucket = raw.whenMs ~/ 120000; // 2-minute window
  return '${raw.pkg}|$merchant|$amt|$bucket';
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
