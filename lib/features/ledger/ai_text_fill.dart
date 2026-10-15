/// Rule-based / local NLP for AI text fill (记账话术 → 预填).
///
/// Parses short Chinese (and light EN) phrases into type / amount / category /
/// account / merchant / note / time hints. Optional LLM enhancement lives in
/// [llm_text_fill.dart] and falls back here on failure.
library;

/// Lightweight category row for matching (avoids coupling to Drift models).
class CategoryRef {
  const CategoryRef({
    required this.name,
    this.id,
    this.parentId,
    this.kind,
  });

  final String name;
  final String? id;
  final String? parentId;

  /// `out` | `in` when known.
  final String? kind;

  bool get isLeafHint => parentId != null;
}

class AiTextFillResult {
  const AiTextFillResult({
    this.type,
    this.amount,
    this.categoryName,
    this.categoryConfidence,
    this.accountName,
    this.toAccountName,
    this.merchant,
    this.note,
    this.happenAt,
    this.hits = const [],
    this.source = 'local',
  });

  /// `out` | `in` | `transfer`
  final String? type;
  final double? amount;

  /// Matched category display name (ledger category or synonym target).
  final String? categoryName;

  /// 0..1; only treat as a fill when >= [kCategoryConfidenceThreshold].
  final double? categoryConfidence;
  final String? accountName;
  final String? toAccountName;
  final String? merchant;

  /// Leftover remark after structured fields are stripped — never the full input.
  final String? note;
  final DateTime? happenAt;

  /// Human-readable match notes for SnackBar feedback.
  final List<String> hits;

  /// `local` | `llm`
  final String source;

  bool get hasConfidentCategory =>
      categoryName != null &&
      categoryName!.isNotEmpty &&
      (categoryConfidence ?? 0) >= kCategoryConfidenceThreshold;

  bool get hasUsefulFill =>
      amount != null ||
      type != null ||
      hasConfidentCategory ||
      accountName != null ||
      toAccountName != null ||
      (merchant != null && merchant!.isNotEmpty) ||
      (note != null && note!.isNotEmpty) ||
      happenAt != null;

  AiTextFillResult copyWith({
    String? type,
    double? amount,
    String? categoryName,
    double? categoryConfidence,
    String? accountName,
    String? toAccountName,
    String? merchant,
    String? note,
    DateTime? happenAt,
    List<String>? hits,
    String? source,
    bool clearCategory = false,
    bool clearNote = false,
  }) {
    return AiTextFillResult(
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      categoryConfidence: clearCategory
          ? null
          : (categoryConfidence ?? this.categoryConfidence),
      accountName: accountName ?? this.accountName,
      toAccountName: toAccountName ?? this.toAccountName,
      merchant: merchant ?? this.merchant,
      note: clearNote ? null : (note ?? this.note),
      happenAt: happenAt ?? this.happenAt,
      hits: hits ?? this.hits,
      source: source ?? this.source,
    );
  }
}

/// Below this, leave category unset rather than guess wrong.
const double kCategoryConfidenceThreshold = 0.72;

/// Built-in synonym → canonical category name (seed defaults + common aliases).
const Map<String, List<String>> kCategorySynonyms = {
  '餐饮': [
    '餐饮',
    '吃饭',
    '午饭',
    '午餐',
    '晚饭',
    '晚餐',
    '早餐',
    '早饭',
    '外卖',
    '美团',
    '饿了么',
    '咖啡',
    '奶茶',
    '食堂',
    '美食',
    '聚餐',
    '宵夜',
    '火锅',
    '烧烤',
    '早餐店',
    '午饭钱',
    '星巴克',
    '麦当劳',
    '肯德基',
    '瑞幸',
    '喜茶',
    '奈雪',
    '必胜客',
    '汉堡王',
    '沙县',
    '黄焖鸡',
    '麻辣烫',
    '冒菜',
    '面馆',
    '小吃',
    '点外卖',
  ],
  '交通': [
    '交通',
    '地铁',
    '公交',
    '打车',
    '出租车',
    '滴滴',
    '高德打车',
    '加油',
    '停车',
    '停车费',
    '高铁',
    '火车',
    '飞机',
    '机票',
    '出行',
    '共享单车',
    '地铁票',
    '公交卡',
    '过路费',
    '过路',
    '油费',
    '电车',
    '船票',
  ],
  '日用': [
    '日用',
    '超市',
    '日用品',
    '洗衣液',
    '牙膏',
    '便利店',
    '百货',
    '购物',
    '日杂',
    '盒马',
    '永辉',
    '物美',
    '沃尔玛',
    '家乐福',
    '山姆',
    '京东到家',
    '生活用品',
  ],
  '居住': [
    '居住',
    '房租',
    '水电',
    '物业',
    '房贷',
    '煤气',
    '燃气',
    '电费',
    '水费',
    '宽带',
    '网费',
    '暖气',
    '取暖',
    '租金',
  ],
  '娱乐': [
    '娱乐',
    '电影',
    '游戏',
    '会员',
    '门票',
    'KTV',
    '演唱会',
    '视频会员',
    '音乐',
    '爱奇艺',
    '腾讯视频',
    '优酷',
    '网易云',
    'Steam',
  ],
  '医疗': ['医疗', '医院', '药店', '挂号', '体检', '买药', '诊所', '看病', '门诊'],
  '教育': ['教育', '学费', '课程', '培训', '教材', '书本', '网课', '辅导', '考证'],
  '购物': [
    '网购',
    '淘宝',
    '天猫',
    '京东',
    '拼多多',
    '得物',
    '唯品会',
    '服饰',
    '衣服',
    '鞋子',
  ],
  '工资': ['工资', '薪水', '薪资', '发薪', '薪水到账', '发工资'],
  '红包': ['红包', '压岁钱'],
  '理财': ['理财', '分红', '利息', '基金', '股票收益', '收益到账'],
  '其他': ['其他', '杂项'],
};

