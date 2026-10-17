/// DeepSeek model-name typo hints (Levenshtein) for smart-fill settings.
library;

/// Known DeepSeek chat/vision model ids we surface in the UI.
const kKnownDeepSeekModels = <String>[
  'deepseek-flash',
  'deepseek-v4-pro',
];

/// Max edit distance treated as a likely typo (inclusive).
const kDeepSeekTypoMaxDistance = 2;

/// Classic Levenshtein edit distance (insert / delete / substitute = 1).
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  // Two-row DP to keep memory small.
  var prev = List<int>.generate(n + 1, (j) => j);
  var curr = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}

bool baseUrlLooksLikeDeepSeek(String? baseUrl) {
  final u = (baseUrl ?? '').trim().toLowerCase();
  if (u.isEmpty) return false;
  return u.contains('deepseek');
}

/// Nearest known DeepSeek model when [model] is a near-miss typo.
///
/// Returns null when:
/// - [baseUrl] does not look like DeepSeek (when [requireDeepSeekHost] is true),
/// - [model] exactly matches a known id,
/// - best distance is 0 or greater than [maxDistance].
String? suggestDeepSeekModelTypo(
  String model, {
  String? baseUrl,
  int maxDistance = kDeepSeekTypoMaxDistance,
  bool requireDeepSeekHost = true,
}) {
  if (requireDeepSeekHost && !baseUrlLooksLikeDeepSeek(baseUrl)) {
    return null;
  }
  final trimmed = model.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (kKnownDeepSeekModels.any((k) => k.toLowerCase() == lower)) {
    return null;
  }
  String? best;
  var bestDist = maxDistance + 1;
  for (final known in kKnownDeepSeekModels) {
    final d = levenshteinDistance(lower, known.toLowerCase());
    if (d > 0 && d < bestDist) {
      bestDist = d;
      best = known;
    } else if (d > 0 && d == bestDist && best != null) {
      // Prefer the lexicographically smaller id on ties for stability.
      if (known.compareTo(best) < 0) best = known;
    }
  }
  if (best != null && bestDist <= maxDistance) return best;
  return null;
}

/// Kind of inline model hint for DeepSeek hosts.
enum DeepSeekModelHintKind {
  /// No hint (not DeepSeek host, empty model, or known model).
  none,

  /// Near-miss typo of a known model — show one-tap fix.
  typo,

  /// Unknown / far from known — generic vision warning.
  unsupportedVision,
}

/// Resolved hint for the settings UI / load warning.
class DeepSeekModelHint {
  const DeepSeekModelHint({
    required this.kind,
    this.suggestion,
    this.message,
  });

  final DeepSeekModelHintKind kind;
  final String? suggestion;
  final String? message;

  static const none = DeepSeekModelHint(kind: DeepSeekModelHintKind.none);
}

/// Evaluate model hint when the API base looks like DeepSeek.
DeepSeekModelHint evaluateDeepSeekModelHint(
  String model, {
  String? baseUrl,
  int maxDistance = kDeepSeekTypoMaxDistance,
}) {
  if (!baseUrlLooksLikeDeepSeek(baseUrl)) return DeepSeekModelHint.none;
  final trimmed = model.trim();
  if (trimmed.isEmpty) return DeepSeekModelHint.none;
  final lower = trimmed.toLowerCase();
  if (kKnownDeepSeekModels.any((k) => k.toLowerCase() == lower)) {
    return DeepSeekModelHint.none;
  }
  final suggestion = suggestDeepSeekModelTypo(
    trimmed,
    baseUrl: baseUrl,
    maxDistance: maxDistance,
    requireDeepSeekHost: true,
  );
  if (suggestion != null) {
    return DeepSeekModelHint(
      kind: DeepSeekModelHintKind.typo,
      suggestion: suggestion,
      message: '疑似拼写错误，是否改为 $suggestion？',
    );
  }
  return const DeepSeekModelHint(
    kind: DeepSeekModelHintKind.unsupportedVision,
    message: '该模型可能不支持图片识别',
  );
}

/// Line appended under a failed connection-test message when a typo is likely.
String? connectionTestTypoHintLine(
  String model, {
  String? baseUrl,
  int maxDistance = kDeepSeekTypoMaxDistance,
}) {
  final s = suggestDeepSeekModelTypo(
    model,
    baseUrl: baseUrl,
    maxDistance: maxDistance,
  );
  if (s == null) return null;
  return '提示：你可能想用 $s';
}
