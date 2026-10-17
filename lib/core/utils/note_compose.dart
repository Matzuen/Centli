/// Compose parsed merchant text into the user-facing note field.
///
/// Convention (B4 T1-1):
/// - both empty → null
/// - only one non-empty → that value
/// - both non-empty → `"商户 · 备注"` (U+00B7 with spaces)
String? composeNote({String? merchant, String? note}) {
  final m = merchant?.trim();
  final n = note?.trim();
  final hasM = m != null && m.isNotEmpty;
  final hasN = n != null && n.isNotEmpty;
  if (!hasM && !hasN) return null;
  if (hasM && !hasN) return m;
  if (!hasM && hasN) return n;
  return '$m · $n';
}
