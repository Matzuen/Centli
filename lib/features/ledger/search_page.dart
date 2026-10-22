import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_range.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/date_range_control.dart';
import '../../core/widgets/txn_grouped_list.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import '../../app/theme.dart';
import '../../core/widgets/centli_error_state.dart';
import '../../core/widgets/glass.dart';

/// Split "午餐 支付宝" into keywords (space / full-width space separated).
@visibleForTesting
List<String> searchKeywords(String raw) {
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[\s\u3000]+'))) {
    final t = part.trim();
    if (t.isNotEmpty) seen.add(t);
  }
  return seen.toList();
}

/// Bill search: multi-keyword text + quick filters (category / account / date).
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  var _seq = 0;
  List<Transaction>? _results;
  Object? _error;
  var _loading = false;
  var _truncated = false;
  static const _searchLimit = 200;

  /// `out` | `in` | `transfer` | null (any)
  String? _type;
  String? _categoryId;
  String? _accountId;
  DateRangeWindow? _range;

  List<Account> _accounts = const [];
  List<Category> _outCats = const [];
  List<Category> _inCats = const [];

  List<String> get _keywords => searchKeywords(
        _query.isEmpty ? _controller.text : _query,
      );

  bool get _hasText => _controller.text.trim().isNotEmpty;

  bool get _hasFilters =>
      _type != null ||
      _categoryId != null ||
      _accountId != null ||
      _range != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
      _loadFilterSources();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadFilterSources() async {
    final ledger = await ref.read(currentLedgerProvider.future);
    if (!mounted || ledger == null) return;
    final db = ref.read(databaseProvider);
    final accounts = await db.loadAccountsIncludingArchived(ledger.id);
    final outCats = await db.loadCategories(ledger.id, 'out');
    final inCats = await db.loadCategories(ledger.id, 'in');
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _outCats = outCats;
      _inCats = inCats;
    });
  }

  void _onChanged(String raw) {
    setState(() {}); // clear affordance + keyword chips live update
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _runSearch(raw);
    });
  }

  Future<void> _runSearch([String? raw]) async {
    final q = (raw ?? _controller.text).trim();
    final seq = ++_seq;
    final hasFilters = _hasFilters;

    if (q.isEmpty && !hasFilters) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _query = '';
        _results = null;
        _error = null;
        _loading = false;
        _truncated = false;
      });
      return;
    }

    final ledger = await ref.read(currentLedgerProvider.future);
    if (!mounted || seq != _seq) return;
    if (ledger == null) {
      setState(() {
        _query = q;
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });

    try {
      final rows = await ref.read(databaseProvider).searchTransactions(
            ledger.id,
            q,
            type: _type,
            categoryId: _categoryId,
            accountId: _accountId,
            startMs: _range?.startMs,
            endMs: _range?.endMs,
            limit: _searchLimit,
          );
      if (!mounted || seq != _seq) return;
      final truncated = rows.length > _searchLimit;
      final shown = truncated ? rows.take(_searchLimit).toList() : rows;
      setState(() {
        _results = shown;
        _truncated = truncated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _type = null;
      _categoryId = null;
      _accountId = null;
      _range = null;
    });
    _runSearch();
  }

  // ---------------------------------------------------------------- filters

  void _setType(String? type) {
    setState(() {
      _type = type;
      if (_categoryId != null &&
          (type == 'transfer' ||
              !_catsForType(type).any((c) => c.id == _categoryId))) {
        _categoryId = null;
      }
    });
    _runSearch();
  }

  List<Category> _catsForType(String? type) {
    if (type == 'in') return _inCats;
    if (type == 'out') return _outCats;
    return [..._outCats, ..._inCats];
  }

  Future<void> _pickCategory() async {
    final cats = _catsForType(_type);
    if (cats.isEmpty) return;
    final id = await showGlassSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '按分类筛选',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.apps,
                          color: scheme.onSurfaceVariant,
                        ),
                        title: const Text('全部分类'),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                      for (final c in cats)
                        ListTile(
                          leading: Icon(
                            Icons.label_outline,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: Text(c.name),
                          trailing: c.id == _categoryId
                              ? Icon(Icons.check, color: scheme.primary)
                              : null,
                          onTap: () => Navigator.pop(ctx, c.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (id == null || !mounted) return;
    setState(() => _categoryId = id.isEmpty ? null : id);
    _runSearch();
  }

  Future<void> _pickAccount() async {
    if (_accounts.isEmpty) return;
    final id = await showGlassSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '按资产账户筛选',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.apps,
                          color: scheme.onSurfaceVariant,
                        ),
                        title: const Text('全部资产账户'),
                        onTap: () => Navigator.pop(ctx, ''),
                      ),
                      for (final a in _accounts)
                        ListTile(
                          leading: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            a.archived == 1 ? '${a.name}（已归档）' : a.name,
                          ),
                          subtitle: Text(a.currency),
                          trailing: a.id == _accountId
                              ? Icon(Icons.check, color: scheme.primary)
                              : null,
                          onTap: () => Navigator.pop(ctx, a.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (id == null || !mounted) return;
    setState(() => _accountId = id.isEmpty ? null : id);
    _runSearch();
  }

  Future<void> _pickRange() async {
    final picked = await showCentliDateRangeSheet(
      context,
      current: _range ?? DateRangeWindow.lastDays(days: 30),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _runSearch();
  }

  bool _isQuickRange(String kind) {
    final r = _range;
    if (r == null) return false;
    switch (kind) {
      case 'week':
        final w = DateRangeWindow.thisWeek();
        return r.startMs == w.startMs && r.endMs == w.endMs;
      case 'month':
        final m = DateRangeWindow.thisMonth();
        return r.kind == DateRangeKind.month &&
            r.startMs == m.startMs &&
            r.endMs == m.endMs;
      case 'lastMonth':
        final lm = DateRangeWindow.lastMonth();
        return r.kind == DateRangeKind.month &&
            r.startMs == lm.startMs &&
            r.endMs == lm.endMs;
      default:
        return false;
    }
  }

  void _setQuickRange(String kind) {
    DateRangeWindow next;
    switch (kind) {
      case 'week':
        next = DateRangeWindow.thisWeek();
      case 'month':
        next = DateRangeWindow.thisMonth();
      case 'lastMonth':
        next = DateRangeWindow.lastMonth();
      default:
        return;
    }
    setState(() {
      if (_isQuickRange(kind)) {
        _range = null;
      } else {
        _range = next;
      }
    });
    _runSearch();
  }

  ({int incomeMinor, int expenseMinor, String ccy}) _resultTotals(
    List<Transaction> rows,
    String baseCcy,
  ) {
    var income = 0;
    var expense = 0;
    for (final t in rows) {
      // 多币种时只累计本位币，避免把不同货币的 minor 直接相加。
      if (t.currency != baseCcy) continue;
      if (t.type == 'in') {
        income += t.amountMinor;
      } else if (t.type == 'out') {
        expense += t.amountMinor;
      }
    }
    return (incomeMinor: income, expenseMinor: expense, ccy: baseCcy);
  }

  /// Space-separated type words become the type filter instead of keywords.
  void _commitQuickType(String? type) {
    if (type == null) return;
    final words = {'支出': 'out', '收入': 'in', '转账': 'transfer'};
    final keyword = words.entries.firstWhere((e) => e.value == type).key;
    final rest = searchKeywords(_controller.text)
        .where((k) => k != keyword)
        .join(' ');
    _controller.text = rest;
    setState(() => _type = type);
    _runSearch(rest);
  }

  String _typeLabel(String? t) {
    switch (t) {
      case 'out':
        return '支出';
      case 'in':
        return '收入';
      case 'transfer':
        return '转账';
      default:
        return '全部';
    }
  }

  String? _categoryName(String? id) {
    if (id == null) return null;
    for (final c in [..._outCats, ..._inCats]) {
      if (c.id == id) return c.name;
    }
    return id;
  }

  String? _accountName(String? id) {
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) {
        return a.archived == 1 ? '${a.name}（已归档）' : a.name;
      }
    }
    return id;
  }

  /// 「更多」: every filter in one sheet (power-user path).
  Future<void> _openFilterSheet() async {
    final result = await showGlassSheet<_SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SearchFilterSheet(
        initial: _SearchFilters(
          type: _type,
          categoryId: _categoryId,
          accountId: _accountId,
          range: _range,
        ),
        accounts: _accounts,
        outCats: _outCats,
        inCats: _inCats,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _type = result.type;
      _categoryId = result.categoryId;
      _accountId = result.accountId;
      _range = result.range;
    });
    await _runSearch();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final hide = ref.watch(hideAmountProvider);
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '多个关键词用空格分开，如「午餐 支付宝」',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _runSearch,
        ),
        actions: [
          if (_hasText)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _runSearch('');
                _focus.requestFocus();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _quickFilterBar(scheme),
          if (_hasText) _keywordChips(scheme),
          Expanded(child: _buildBody(scheme, hide)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ quick bar

  Widget _quickFilterBar(ColorScheme scheme) {
    final hasType = _type != null;
    final typeLabel = hasType ? _typeLabel(_type) : '类型';
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          children: [
            FilterChip(
              key: const Key('search_quick_type'),
              avatar: Icon(
                Icons.swap_vert,
                size: 16,
                color: hasType ? scheme.primary : scheme.onSurfaceVariant,
              ),
              label: Text(typeLabel),
              selected: hasType,
              onSelected: (_) => _showTypeMenu(context),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_category'),
              avatar: Icon(
                Icons.label_outline,
                size: 16,
                color: _categoryId != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              label: Text(
                _categoryId != null ? _categoryName(_categoryId) ?? '分类' : '分类',
              ),
              selected: _categoryId != null,
              onSelected: (_) => _pickCategory(),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_account'),
              avatar: Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: _accountId != null
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              label: Text(
                _accountId != null ? _accountName(_accountId) ?? '资产账户' : '资产账户',
              ),
              selected: _accountId != null,
              onSelected: (_) => _pickAccount(),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_date'),
              avatar: Icon(
                Icons.date_range,
                size: 16,
                color: _range != null ? scheme.primary : scheme.onSurfaceVariant,
              ),
              label: Text(_range?.label ?? '日期'),
              selected: _range != null,
              onSelected: (_) => _pickRange(),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_this_week'),
              label: const Text('本周'),
              selected: _isQuickRange('week'),
              onSelected: (_) => _setQuickRange('week'),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_this_month'),
              label: const Text('本月'),
              selected: _isQuickRange('month'),
              onSelected: (_) => _setQuickRange('month'),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const Key('search_quick_last_month'),
              label: const Text('上月'),
              selected: _isQuickRange('lastMonth'),
              onSelected: (_) => _setQuickRange('lastMonth'),
            ),
            const SizedBox(width: 4),
            ActionChip(
              key: const Key('search_more_filters'),
              avatar: Icon(
                Icons.tune,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              label: const Text('更多'),
              onPressed: _openFilterSheet,
            ),
            if (_hasFilters) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: _clearFilters,
                child: const Text('清除'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTypeMenu(BuildContext context) async {
    final result = await showGlassSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in const [
              ('', '全部类型'),
              ('out', '支出'),
              ('in', '收入'),
              ('transfer', '转账'),
            ])
              ListTile(
                title: Text(opt.$2),
                trailing: (opt.$1.isEmpty ? null : opt.$1) == _type
                    ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, opt.$1),
              ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    _setType(result.isEmpty ? null : result);
  }

  // -------------------------------------------------------- keyword chips

  Widget _keywordChips(ColorScheme scheme) {
    final chips = <Widget>[];
    for (final k in _keywords) {
      chips.add(
        Chip(
          key: ValueKey('kw_$k'),
          visualDensity: VisualDensity.compact,
          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
          label: Text(k),
        ),
      );
    }
    if (_type != null) {
      chips.add(InputChip(
        label: Text('类型: ${_typeLabel(_type)}'),
        onDeleted: () => _setType(null),
      ));
    }
    if (_categoryId != null) {
      chips.add(InputChip(
        label: Text('分类: ${_categoryName(_categoryId) ?? ''}'),
        onDeleted: () {
          setState(() => _categoryId = null);
          _runSearch();
        },
      ));
    }
    if (_accountId != null) {
      chips.add(InputChip(
        label: Text('资产账户: ${_accountName(_accountId) ?? ''}'),
        onDeleted: () {
          setState(() => _accountId = null);
          _runSearch();
        },
      ));
    }
    if (_range != null) {
      chips.add(InputChip(
        label: Text('日期: ${_range!.label}'),
        onDeleted: () {
          setState(() => _range = null);
          _runSearch();
        },
      ));
    }
    if (_keywords.isEmpty && chips.isEmpty) return const SizedBox.shrink();
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => chips[i],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _buildBody(ColorScheme scheme, bool hide) {
    if (_error != null) {
      return CentliErrorState(
        error: _error,
        onRetry: () => _runSearch(),
      );
    }
    if (!_hasText && !_hasFilters) {
      return CentliEmptyState(
        icon: Icons.search,
        title: '搜索账单',
        message: '输入备注 / 商户 / 金额，多个关键词用空格分开；'
            '也可以用上面的分类、资产账户、日期快捷筛选。',
      );
    }
    if (_loading && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _results ?? const <Transaction>[];
    if (rows.isEmpty) {
      return CentliEmptyState(
        icon: Icons.search_off_outlined,
        title: '无匹配账单',
        message: _keywords.length > 1
            ? '同时满足 ${_keywords.map((k) => '「$k」').join('、')} 的账单不存在，试试减少关键词。'
            : '试试换个关键词，或放宽类型 / 分类 / 资产账户 / 日期筛选。',
        action: _hasFilters
            ? OutlinedButton(
                onPressed: _clearFilters,
                child: const Text('清除筛选'),
              )
            : null,
      );
    }
    final base =
        ref.watch(currentLedgerProvider).valueOrNull?.baseCurrency ?? 'CNY';
    final totals = _resultTotals(rows, base);
    return Column(
      children: [
        if (_truncated)
          Material(
            color: scheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '结果已截断（仅显示最新 $_searchLimit 条），请缩小关键词或加筛选。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                '共 ${rows.length}${_truncated ? '+' : ''} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              if (_keywords.any((k) =>
                  const {'支出', '收入', '转账'}.contains(k)) &&
                  _type == null)
                TextButton(
                  key: const Key('search_promote_type'),
                  onPressed: () => _commitQuickType(_keywords.firstWhere(
                    (k) => const {'支出', '收入', '转账'}.contains(k),
                  )),
                  child: const Text('把类型词当作筛选'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '收入 ${hide ? '****' : formatMinor(totals.ccy, totals.incomeMinor)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CentliTheme.incomeGreen,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Expanded(
                child: Text(
                  '支出 ${hide ? '****' : formatMinor(totals.ccy, totals.expenseMinor)}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CentliTheme.expenseRed,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TxnGroupedList(
            txns: rows,
            hide: hide,
            highlight: _keywords,
            padding: const EdgeInsets.only(bottom: 24),
          ),
        ),
      ],
    );
  }
}

class _SearchFilters {
  const _SearchFilters({
    this.type,
    this.categoryId,
    this.accountId,
    this.range,
  });

  final String? type;
  final String? categoryId;
  final String? accountId;
  final DateRangeWindow? range;
}

/// Combined filter sheet (the quick chips cover the common paths; this keeps
/// every filter in one place for power users).
class _SearchFilterSheet extends StatefulWidget {
  const _SearchFilterSheet({
    required this.initial,
    required this.accounts,
    required this.outCats,
    required this.inCats,
  });

  final _SearchFilters initial;
  final List<Account> accounts;
  final List<Category> outCats;
  final List<Category> inCats;

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late String? _type = widget.initial.type;
  late String? _categoryId = widget.initial.categoryId;
  late String? _accountId = widget.initial.accountId;
  late DateRangeWindow? _range = widget.initial.range;

  List<Category> get _catsForType {
    if (_type == 'in') return widget.inCats;
    if (_type == 'out') return widget.outCats;
    return [...widget.outCats, ...widget.inCats];
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '筛选条件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: CentliSpacing.section),
              Text('类型', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: CentliSpacing.item),
              Wrap(
                spacing: 8,
                children: [
                  for (final opt in <(String?, String)>[
                    (null, '全部'),
                    ('out', '支出'),
                    ('in', '收入'),
                    ('transfer', '转账'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: _type == opt.$1,
                      onSelected: (_) {
                        setState(() {
                          _type = opt.$1;
                          if (_categoryId != null && _type != null && _type != 'transfer') {
                            final ok = _catsForType.any((c) => c.id == _categoryId);
                            if (!ok) _categoryId = null;
                          }
                          if (_type == 'transfer') _categoryId = null;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              Text('分类', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: CentliSpacing.item),
              DropdownButtonFormField<String?>(
                key: ValueKey('cat_${_type}_$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部分类'),
                  ),
                  for (final c in _catsForType)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                ],
                onChanged: _type == 'transfer'
                    ? null
                    : (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              Text('资产账户', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: CentliSpacing.item),
              DropdownButtonFormField<String?>(
                key: ValueKey('acc_$_accountId'),
                initialValue: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部资产账户'),
                  ),
                  for (final a in widget.accounts)
                    DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text(
                        a.archived == 1
                            ? '${a.name} (${a.currency}) · 已归档'
                            : '${a.name} (${a.currency})',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              Text('日期范围', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: CentliSpacing.item),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_range?.label ?? '不限日期'),
                subtitle: const Text('复用首页 / 统计的日期选择器'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_range != null)
                      IconButton(
                        tooltip: '清除',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _range = null),
                      ),
                    IconButton(
                      tooltip: '选择',
                      icon: const Icon(Icons.date_range),
                      onPressed: () async {
                        final picked = await showCentliDateRangeSheet(
                          context,
                          current: _range ??
                              DateRangeWindow.lastDays(days: 30),
                        );
                        if (picked != null && mounted) {
                          setState(() => _range = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _type = null;
                          _categoryId = null;
                          _accountId = null;
                          _range = null;
                        });
                      },
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _SearchFilters(
                            type: _type,
                            categoryId: _categoryId,
                            accountId: _accountId,
                            range: _range,
                          ),
                        );
                      },
                      child: const Text('应用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