/// Very short tokens — only count when not a substring of a longer already-matched synonym.
const Set<String> _shortSynonyms = {'饭', '餐', '药'};

const List<String> _incomeKeywords = [
  '收到',
  '收入',
  '入账',
  '到账',
  '赚了',
  '工资',
  '薪水',
  '薪资',
  '红包',
  '报销',
];

const List<String> _transferKeywords = [
  '转账',
  '转到',
  '转入',
  '转出',
  '转给',
  '汇款',
];

const List<String> _expenseKeywords = [
  '花了',
  '花',
  '买了',
  '买',
  '付了',
  '付',
  '支付',
  '消费',
  '支出',
  '付款',
];

final RegExp _amountRegex = RegExp(
  r'(?:'
  r'[￥¥\$€£]\s*(\d+(?:\.\d{1,2})?)'
  r'|'
  r'(\d+(?:\.\d{1,2})?)\s*(?:元|块钱|块|圆)'
  r'|'
  r'(?:花了|花|付了|付|买了|买|收入|收到|到账|转账|转了|转)\s*(\d+(?:\.\d{1,2})?)'
  r'|'
  r'(?<![\d.])(\d+(?:\.\d{1,2})?)(?![\d.])'
  r')',
);

final RegExp _ymdRegex = RegExp(
  r'(?:(\d{4})[年\-./])?(\d{1,2})[月\-./](\d{1,2})日?',
);

