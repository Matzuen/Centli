import 'dart:convert';

/// One saved bookkeeping prefills (amount/category/account/note/tags/…).
class TxnTemplate {
  const TxnTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.accountId,
    this.categoryId,
    this.merchant,
    this.note,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String type;
  final int amountMinor;
  final String currency;
  final String accountId;
  final String? categoryId;
  final String? merchant;
  final String? note;
  final List<String> tags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'amountMinor': amountMinor,
        'currency': currency,
        'accountId': accountId,
        'categoryId': categoryId,
        'merchant': merchant,
        'note': note,
        'tags': tags,
      };

  static TxnTemplate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = '${m['id'] ?? ''}'.trim();
    final name = '${m['name'] ?? ''}'.trim();
    final type = '${m['type'] ?? 'out'}'.trim();
    final accountId = '${m['accountId'] ?? ''}'.trim();
    final currency = '${m['currency'] ?? 'CNY'}'.trim();
    final amount = m['amountMinor'];
    final amountMinor = amount is int
        ? amount
        : int.tryParse('$amount') ?? 0;
    if (id.isEmpty || name.isEmpty || accountId.isEmpty) return null;
    final cat = '${m['categoryId'] ?? ''}'.trim();
    final merchant = '${m['merchant'] ?? ''}'.trim();
    final note = '${m['note'] ?? ''}'.trim();
    final tagsRaw = m['tags'];
    final tags = <String>[];
    if (tagsRaw is List) {
      for (final t in tagsRaw) {
        final s = '$t'.trim();
        if (s.isNotEmpty) tags.add(s);
      }
    }
    return TxnTemplate(
      id: id,
      name: name,
      type: type.isEmpty ? 'out' : type,
      amountMinor: amountMinor,
      currency: currency.isEmpty ? 'CNY' : currency,
      accountId: accountId,
      categoryId: cat.isEmpty ? null : cat,
      merchant: merchant.isEmpty ? null : merchant,
      note: note.isEmpty ? null : note,
      tags: tags,
    );
  }

  static List<TxnTemplate> decodeList(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! List) return const [];
      final out = <TxnTemplate>[];
      for (final e in decoded) {
        final t = tryParse(e);
        if (t != null) out.add(t);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<TxnTemplate> items) =>
      jsonEncode([for (final t in items) t.toJson()]);
}
