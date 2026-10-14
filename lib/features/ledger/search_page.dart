import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_range.dart';
import '../../core/widgets/date_range_control.dart';
import '../../core/widgets/txn_list_tile.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';

/// Bill search: keyword + filters (type / category / account / date range).
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

  /// `out` | `in` | `transfer` | null (any)
  String? _type;
  String? _categoryId;
  String? _accountId;
  DateRangeWindow? _range;

  List<Account> _accounts = const [];
  List<Category> _outCats = const [];
  List<Category> _inCats = const [];

  bool get _hasFilters =>
      _type != null ||
      _categoryId != null ||
      _accountId != null ||
      _range != null;

  int get _activeFilterCount {
    var n = 0;
    if (_type != null) n++;
    if (_categoryId != null) n++;
    if (_accountId != null) n++;
    if (_range != null) n++;
    return n;
  }

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
    final accounts = await db.loadActiveAccounts(ledger.id);
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
    setState(() {}); // refresh clear affordance
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
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = rows;
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

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return _SearchFilterSheet(
          initial: _SearchFilters(
            type: _type,
            categoryId: _categoryId,
            accountId: _accountId,
            range: _range,
          ),
          accounts: _accounts,
          outCats: _outCats,
          inCats: _inCats,
        );
      },
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

  String _typeLabel(String? t) {
    switch (t) {
      case 'out':
        return '\u652f\u51fa';
      case 'in':
        return '\u6536\u5165';
      case 'transfer':
        return '\u8f6c\u8d26';
      default:
        return '\u5168\u90e8';
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
      if (a.id == id) return a.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText:
                '\u5907\u6ce8 / \u5546\u6237 / \u91d1\u989d',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _runSearch,
        ),
        actions: [
          IconButton(
            tooltip: '\u7b5b\u9009',
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.tune),
            ),
            onPressed: _openFilterSheet,
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: '\u6e05\u7a7a',
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
          if (_hasFilters) _buildFilterChips(scheme),
          Expanded(child: _buildBody(scheme, hide)),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme scheme) {
    final chips = <Widget>[];
    if (_type != null) {
      chips.add(
        InputChip(
          label: Text('\u7c7b\u578b: ${_typeLabel(_type)}'),
          onDeleted: () {
            setState(() => _type = null);
            _runSearch();
          },
        ),
      );
    }
    if (_categoryId != null) {
      chips.add(
        InputChip(
          label: Text(
            '\u5206\u7c7b: ${_categoryName(_categoryId) ?? ''}',
          ),
          onDeleted: () {
            setState(() => _categoryId = null);
            _runSearch();
          },
        ),
      );
    }
    if (_accountId != null) {
      chips.add(
        InputChip(
          label: Text(
            '\u8d26\u6237: ${_accountName(_accountId) ?? ''}',
          ),
          onDeleted: () {
            setState(() => _accountId = null);
            _runSearch();
          },
        ),
      );
    }
    if (_range != null) {
      chips.add(
        InputChip(
          label: Text('\u65e5\u671f: ${_range!.label}'),
          onDeleted: () {
            setState(() => _range = null);
            _runSearch();
          },
        ),
      );
    }
    chips.add(
      ActionChip(
        label: const Text('\u6e05\u9664\u7b5b\u9009'),
        onPressed: _clearFilters,
      ),
    );

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, bool hide) {
    if (_error != null) {
      return Center(child: Text('\u641c\u7d22\u5931\u8d25: $_error'));
    }
    if (_query.isEmpty && !_hasFilters) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              Text(
                '\u641c\u7d22\u8d26\u5355',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '\u6309\u5907\u6ce8\u3001\u5546\u6237\u6216\u91d1\u989d\u5173\u952e\u8bcd\u67e5\u8be2\uff1b'
                '\u4e5f\u53ef\u7528\u7c7b\u578b / \u5206\u7c7b / \u8d26\u6237 / \u65e5\u671f\u7b5b\u9009',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openFilterSheet,
                icon: const Icon(Icons.tune),
                label: const Text('\u6253\u5f00\u7b5b\u9009'),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading && _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _results ?? const <Transaction>[];
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '\u65e0\u5339\u914d\u8d26\u5355',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        return TxnListTile(txn: rows[i], hide: hide);
      },
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
    // Any type: show both lists
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
                '\u7b5b\u9009\u6761\u4ef6',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '\u7c7b\u578b',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final opt in <(String?, String)>[
                    (null, '\u5168\u90e8'),
                    ('out', '\u652f\u51fa'),
                    ('in', '\u6536\u5165'),
                    ('transfer', '\u8f6c\u8d26'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: _type == opt.$1,
                      onSelected: (_) {
                        setState(() {
                          _type = opt.$1;
                          // Drop category if it no longer belongs to the kind.
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
              const SizedBox(height: 16),
              Text(
                '\u5206\u7c7b',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: ValueKey('cat_${_type}_$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('\u5168\u90e8\u5206\u7c7b'),
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
              const SizedBox(height: 16),
              Text(
                '\u8d26\u6237',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: ValueKey('acc_$_accountId'),
                initialValue: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('\u5168\u90e8\u8d26\u6237'),
                  ),
                  for (final a in widget.accounts)
                    DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text('${a.name} (${a.currency})'),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 16),
              Text(
                '\u65e5\u671f\u8303\u56f4',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _range?.label ?? '\u4e0d\u9650\u65e5\u671f',
                ),
                subtitle: const Text(
                  '\u590d\u7528\u9996\u9875/\u7edf\u8ba1\u7684\u65e5\u671f\u9009\u62e9\u5668',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_range != null)
                      IconButton(
                        tooltip: '\u6e05\u9664',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _range = null),
                      ),
                    IconButton(
                      tooltip: '\u9009\u62e9',
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
              const SizedBox(height: 12),
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
                      child: const Text('\u91cd\u7f6e'),
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
                      child: const Text('\u5e94\u7528'),
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