/// Parse free-text bookkeeping phrase into structured fill hints.
AiTextFillResult parseBookkeepingText(
  String raw, {
  List<String> categoryNames = const [],
  List<CategoryRef> categories = const [],
  List<String> accountNames = const [],
  DateTime? now,
}) {
  final input = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (input.isEmpty) {
    return const AiTextFillResult();
  }

  final hits = <String>[];
  final lower = input.toLowerCase();
  final clock = now ?? DateTime.now();
  final consumed = <_Span>[];

  // Resolve category name list from either API.
  final catNames = categories.isNotEmpty
      ? categories.map((c) => c.name).toList()
      : categoryNames;

  // --- type ---
  String? type;
  if (_transferKeywords.any(input.contains)) {
    type = 'transfer';
    hits.add('类型:转账');
    _markFirstKeyword(input, _transferKeywords, consumed);
  } else if (_incomeKeywords.any(input.contains)) {
    type = 'in';
    hits.add('类型:收入');
    _markFirstKeyword(input, _incomeKeywords, consumed);
  } else if (_expenseKeywords.any(input.contains)) {
    type = 'out';
    hits.add('类型:支出');
    _markFirstKeyword(input, _expenseKeywords, consumed);
  }

  // --- amount ---
  double? amount;
  Match? amountMatch;
  for (final m in _amountRegex.allMatches(input)) {
    final g = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4);
    if (g == null) continue;
    final v = double.tryParse(g);
    if (v == null || v <= 0) continue;
    final ranked =
        m.group(1) != null || m.group(2) != null || m.group(3) != null;
    if (amount == null || ranked) {
      amount = v;
      amountMatch = m;
      if (ranked) break;
    }
  }
  if (amount != null && amountMatch != null) {
    hits.add('金额:$amount');
    consumed.add(_Span(amountMatch.start, amountMatch.end));
  }

  // --- happenAt ---
  DateTime? happenAt;
  if (input.contains('今天') || input.contains('今日')) {
    happenAt =
        DateTime(clock.year, clock.month, clock.day, clock.hour, clock.minute);
    hits.add('日期:今天');
    _markLiteral(input, input.contains('今天') ? '今天' : '今日', consumed);
  } else if (input.contains('昨天') || input.contains('昨日')) {
    final d = clock.subtract(const Duration(days: 1));
    happenAt = DateTime(d.year, d.month, d.day, clock.hour, clock.minute);
    hits.add('日期:昨天');
    _markLiteral(input, input.contains('昨天') ? '昨天' : '昨日', consumed);
  } else if (input.contains('前天')) {
    final d = clock.subtract(const Duration(days: 2));
    happenAt = DateTime(d.year, d.month, d.day, clock.hour, clock.minute);
    hits.add('日期:前天');
    _markLiteral(input, '前天', consumed);
  } else {
    final dm = _ymdRegex.firstMatch(input);
    if (dm != null) {
      final y = int.tryParse(dm.group(1) ?? '') ?? clock.year;
      final mo = int.parse(dm.group(2)!);
      final day = int.parse(dm.group(3)!);
      if (mo >= 1 && mo <= 12 && day >= 1 && day <= 31) {
        happenAt = DateTime(y, mo, day, clock.hour, clock.minute);
        hits.add('日期:$y-$mo-$day');
        consumed.add(_Span(dm.start, dm.end));
      }
    }
  }

  // --- accounts ---
  String? accountName;
  String? toAccountName;
  final sortedAccounts = [...accountNames]
    ..sort((a, b) => b.length.compareTo(a.length));
  final foundAccounts = <String>[];
  for (final name in sortedAccounts) {
    if (name.isEmpty) continue;
    if (input.contains(name) || lower.contains(name.toLowerCase())) {
      foundAccounts.add(name);
      _markLiteral(input, name, consumed);
    }
  }
  if (type == 'transfer' && foundAccounts.length >= 2) {
    final fromIdx = _indexOfAny(input, ['从', '由']);
    final toIdx = _indexOfAny(input, ['到', '至', '给', '转入']);
    if (fromIdx >= 0 && toIdx > fromIdx) {
      accountName = _pickAccountInRange(input, foundAccounts, fromIdx, toIdx) ??
          foundAccounts.first;
      toAccountName = _pickAccountInRange(
            input,
            foundAccounts,
            toIdx,
            input.length,
          ) ??
          foundAccounts[1];
    } else {
      // Prefer left-to-right order in the original string.
      foundAccounts.sort((a, b) => input.indexOf(a).compareTo(input.indexOf(b)));
      accountName = foundAccounts[0];
      toAccountName = foundAccounts[1];
    }
    hits.add('账户:$accountName→$toAccountName');
  } else if (foundAccounts.isNotEmpty) {
    accountName = foundAccounts.first;
    hits.add('账户:$accountName');
  }

  // --- category (synonyms + ledger names, with confidence) ---
  String? categoryName;
  double? categoryConfidence;
  final synonymHits = <(String canon, String syn, double score)>[];
  for (final entry in kCategorySynonyms.entries) {
    for (final syn in entry.value) {
      if (!input.contains(syn)) continue;
      if (_shortSynonyms.contains(syn) && syn.length <= 1) {
        // Single-char: only if not part of a longer synonym already considered
        // later by length sort — score low.
        synonymHits.add((entry.key, syn, 0.55));
      } else if (syn.length <= 1) {
        synonymHits.add((entry.key, syn, 0.55));
      } else if (syn.length == 2) {
        synonymHits.add((entry.key, syn, 0.78));
      } else {
        synonymHits.add((entry.key, syn, 0.92));
      }
    }
  }
  synonymHits.sort((a, b) {
    final byLen = b.$2.length.compareTo(a.$2.length);
    if (byLen != 0) return byLen;
    return b.$3.compareTo(a.$3);
  });

  // Direct ledger category name hits (prefer longer / leaf).
  final directHits = <(String name, double score)>[];
  final sortedCats = [...catNames]..sort((a, b) => b.length.compareTo(a.length));
  for (final name in sortedCats) {
    if (name.isEmpty) continue;
    if (input.contains(name)) {
      final leafBoost = _isLeafName(name, categories) ? 0.05 : 0.0;
      directHits.add((name, 0.95 + leafBoost > 1.0 ? 1.0 : 0.95 + leafBoost));
    }
  }

  if (directHits.isNotEmpty) {
    categoryName = directHits.first.$1;
    categoryConfidence = directHits.first.$2;
    hits.add('分类:$categoryName');
    _markLiteral(input, categoryName, consumed);
  } else if (synonymHits.isNotEmpty) {
    final best = synonymHits.first;
    final mapped = _bestCategoryMatch(
      best.$1,
      catNames,
      categories: categories,
      preferKind: type == 'in'
          ? 'in'
          : type == 'out'
              ? 'out'
              : null,
    );
    if (mapped != null) {
      categoryName = mapped;
      categoryConfidence = best.$3;
      hits.add('分类:$categoryName');
      _markLiteral(input, best.$2, consumed);
    } else if (best.$3 >= kCategoryConfidenceThreshold) {
      // Canon not in ledger — still suggest name; UI maps fuzzily or leaves unset.
      categoryName = best.$1;
      final scaled = best.$3 * 0.85;
      categoryConfidence = scaled;
      if (scaled >= kCategoryConfidenceThreshold) {
        hits.add('分类:$categoryName');
        _markLiteral(input, best.$2, consumed);
      } else {
        categoryName = null;
        categoryConfidence = null;
      }
    }
  }

  // Drop weak category guesses.
  if (categoryName != null &&
      (categoryConfidence ?? 0) < kCategoryConfidenceThreshold) {
    hits.removeWhere((h) => h.startsWith('分类:'));
    categoryName = null;
    categoryConfidence = null;
  }

  // Infer type from category kind hints if still unknown.
  if (type == null && categoryName != null) {
    final incomeCanons = const {'工资', '红包', '理财'};
    final isIncome = incomeCanons.contains(categoryName) ||
        synonymHits.any((h) => incomeCanons.contains(h.$1));
    if (isIncome) {
      type = 'in';
      hits.add('类型:收入');
    } else {
      type = 'out';
      hits.add('类型:支出');
    }
  }
  type ??= 'out';

  // --- merchant ---
  String? merchant;
  final merchantMatch = RegExp(
    r'(?:在|向|给|于)\s*([A-Za-z0-9\u4e00-\u9fff]{2,16}?)(?=(?:\s|花了|花|付了|付|买了|买|转|消费|支付|\d|元|块|$))',
  ).firstMatch(input);
  if (merchantMatch != null) {
    final cand = merchantMatch.group(1)!.trim();
    if (cand.isNotEmpty &&
        !sortedAccounts.contains(cand) &&
        cand != categoryName) {
      merchant = cand;
      hits.add('商家:$merchant');
      consumed.add(_Span(merchantMatch.start, merchantMatch.end));
    }
  }
  // Bare known brand as merchant when not already set.
  if (merchant == null) {
    const brands = [
      '星巴克',
      '麦当劳',
      '肯德基',
      '瑞幸',
      '喜茶',
      '奈雪',
      '美团',
      '饿了么',
      '盒马',
      '永辉',
      '滴滴',
      '淘宝',
      '京东',
      '拼多多',
    ];
    for (final b in brands) {
      if (input.contains(b)) {
        merchant = b;
        hits.add('商家:$merchant');
        _markLiteral(input, b, consumed);
        break;
      }
    }
  }

  // --- note: leftover only ---
  final note = _leftoverNote(input, consumed);

  return AiTextFillResult(
    type: type,
    amount: amount,
    categoryName: categoryName,
    categoryConfidence: categoryConfidence,
    accountName: accountName,
    toAccountName: toAccountName,
    merchant: merchant,
    note: note,
    happenAt: happenAt,
    hits: hits,
    source: 'local',
  );
}

