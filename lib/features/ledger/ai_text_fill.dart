/// Rule-based / local NLP for P3 AI text fill (记账话术 → 预填).
///
/// No remote LLM / API key required. Parses short Chinese (and light EN)
/// phrases into type / amount / category / account / note / time hints.
library;

class AiTextFillResult {
  const AiTextFillResult({
    this.type,
    this.amount,
    this.categoryName,
    this.accountName,
    this.toAccountName,
    this.merchant,
    this.note,
    this.happenAt,
    this.hits = const [],
  });

  /// `out` | `in` | `transfer`
  final String? type;
  final double? amount;

  /// Matched category display name (ledger category or synonym target).
  final String? categoryName;
  final String? accountName;
  final String? toAccountName;
  final String? merchant;
  final String? note;
  final DateTime? happenAt;

  /// Human-readable match notes for SnackBar feedback.
  final List<String> hits;

  bool get hasUsefulFill =>
      amount != null ||
      type != null ||
      categoryName != null ||
      accountName != null ||
      toAccountName != null ||
      (note != null && note!.isNotEmpty) ||
      happenAt != null;
}

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
    '饭',
    '餐',
    '星巴克',
    '麦当劳',
    '肯德基',
    '瑞幸',
    '喜茶',
    '奈雪',
  ],
  '交通': [
    '交通',
    '地铁',
    '公交',
    '打车',
    '出租车',
    '滴滴',
    '加油',
    '停车',
    '高铁',
    '火车',
    '飞机',
    '机票',
    '出行',
    '共享单车',
    '地铁票',
    '公交卡',
    '过路费',
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
  ],
  '医疗': ['医疗', '医院', '药店', '挂号', '体检', '买药', '诊所'],
  '教育': ['教育', '学费', '课程', '培训', '教材', '书本', '网课'],
  '工资': ['工资', '薪水', '薪资', '发薪', '薪水到账'],
  '红包': ['红包', '压岁钱'],
  '理财': ['理财', '分红', '利息', '基金', '股票收益'],
  '其他': ['其他', '杂项'],
};

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

  // --- type ---
  String? type;
  if (_transferKeywords.any(input.contains)) {
    type = 'transfer';
    hits.add('类型:转账');
  } else if (_incomeKeywords.any(input.contains)) {
    type = 'in';
    hits.add('类型:收入');
  } else if (_expenseKeywords.any(input.contains)) {
    type = 'out';
    hits.add('类型:支出');
  }

  // --- amount ---
  double? amount;
  for (final m in _amountRegex.allMatches(input)) {
    final g = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4);
    if (g == null) continue;
    final v = double.tryParse(g);
    if (v == null || v <= 0) continue;
    // Prefer currency-marked / unit-marked groups over bare trailing numbers.
    final ranked = m.group(1) != null || m.group(2) != null || m.group(3) != null;
    if (amount == null || ranked) {
      amount = v;
      if (ranked) break;
    }
  }
  if (amount != null) {
    hits.add('金额:$amount');
  }

  // --- happenAt ---
  DateTime? happenAt;
  if (input.contains('今天') || input.contains('今日')) {
    happenAt = DateTime(clock.year, clock.month, clock.day, clock.hour, clock.minute);
    hits.add('日期:今天');
  } else if (input.contains('昨天') || input.contains('昨日')) {
    final d = clock.subtract(const Duration(days: 1));
    happenAt = DateTime(d.year, d.month, d.day, clock.hour, clock.minute);
    hits.add('日期:昨天');
  } else if (input.contains('前天')) {
    final d = clock.subtract(const Duration(days: 2));
    happenAt = DateTime(d.year, d.month, d.day, clock.hour, clock.minute);
    hits.add('日期:前天');
  } else {
    final dm = _ymdRegex.firstMatch(input);
    if (dm != null) {
      final y = int.tryParse(dm.group(1) ?? '') ?? clock.year;
      final mo = int.parse(dm.group(2)!);
      final day = int.parse(dm.group(3)!);
      if (mo >= 1 && mo <= 12 && day >= 1 && day <= 31) {
        happenAt = DateTime(y, mo, day, clock.hour, clock.minute);
        hits.add('日期:$y-$mo-$day');
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
    }
  }
  if (type == 'transfer' && foundAccounts.length >= 2) {
    // Heuristic: 「从A到B」/「A转到B」
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
      accountName = foundAccounts[0];
      toAccountName = foundAccounts[1];
    }
    hits.add('账户:$accountName→$toAccountName');
  } else if (foundAccounts.isNotEmpty) {
    accountName = foundAccounts.first;
    hits.add('账户:$accountName');
  }

  // --- category (synonyms + ledger names) ---
  String? categoryName;
  // Prefer longer synonym hits.
  final synonymHits = <(String canon, String syn)>[];
  for (final entry in kCategorySynonyms.entries) {
    for (final syn in entry.value) {
      if (input.contains(syn)) {
        synonymHits.add((entry.key, syn));
      }
    }
  }
  synonymHits.sort((a, b) => b.$2.length.compareTo(a.$2.length));

  if (synonymHits.isNotEmpty) {
    final canon = synonymHits.first.$1;
    // Map canonical name onto an actual ledger category if present.
    categoryName = _bestCategoryMatch(canon, categoryNames) ?? canon;
    hits.add('分类:$categoryName');
  } else {
    final sortedCats = [...categoryNames]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final name in sortedCats) {
      if (name.isEmpty) continue;
      if (input.contains(name)) {
        categoryName = name;
        hits.add('分类:$categoryName');
        break;
      }
    }
  }

  // Infer type from category kind hints if still unknown.
  if (type == null && categoryName != null) {
    if (const {'工资', '红包', '理财'}.contains(categoryName) ||
        synonymHits.any((h) => const {'工资', '红包', '理财'}.contains(h.$1))) {
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
    }
  }

  // --- note: keep original phrase (user can edit) ---
  final note = input;

  return AiTextFillResult(
    type: type,
    amount: amount,
    categoryName: categoryName,
    accountName: accountName,
    toAccountName: toAccountName,
    merchant: merchant,
    note: note,
    happenAt: happenAt,
    hits: hits,
  );
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

String? _bestCategoryMatch(String canon, List<String> categoryNames) {
  for (final n in categoryNames) {
    if (n == canon) return n;
  }
  for (final n in categoryNames) {
    if (n.contains(canon) || canon.contains(n)) return n;
  }
  return null;
}
