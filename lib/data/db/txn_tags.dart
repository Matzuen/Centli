import 'dart:convert';

/// Encode tag list for DB / export. Empty → null. Max 5 tags, each ≤ 12 chars.
String? encodeTxnTags(List<String>? tags) {
  if (tags == null || tags.isEmpty) return null;
  final cleaned = <String>[];
  for (final raw in tags) {
    var t = raw.trim();
    if (t.isEmpty) continue;
    if (t.length > 12) t = t.substring(0, 12);
    if (!cleaned.contains(t)) cleaned.add(t);
    if (cleaned.length >= 5) break;
  }
  if (cleaned.isEmpty) return null;
  return jsonEncode(cleaned);
}

/// Decode tags JSON from DB. Invalid / empty → [].
List<String> decodeTxnTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <String>[];
    for (final e in decoded) {
      if (e is! String) continue;
      final t = e.trim();
      if (t.isEmpty) continue;
      out.add(t.length > 12 ? t.substring(0, 12) : t);
      if (out.length >= 5) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}