/// Map a free-text category hint (e.g. from LLM) onto a ledger category name.
String? mapCategoryHintToLocal(
  String? hint, {
  List<String> categoryNames = const [],
  List<CategoryRef> categories = const [],
  String? preferKind,
}) {
  if (hint == null) return null;
  final cleaned = hint.trim();
  if (cleaned.isEmpty) return null;
  final names = categories.isNotEmpty
      ? categories.map((c) => c.name).toList()
      : categoryNames;
  if (names.isEmpty) return null;

  // Exact
  for (final n in names) {
    if (n == cleaned) return n;
  }
  // Case-insensitive / contains
  final lower = cleaned.toLowerCase();
  final fuzzy = <(String, int)>[];
  for (final n in names) {
    if (n.toLowerCase() == lower) return n;
    if (n.contains(cleaned) || cleaned.contains(n)) {
      final leaf = _isLeafName(n, categories) ? 1 : 0;
      fuzzy.add((n, n.length + leaf * 10));
    }
  }
  if (fuzzy.isNotEmpty) {
    fuzzy.sort((a, b) => b.$2.compareTo(a.$2));
    if (preferKind != null && categories.isNotEmpty) {
      for (final f in fuzzy) {
        CategoryRef? ref;
        for (final c in categories) {
          if (c.name == f.$1) {
            ref = c;
            break;
          }
        }
        if (ref?.kind == preferKind) return f.$1;
      }
    }
    return fuzzy.first.$1;
  }

  // Synonym → canon → local
  for (final entry in kCategorySynonyms.entries) {
    if (entry.key == cleaned || entry.value.contains(cleaned)) {
      return _bestCategoryMatch(
        entry.key,
        names,
        categories: categories,
        preferKind: preferKind,
      );
    }
  }
  return null;
}

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

