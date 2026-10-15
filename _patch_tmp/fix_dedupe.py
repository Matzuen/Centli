from pathlib import Path
root = Path(r"D:\Resource\Codebase\studyProject\Centli")

# Improve dedupe for failed parses so they don't block real payments
path = root / "lib/platform/notifications/notification_parse.dart"
text = path.read_text(encoding="utf-8")
old = '''String dedupeKey(RawNotification raw, ParseResult r) {
  final merchant = (r.merchant ?? '').trim().toLowerCase();
  final amt = r.amountMinor?.toString() ?? 'na';
  final bucket = raw.whenMs ~/ 120000; // 2-minute window
  return '${raw.pkg}|$merchant|$amt|$bucket';
}'''
new = '''String dedupeKey(RawNotification raw, ParseResult r) {
  final merchant = (r.merchant ?? '').trim().toLowerCase();
  final amt = r.amountMinor?.toString() ?? 'na';
  final bucket = raw.whenMs ~/ 120000; // 2-minute window
  // Failed parses must not collapse all same-pkg notices in the window
  // into one key (that caused "first capture works, later ones vanish").
  if (!r.ok || r.amountMinor == null) {
    final tip = '${raw.title}\\n${raw.text}'.trim();
    final tipKey = tip.isEmpty ? 'empty' : tip.hashCode.toRadixString(16);
    return '${raw.pkg}|raw|$tipKey|$bucket';
  }
  return '${raw.pkg}|$merchant|$amt|$bucket';
}'''
if old not in text:
    raise SystemExit('dedupeKey not found')
path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
print("patched dedupeKey")
