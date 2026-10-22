// Resolve user-entered app names / aliases to Android package names.
// Users often type 「中国农业银行」 instead of `com.android.bankabc`.

/// Known Chinese / short labels → candidate package names (first = preferred).
const Map<String, List<String>> kKnownAppPackageAliases = {
  '支付宝': ['com.eg.android.AlipayGphone'],
  '微信': ['com.tencent.mm'],
  '微信支付': ['com.tencent.mm'],
  '中国农业银行': [
    'com.android.bankabc',
    'com.chinamworld.main',
    'com.csii.abchina',
  ],
  '农业银行': [
    'com.android.bankabc',
    'com.chinamworld.main',
    'com.csii.abchina',
  ],
  '农行': ['com.android.bankabc', 'com.chinamworld.main'],
  '中国工商银行': ['com.icbc'],
  '工商银行': ['com.icbc'],
  '工行': ['com.icbc'],
  '中国建设银行': ['com.chinamworld.CCB'],
  '建设银行': ['com.chinamworld.CCB'],
  '建行': ['com.chinamworld.CCB'],
  '中国银行': ['com.chinamworld.bocmbci'],
  '中行': ['com.chinamworld.bocmbci'],
  '交通银行': ['com.bankcomm.Bankcomm'],
  '招行': ['cmb.pb'],
  '招商银行': ['cmb.pb'],
  '邮储银行': ['com.yitong.mbank.psbc'],
  '中国邮政储蓄银行': ['com.yitong.mbank.psbc'],
};

final RegExp kAndroidPackageNameRe = RegExp(
  r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
);

bool looksLikeAndroidPackageName(String raw) {
  final t = raw.trim();
  return t.contains('.') && kAndroidPackageNameRe.hasMatch(t);
}

/// Expand a typed package field into one or more real package names.
///
/// - Valid package name → `[input]`
/// - Known alias (e.g. 中国农业银行) → candidate list
/// - Otherwise empty (caller should pick from installed apps)
List<String> resolvePackageInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return const [];
  if (looksLikeAndroidPackageName(t)) return [t];
  final aliases = kKnownAppPackageAliases[t];
  if (aliases != null && aliases.isNotEmpty) return List<String>.from(aliases);
  // Fuzzy: label contains / is contained by a known key.
  for (final e in kKnownAppPackageAliases.entries) {
    if (t.contains(e.key) || e.key.contains(t)) {
      return List<String>.from(e.value);
    }
  }
  return const [];
}

String? packageInputError(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '请填写包名或从已安装应用中选择';
  if (looksLikeAndroidPackageName(t)) return null;
  if (resolvePackageInput(t).isNotEmpty) return null;
  return '请填写 Android 包名（如 com.android.bankabc），或点「从已安装应用选择」';
}