void _markLiteral(String input, String lit, List<_Span> consumed) {
  final i = input.indexOf(lit);
  if (i >= 0) consumed.add(_Span(i, i + lit.length));
}

void _markFirstKeyword(String input, List<String> keys, List<_Span> consumed) {
  // Prefer longer keyword.
  final sorted = [...keys]..sort((a, b) => b.length.compareTo(a.length));
  for (final k in sorted) {
    final i = input.indexOf(k);
    if (i >= 0) {
      consumed.add(_Span(i, i + k.length));
      return;
    }
  }
}

String? _leftoverNote(String input, List<_Span> consumed) {
  if (consumed.isEmpty) {
    // Nothing structured matched beyond defaults — if input looks like a bare
    // phrase with digits already taken, avoid dumping whole string.
    return null;
  }
  final chars = List<bool>.filled(input.length, false);
  for (final s in consumed) {
    final a = s.start.clamp(0, input.length);
    final b = s.end.clamp(0, input.length);
    for (var i = a; i < b; i++) {
      chars[i] = true;
    }
  }
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    if (!chars[i]) buf.write(input[i]);
  }
  var left = buf.toString().trim();
  // Strip leftover filler particles / punctuation.
  left = left
      .replaceAll(RegExp(r'[，,。.\s]+'), ' ')
      .replaceAll(RegExp(r'^(的|了|啊|呢|吧|呀)+'), '')
      .replaceAll(RegExp(r'(的|了|啊|呢|吧|呀)+$'), '')
      .trim();
  // Drop pure noise like lone "用/在".
  if (left.length <= 1) return null;
  if (RegExp(r'^[\d.\s￥¥\$元块圆]+$').hasMatch(left)) return null;
  return left.isEmpty ? null : left;
}

int _indexOfAny(String s, List<String> keys) {
  var best = -1;
  for (final k in keys) {
    final i = s.indexOf(k);
    if (i >= 0 && (best < 0 || i < best)) best = i;
  }
  return best;
}

String? _pickAccountInRange(
  String input,
  List<String> accounts,
  int start,
  int end,
) {
  final slice = input.substring(start, end.clamp(0, input.length));
  for (final a in accounts) {
    if (slice.contains(a)) return a;
  }
  return null;
}

bool _isLeafName(String name, List<CategoryRef> categories) {
  if (categories.isEmpty) return false;
  CategoryRef? self;
  for (final c in categories) {
    if (c.name == name) {
      self = c;
      break;
    }
  }
  if (self == null) return false;
  if (self.parentId != null) return true;
  // Parent with children → not leaf.
  final id = self.id;
  if (id == null) return false;
  return !categories.any((c) => c.parentId == id);
}

String? _bestCategoryMatch(
  String canon,
  List<String> categoryNames, {
  List<CategoryRef> categories = const [],
  String? preferKind,
}) {
  final candidates = <String>[];
  for (final n in categoryNames) {
    if (n == canon) candidates.add(n);
  }
  if (candidates.isEmpty) {
    for (final n in categoryNames) {
      if (n.contains(canon) || canon.contains(n)) candidates.add(n);
    }
  }
  if (candidates.isEmpty) return null;

  // Prefer leaf + matching kind.
  candidates.sort((a, b) {
    final la = _isLeafName(a, categories) ? 1 : 0;
    final lb = _isLeafName(b, categories) ? 1 : 0;
    if (la != lb) return lb.compareTo(la);
    return b.length.compareTo(a.length);
  });

  if (preferKind != null && categories.isNotEmpty) {
    for (final name in candidates) {
      for (final c in categories) {
        if (c.name == name && c.kind == preferKind) return name;
      }
    }
  }
  return candidates.first;
}
