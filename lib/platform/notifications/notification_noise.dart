import 'package:flutter/foundation.dart';

/// Strong marketing words (G29.1 noise filter).
const kNotiMarketingWords = [
  '优惠',
  '券',
  '活动',
  '限时',
  '抽奖',
  '会员',
  '积分',
  '理财',
  '基金',
  '借款',
  '额度',
];

@visibleForTesting
bool containsMarketingWord(String text) {
  for (final w in kNotiMarketingWords) {
    if (text.contains(w)) return true;
  }
  return false;
}

/// RemoteInput amount parse (G29.4): 24.70 / ￥24.7 / 24.7元 → minor; abc → null.
@visibleForTesting
int? parseRemoteInputAmountMinor(String raw) {
  final cleaned = raw.replaceAll(',', '');
  final m = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(cleaned);
  if (m == null) return null;
  final major = double.tryParse(m.group(1)!);
  if (major == null) return null;
  return (major * 100).round();
}

/// Whether a widened-gate notification should be dropped as weak noise.
@visibleForTesting
bool shouldDropAsWeakNoise({
  required bool templateMatched,
  required int? amountMinor,
  required String title,
  required String text,
}) {
  if (templateMatched && amountMinor != null) return false;
  if (templateMatched) return false; // matched but no amount → parse_failed path
  final body = '$title\n$text';
  if (amountMinor == null && !templateMatched) return true;
  if (amountMinor == null && containsMarketingWord(body)) return true;
  return false;
}
