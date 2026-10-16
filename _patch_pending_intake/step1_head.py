# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(r"D:\Resource\Codebase\studyProject\Centli")

manual_append = """

// ---------------------------------------------------------------------------
// Manual intake (share / OCR / clipboard / URL scheme)
// Slightly looser than NotificationListener: user explicitly chose the content.
// Still requires an amount OR clear payment/transfer keywords.
// ---------------------------------------------------------------------------

/// Keywords that indicate a payment / transfer / red-packet bill (send-out OK).
const kManualPayKeywords =
    r'\u8f6c\u8d26\u6210\u529f|\u5df2\u8f6c\u8d26|\u8f6c\u8d26|\u7ea2\u5305|\u5fae\u4fe1\u7ea2\u5305|\u4ed8\u6b3e\u7ed9|\u652f\u4ed8\u6210\u529f|\u4ed8\u6b3e\u6210\u529f|\u5df2\u652f\u4ed8|\u5fae\u4fe1\u652f\u4ed8|\u652f\u4ed8\u5b9d|\u5411.+\u8f6c\u8d26|\u6536\u6b3e\u65b9|\u4ea4\u6613\u6210\u529f|\u652f\u51fa';

/// Chat / OTP noise to reject even on manual paths.
const kManualExcludeKeywords =
    r'\u9a8c\u8bc1\u7801|\u767b\u5f55\u9a8c\u8bc1|\u670b\u53cb\u5708|\u53d1\u6765\u4e00\u6761|\u62cd\u4e86\u62cd|\u4e92\u52a8\u6d88\u606f|\u65b0\u7684\u670b\u53cb|\u8bed\u97f3\u901a\u8bdd|\u89c6\u9891\u901a\u8bdd|\u6536\u5230\u4e00\u6761|\u53d1\u6765\u4e00\u4e2a\u7ea2\u5305|\u9886\u53d6\u4e86\u4f60\u7684\u7ea2\u5305|\u4f1a\u8bdd\u6d88\u606f';

/// Guess source package from bill text (\u5fae\u4fe1 / \u652f\u4ed8\u5b9d).
String guessPkgFromText(String text) {
  final t = text;
  if (t.contains('\u652f\u4ed8\u5b9d') || t.contains('Alipay') || t.contains('alipay')) {
    return 'com.eg.android.AlipayGphone';
  }
  if (t.contains('\u5fae\u4fe1') || t.contains('WeChat') || t.contains('\u5fae\u4fe1\u652f\u4ed8') ||
      t.contains('\u5fae\u4fe1\u7ea2\u5305')) {
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
    r'\u5411\\s*(.+?)\\s*\u8f6c\u8d26',
    r'\u4ed8\u6b3e\u7ed9\\s*(.+?)(?:\\s|$|\u00a5|\uffe5|\\d)',
    r'\u7ed9\\s*(.+?)\\s*(?:\u8f6c\u8d26|\u53d1\u7ea2\u5305|\u7ea2\u5305)',
    r'(?:\u5546\u6237|\u6536\u6b3e\u65b9|\u5bf9\u65b9|\u6536\u6b3e\u4eba)[:\uff1a\\s]*(.+?)(?:\\s|$|\u00a5|\uffe5)',
    r'\u8f6c\u8d26\u7ed9\\s*(.+?)(?:\\s|$|\u00a5|\uffe5|\\d)',
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
  ].where((s) => s.isNotEmpty).join('\\n');
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

  // Require amount, or a clear keyword (still prefer amount for ok=true).
  if (!hasAmount && !hasKeyword) {
    return ParseResult(ok: false, happenAt: when, currency: 'CNY');
  }
  // Amount without keyword: accept only if looks like a bill line.
  if (!hasKeyword && hasAmount) {
    final hasMoneyMark = RegExp(r'\u00a5|\uffe5|\\$|\u20ac|USD|CNY|\u91d1\u989d|\u5143').hasMatch(body);
    if (!hasMoneyMark) {
      return ParseResult(ok: false, happenAt: when, currency: 'CNY');
    }
  }

  // Prefer structured notification templates when we can guess the app.
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
  final isTransfer = RegExp(r'\u8f6c\u8d26|\u7ea2\u5305').hasMatch(body);

  return ParseResult(
    amountMinor: extracted?.minor,
    currency: extracted?.currency ?? 'CNY',
    merchant: merchant,
    happenAt: when,
    ok: extracted != null,
    templateId: isTransfer ? 'manual_transfer_zh' : 'manual_pay_zh',
    accountHint: hint,
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
"""

parse_path = root / "lib/platform/notifications/notification_parse.dart"
parse = parse_path.read_text(encoding="utf-8")
if "parseManualCaptureText" not in parse:
    # Fix the join newline - we used \\n in the triple-quoted string for PowerShell safety
    # but we need actual \n in Dart source for join
    fixed = manual_append.replace("join('\\\\n')", "join('\\n')")
    # Also the patterns got double-escaped - decode unicode escapes by writing as unicode
    parse_path.write_text(parse + fixed.encode('utf-8').decode('unicode_escape') if False else parse + _decode_escapes(fixed), encoding="utf-8")
    print("appended")
else:
    print("already present")

def _decode_escapes(s):
    # Only decode \uXXXX sequences, leave regex \\ alone carefully
    import re
    def repl(m):
        return chr(int(m.group(1), 16))
    # First convert \uXXXX
    s2 = re.sub(r'\\u([0-9a-fA-F]{4})', repl, s)
    # Fix join('\\n') - in the string we may have join('\\n') already correct after u-decode
    # Fix double-backslashes in raw strings that should be single for Dart raw regex
    # Our patterns used \\\\s which after writing should be \\s in file for Dart raw string
    return s2

# redefine properly
