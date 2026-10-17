import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/utils/money.dart';
import '../../core/utils/amount_expr.dart';
import '../../core/widgets/centli_icon.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import 'category_picker_sheet.dart';

Future<void> showBookkeepingSheet(
  BuildContext context, {
  Transaction? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => BookkeepingSheet(
      existing: existing,
    ),
  );
}

class BookkeepingSheet extends ConsumerStatefulWidget {
  const BookkeepingSheet({
    super.key,
    this.existing,
  });

  final Transaction? existing;

@override
  ConsumerState<BookkeepingSheet> createState() => _BookkeepingSheetState();
}

class _BookkeepingSheetState extends ConsumerState<BookkeepingSheet> {
  String _type = 'out';
  String _amountText = '0';
  String _toAmountText = '0';
  String? _fxRateText;

  /// When cross-ccy: user enters to_amount (true) or fx_rate (false).
  bool _useToAmount = true;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  final _noteCtrl = TextEditingController();
  List<String> _tags = [];
List<Account> _accounts = [];
  List<Category> _categories = [];
  String? _ledgerId;
  bool _loading = true;
  bool _saving = false;
  DateTime _happenAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }


  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null) {
      setState(() => _loading = false);
      return;
    }
    var accounts = await db.loadActiveAccounts(ledgerId);
    final existing = widget.existing;
    if (existing != null) {
      final need = <String>{
        existing.accountId,
        if (existing.toAccountId != null) existing.toAccountId!,
      };
      final have = {for (final a in accounts) a.id};
      for (final id in need) {
        if (!have.contains(id)) {
          final a = await db.getAccount(id);
          if (a != null) accounts = [...accounts, a];
        }
      }
    }
    final cats = await db.loadCategories(
      ledgerId,
      _type == 'in' ? 'in' : 'out',
    );
    if (!mounted) return;
    setState(() {
      _ledgerId = ledgerId;
      _accounts = accounts;
      if (existing != null) {
        _type = existing.type;
        _amountText = fromMinor(
          existing.currency,
          existing.amountMinor,
        ).toStringAsFixed(currencyDecimals[existing.currency] ?? 2);
        // trim trailing zeros from whole amounts
        if (_amountText.contains('.')) {
          _amountText = _amountText.replaceFirst(RegExp(r'\.?0+$'), '');
          if (_amountText.isEmpty) _amountText = '0';
        }
        _accountId = existing.accountId;
        _toAccountId = existing.toAccountId;
        _categoryId = existing.categoryId;
            _noteCtrl.text = existing.note ?? '';
        _tags = List<String>.from(decodeTxnTags(existing.tags));
        _happenAt = DateTime.fromMillisecondsSinceEpoch(
          existing.happenAt,
          isUtc: true,
        ).toLocal();
        if (existing.toAmountMinor != null) {
          final toAcc = accounts.where((a) => a.id == existing.toAccountId);
          final toCcy = toAcc.isNotEmpty
              ? toAcc.first.currency
              : existing.currency;
          _toAmountText = fromMinor(
            toCcy,
            existing.toAmountMinor!,
          ).toStringAsFixed(currencyDecimals[toCcy] ?? 2);
        }
        if (existing.fxRate != null) {
          _fxRateText = existing.fxRate.toString();
        }
      } else {
        _accountId = accounts.isNotEmpty ? accounts.first.id : null;
        _toAccountId = accounts.length > 1 ? accounts[1].id : null;
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
      _categories = cats;
      // reload cats for existing type (may differ from default out)
      _loading = false;
    });
    if (existing != null && existing.type != 'out') {
      await _reloadCategories();
      if (existing.categoryId != null) {
        setState(() => _categoryId = existing.categoryId);
      }
    }
  }

  Future<void> _reloadCategories({bool resetSelection = false}) async {
    if (_ledgerId == null || _type == 'transfer') return;
    final db = ref.read(databaseProvider);
    final cats = await db.loadCategories(
      _ledgerId!,
      _type == 'in' ? 'in' : 'out',
    );
    setState(() {
      _categories = cats;
      if (resetSelection ||
          _categoryId == null ||
          !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
  }

  Account? _accountById(String? id) {
    if (id == null || _accounts.isEmpty) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String get _currency {
    return _accountById(_accountId)?.currency ?? 'CNY';
  }

  String get _toCurrency {
    return _accountById(_toAccountId)?.currency ?? _currency;
  }

  bool get _isCrossCurrency {
    if (_type != 'transfer') return false;
    final from = _accountById(_accountId);
    final to = _accountById(_toAccountId);
    if (from == null || to == null) return false;
    return from.currency != to.currency;
  }

  int get _maxDecimals => currencyDecimals[_currency] ?? 2;



  void _onKey(String key) {
    setState(() {
      if (key == 'AC') {
        _amountText = '0';
      } else if (key == '=') {
        final v = _evalAmount(_amountText);
        if (v == null) return;
        final decimals = _maxDecimals;
        var collapsed = v.toStringAsFixed(decimals);
        if (decimals > 0) {
          collapsed = collapsed.replaceFirst(RegExp(r'\.?0+$'), '');
          if (collapsed.isEmpty) collapsed = '0';
        }
        _amountText = collapsed;
      } else if (key == '+' ||
          key == '-' ||
          key == '×' ||
          key == '÷' ||
          key == '*' ||
          key == '/') {
        _amountText = applyAmountOperator(_amountText, key);
      } else {
        _amountText = applyAmountKey(_amountText, key, _maxDecimals);
      }
    });
  }

  double? _evalAmount(String expr) => evalAmountExpr(expr);

  bool get _amountHasOperator => amountExprHasOperator(_amountText);

    Future<void> _promptCrossCurrency({bool keepOpen = false}) async {
    final fromCcy = _currency;
    final toCcy = _toCurrency;
    final major = _evalAmount(_amountText) ?? 0;
    final toCtrl = TextEditingController(
      text: _toAmountText == '0' ? '' : _toAmountText,
    );
    final rateCtrl = TextEditingController(text: _fxRateText ?? '');
    var useTo = _useToAmount;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('\u8de8\u5e01\u8f6c\u8d26 ($fromCcy \u2192 $toCcy)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '\u8f6c\u51fa ${formatMinor(fromCcy, toMinor(fromCcy, major))}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('\u5bf9\u65b9\u91d1\u989d'),
                      ),
                      ButtonSegment(value: false, label: Text('\u6c47\u7387')),
                    ],
                    selected: {useTo},
                    onSelectionChanged: (s) => setLocal(() => useTo = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (useTo)
                    TextField(
                      controller: toCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '\u8f6c\u5165\u91d1\u989d ($toCcy)',
                        border: const OutlineInputBorder(),
                      ),
                    )
                  else
                    TextField(
                      controller: rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '1 $fromCcy = ? $toCcy',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('\u53d6\u6d88'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('\u786e\u5b9a'),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      if (ok != true) return;
      setState(() {
        _useToAmount = useTo;
        if (useTo) {
          _toAmountText = toCtrl.text.trim().isEmpty ? '0' : toCtrl.text.trim();
          _fxRateText = null;
        } else {
          _fxRateText = rateCtrl.text.trim();
          _toAmountText = '0';
        }
      });
      await _save(skipCrossPrompt: true, keepOpen: keepOpen);
    } finally {
      toCtrl.dispose();
      rateCtrl.dispose();
    }
  }

  Future<void> _save({
    bool skipCrossPrompt = false,
    bool keepOpen = false,
  }) async {
    final major = _evalAmount(_amountText);
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u91d1\u989d')),
      );
      return;
    }
    // Collapse expression to evaluated major so subsequent FX math uses a plain number.
    if (_amountHasOperator) {
      final decimals = _maxDecimals;
      var collapsed = major.toStringAsFixed(decimals);
      if (decimals > 0) {
        collapsed = collapsed.replaceFirst(RegExp(r'\.?0+$'), '');
        if (collapsed.isEmpty) collapsed = '0';
      }
      _amountText = collapsed;
    }
    if (_ledgerId == null || _accountId == null) return;

    if (_type == 'transfer') {
      if (_toAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\u8bf7\u9009\u62e9\u8f6c\u5165\u8d26\u6237'),
          ),
        );
        return;
      }
      if (_toAccountId == _accountId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u8f6c\u51fa\u4e0e\u8f6c\u5165\u8d26\u6237\u4e0d\u80fd\u76f8\u540c',
            ),
          ),
        );
        return;
      }
      if (_isCrossCurrency && !skipCrossPrompt) {
        final hasTo = (double.tryParse(_toAmountText) ?? 0) > 0;
        final hasRate = (double.tryParse(_fxRateText ?? '') ?? 0) > 0;
        if (!hasTo && !hasRate) {
          await _promptCrossCurrency(keepOpen: keepOpen);
          return;
        }
      }
    } else if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u9009\u62e9\u5206\u7c7b')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final amountMinor = toMinor(_currency, major);
      double? fxRate;
      int? toAmountMinor;

      if (_type == 'transfer' && _isCrossCurrency) {
        if (_useToAmount || (double.tryParse(_toAmountText) ?? 0) > 0) {
          final toMajor = double.tryParse(_toAmountText) ?? 0;
          if (toMajor <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u8bf7\u8f93\u5165\u5bf9\u65b9\u91d1\u989d'),
              ),
            );
            return;
          }
          toAmountMinor = toMinor(_toCurrency, toMajor);
          fxRate = toMajor / major; // 1 from = rate to
        } else {
          fxRate = double.tryParse(_fxRateText ?? '');
          if (fxRate == null || fxRate <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u8bf7\u8f93\u5165\u6709\u6548\u6c47\u7387'),
              ),
            );
            return;
          }
          toAmountMinor = toMinor(_toCurrency, major * fxRate);
        }
      } else if (_type == 'transfer') {
        toAmountMinor = amountMinor;
      }

      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      // Panel no longer edits member; preserve existing value on update.
      final member = widget.existing?.member;
      final toAcc = _type == 'transfer' ? _toAccountId : null;
      final cat = _type == 'transfer' ? null : _categoryId;
      if (widget.existing != null) {
        await db.updateManualTransaction(
          id: widget.existing!.id,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
            member: member,
          note: note,
          tags: _tags,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      } else {
        await db.insertManualTransaction(
          ledgerId: _ledgerId!,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
            member: member,
          note: note,
          tags: _tags,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      }
      if (!mounted) return;
      if (keepOpen && widget.existing == null) {
        // 再记一笔：落库后保留面板，清空金额/备注，时间刷新为现在。
        setState(() {
          _amountText = '0';
          _toAmountText = '0';
          _fxRateText = null;
          _noteCtrl.clear();
              _happenAt = DateTime.now();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存，可继续记账')));
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _happenAtLabel {
    final now = DateTime.now();
    final sameDay =
        _happenAt.year == now.year &&
        _happenAt.month == now.month &&
        _happenAt.day == now.day;
    if (sameDay) {
      return DateFormat('HH:mm').format(_happenAt);
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(_happenAt);
  }

  Future<void> _pickHappenAt() async {
    final today = DateTime.now();
    final last = DateTime(today.year, today.month, today.day);
    var initial = _happenAt;
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(DateTime(2020, 1, 1))) {
      initial = DateTime(2020, 1, 1);
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: last,
      locale: const Locale('zh', 'CN'),
      helpText: '选择日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_happenAt),
      helpText: '选择时间',
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('zh', 'CN'),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (time == null || !mounted) return;
    setState(() {
      _happenAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Category? _categoryById(String? id) {
    if (id == null || _categories.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _categories,
      selectedId: _categoryId,
    );
    if (!mounted) return;
    if (id != null) {
      setState(() => _categoryId = id);
      return;
    }
    // Dismiss or 管理: refresh tree, keep selection when still valid.
    await _reloadCategories();
  }

  Future<void> _pickAccount({required bool toAccount}) async {
    final current = toAccount ? _toAccountId : _accountId;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _AccountPickerSheet(
          accounts: _accounts,
          selectedId: current,
          title: toAccount
              ? '\u9009\u62e9\u8f6c\u5165\u8d26\u6237'
              : '\u9009\u62e9\u8d26\u6237',
        );
      },
    );
    if (id == null || !mounted) return;
    setState(() {
      if (toAccount) {
        _toAccountId = id;
      } else {
        _accountId = id;
      }
    });
  }

  bool get _isDirty {
    final amt = _evalAmount(_amountText) ?? 0;
    return amt > 0 || _noteCtrl.text.trim().isNotEmpty || _tags.isNotEmpty;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty) return true;
    final major = _evalAmount(_amountText) ?? 0;
    final label = major > 0
        ? formatMinor(_currency, toMinor(_currency, major))
        : (_noteCtrl.text.trim().isNotEmpty ? '备注' : '标签');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃这笔记账？'),
        content: Text('已输入 $label，确定放弃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续记账'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editSheetTags() async {
    final current = List<String>.from(_tags);
    final ctrl = TextEditingController();
    final suggestions = _ledgerId == null
        ? <String>[]
        : await ref.read(databaseProvider).listDistinctTags(_ledgerId!);
    if (!mounted) return;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void addTag(String raw) {
              var t = raw.trim();
              if (t.isEmpty) return;
              if (t.length > 12) t = t.substring(0, 12);
              if (current.contains(t) || current.length >= 5) return;
              setLocal(() => current.add(t));
              ctrl.clear();
            }

            return AlertDialog(
              title: const Text('标签'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final t in current)
                          InputChip(
                            label: Text(t),
                            onDeleted: () => setLocal(() => current.remove(t)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: '新标签',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: addTag,
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final s in suggestions.take(12))
                            ActionChip(
                              label: Text(s),
                              onPressed: () => addTag(s),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, List<String>.from(current)),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (result != null) setState(() => _tags = result);
  }



  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final chipBorder = CentliTheme.chipBorder(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfNeeded() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _loading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final segs = <(String, String)>[
                                ('out', '支出'),
                                ('in', '收入'),
                                if (_type == 'refund') ('refund', '退款'),
                                ('transfer', '转账'),
                              ];
                              return Padding(
                                key: const Key('bk_type_switcher'),
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Row(
                                  children: [
                                    for (final entry in segs)
                                      Expanded(
                                        child: InkWell(
                                          key: Key('bk_type_seg_${entry.$1}'),
                                          onTap: () async {
                                            setState(() => _type = entry.$1);
                                            if (entry.$1 == 'transfer') {
                                              setState(() => _categoryId = null);
                                            } else {
                                              await _reloadCategories(
                                                resetSelection: true,
                                              );
                                            }
                                          },
                                          child: Column(
                                            children: [
                                              Text(
                                                entry.$2,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight: _type == entry.$1
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: _type == entry.$1
                                                          ? scheme.primary
                                                          : scheme.onSurfaceVariant,
                                                    ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                height: 2,
                                                color: _type == entry.$1
                                                    ? scheme.primary
                                                    : Colors.transparent,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Finch rhythm: compact amount (right), chips flush under.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 18, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_amountHasOperator)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      _amountText,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            height: 1.0,
                                          ),
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      formatMinor(
                                        _currency,
                                        toMinor(
                                          _currency,
                                          _evalAmount(_amountText) ?? 0,
                                        ),
                                        hide: hide,
                                      ),
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.8,
                                            height: 1.0,
                                            fontSize: 32,
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _currency,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontSize: 13,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Chips: time / category / account / tags (single scroll row)
                          Padding(
                            key: const Key('bk_chips_row'),
                            padding: const EdgeInsets.only(left: 16),
                            child: _ChipScrollRow(
                              children: [
                                _MetaChip(
                                  icon: Icons.schedule_rounded,
                                  label: hide ? '**:**' : _happenAtLabel,
                                  onTap: _pickHappenAt,
                                ),
                                if (_type != 'transfer')
                                  Builder(
                                    builder: (context) {
                                      final cat = _categoryById(_categoryId);
                                      return _MetaChip(
                                        leading: cat == null
                                            ? null
                                            : CentliIconChip(
                                                name: cat.name,
                                                kind: cat.kind,
                                                iconKey: cat.icon,
                                                size: 16,
                                              ),
                                        icon: cat == null
                                            ? Icons.category_outlined
                                            : null,
                                        label: cat?.name ?? '分类',
                                        onTap: _pickCategory,
                                      );
                                    },
                                  ),
                                if (_type != 'transfer')
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_accountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 16,
                                              ),
                                        icon: acc == null
                                            ? Icons
                                                .account_balance_wallet_outlined
                                            : null,
                                        label: acc?.name ?? '账户',
                                        onTap: () =>
                                            _pickAccount(toAccount: false),
                                      );
                                    },
                                  )
                                else ...[
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_accountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 16,
                                              ),
                                        icon: Icons.south_west_rounded,
                                        label: acc == null
                                            ? '转出'
                                            : '转出 · ${acc.name}',
                                        onTap: () =>
                                            _pickAccount(toAccount: false),
                                      );
                                    },
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_toAccountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 16,
                                              ),
                                        icon: Icons.north_east_rounded,
                                        label: acc == null
                                            ? '转入'
                                            : '转入 · ${acc.name}',
                                        onTap: () =>
                                            _pickAccount(toAccount: true),
                                      );
                                    },
                                  ),
                                ],
                                _MetaChip(
                                  icon: Icons.sell_outlined,
                                  label: _tags.isEmpty
                                      ? '标签'
                                      : (hide
                                          ? '****'
                                          : _tags.take(2).join(' · ')),
                                  onTap: _editSheetTags,
                                ),
                              ],
                            ),
                          ),
                          if (_type == 'transfer' && _isCrossCurrency)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                              child: Text(
                                '\u8de8\u5e01\uff1a\u4fdd\u5b58\u65f6\u4f1a\u8be2\u95ee\u5bf9\u65b9\u91d1\u989d/\u6c47\u7387',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Padding(
                            key: const Key('bk_note'),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              height: 46,
                              child: TextField(
                                controller: _noteCtrl,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '\u5907\u6ce8',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  isDense: true,
                                  prefixIcon: Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  filled: true,
                                  fillColor: scheme.surface,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: chipBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: chipBorder),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: scheme.primary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  _Keypad(
                    key: const Key('bk_keypad'),
                    onKey: _onKey,
                    onSubmit: _saving ? null : () => _save(),
                    onLongSubmit: (_saving || widget.existing != null)
                        ? null
                        : () => _save(keepOpen: true),
                  ),
                  SizedBox(
                    height: safeBottom > 0 ? safeBottom : 10,
                  ),
                ],
              ),
      ),
    ),
    );
  }
}

/// Contract chip row: height 36, gap 8, horizontal scroll.
class _ChipScrollRow extends StatelessWidget {
  const _ChipScrollRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = CentliTheme.chipBorder(context);
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({
    required this.accounts,
    required this.title,
    this.selectedId,
  });

  final List<Account> accounts;
  final String title;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final a = accounts[i];
                final selected = a.id == selectedId;
                return ListTile(
                  leading: CentliIconChip(
                    name: a.name,
                    kind: 'account',
                    iconKey: a.icon,
                    size: 40,
                  ),
                  title: Text(
                    a.name,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(currencyLabel(a.currency)),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: CentliTheme.softBlue)
                      : null,
                  onTap: () => Navigator.pop(context, a.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    super.key,
    required this.onKey,
    required this.onSubmit,
    this.onLongSubmit,
  });

  final void Function(String key) onKey;
  final VoidCallback? onSubmit;
  final VoidCallback? onLongSubmit;

  static const _rows = <List<String>>[
    ['AC', '\u232b', '/', '*'],
    ['7', '8', '9', '-'],
    ['4', '5', '6', '+'],
    ['1', '2', '3', '='],
    ['0', '.', '\u2713'],
  ];

  static const _colFlex = [78, 78, 78, 86];

  Color _bg(BuildContext context, String k) {
    if (k == '\u2713') return CentliTheme.keypadConfirm(context);
    if (k == 'AC' || k == '\u232b') return CentliTheme.keypadAcBg(context);
    if (k == '+' || k == '-' || k == '*' || k == '/' || k == '=') {
      return CentliTheme.keypadOpBg(context);
    }
    return CentliTheme.keypadNumBg(context);
  }

  Color _fg(BuildContext context, String k) {
    if (k == '\u2713') return Colors.white;
    if (k == 'AC' || k == '\u232b') return CentliTheme.keypadAcFg(context);
    if (k == '+' || k == '-' || k == '*' || k == '/' || k == '=') {
      return CentliTheme.keypadOpFg(context);
    }
    return CentliTheme.keypadNumFg(context);
  }

  String _label(String k) {
    if (k == '-') return '\u2212';
    return k;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < _rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 3.5),
            _buildRow(context, _rows[r], isLast: r == _rows.length - 1),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<String> row, {
    required bool isLast,
  }) {
    if (isLast) {
      return Row(
        children: [
          Expanded(
            flex: _colFlex[0] + _colFlex[1],
            child: _keyBtn(context, '0'),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: _colFlex[2],
            child: _keyBtn(context, '.'),
          ),
          const SizedBox(width: 7),
          Expanded(
            flex: _colFlex[3],
            child: _keyBtn(context, '\u2713'),
          ),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < row.length; i++) ...[
          if (i > 0) const SizedBox(width: 7),
          Expanded(
            flex: _colFlex[i],
            child: _keyBtn(context, row[i]),
          ),
        ],
      ],
    );
  }

  Widget _keyBtn(BuildContext context, String k) {
    return SizedBox(
      height: 54,
      child: Tooltip(
        message: k == '\u2713' ? '\u957f\u6309\u518d\u8bb0\u4e00\u7b14' : '',
        child: Material(
          color: _bg(context, k),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (k == '\u2713') {
                onSubmit?.call();
              } else {
                onKey(k);
              }
            },
            onLongPress: k == '\u2713' ? onLongSubmit : null,
            child: Center(
              child: Text(
                _label(k),
                style: TextStyle(
                  fontSize: k == 'AC' ? 16 : 20,
                  fontWeight: FontWeight.w700,
                  color: _fg(context, k),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
