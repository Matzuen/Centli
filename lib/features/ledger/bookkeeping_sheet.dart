import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/constants/pref_keys.dart';
import '../../core/utils/money.dart';
import '../../core/utils/amount_expr.dart';
import '../../core/widgets/centli_icon.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import 'account_picker_sheet.dart';
import 'category_picker_sheet.dart';
import 'ledger_detail_page.dart' show showTagEditorDialog;
import 'sub_transaction_sheet.dart';
import '../../core/widgets/glass.dart';

/// Set by the bill-detail page when 金额 was edited but not yet saved through
/// 保存. The bookkeeping sheet applies it on next open (it only shows on
/// phones; on desktop save now or enter the amount in the sheet).
int? pendingDetailAmountMinor;

/// Opens the manual panel.
///
/// - [existing]: edit that bill in place.
/// - [template]: start a NEW bill pre-filled from [template] (资产账户 / 分类 /
///   标签 / 备注，金额清零) — 「照着这笔再记一笔」.
/// - [initialNote]: pre-fill only the note (used when the note recalls a
///   category before the panel opens).
Future<bool?> showBookkeepingSheet(
  BuildContext context, {
  Transaction? existing,
  Transaction? template,
  String? initialNote,
  DateTime? initialHappenAt,
}) {
  // Detail-page rows collect edits and persist them on 保存; the sheet saves
  // everything when closed via ✓. Drop any unconsumed detail amount so the
  // sheet's visible (possibly stale) amount is not silently overridden.
  pendingDetailAmountMinor = null;
  return showGlassSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => BookkeepingSheet(
      existing: existing,
      template: template,
      initialNote: initialNote,
      initialHappenAt: initialHappenAt,
    ),
  );
}

class BookkeepingSheet extends ConsumerStatefulWidget {
  const BookkeepingSheet({
    super.key,
    this.existing,
    this.template,
    this.initialNote,
    this.initialHappenAt,
  });

  final Transaction? existing;

  /// Bill to copy when creating a new one (account / category / tags / note).
  final Transaction? template;

  /// Note to pre-fill for a 记一笔 (category is recalled from it).
  final String? initialNote;

  final DateTime? initialHappenAt;

@override
  ConsumerState<BookkeepingSheet> createState() => _BookkeepingSheetState();
}

class _BookkeepingSheetState extends ConsumerState<BookkeepingSheet> {
  String _type = 'out';

  /// 分类 kind：与交易类型对齐（含 transfer）。
  String get _categoryKind => switch (_type) {
        'in' => 'in',
        'transfer' => 'transfer',
        _ => 'out',
      };
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
  /// Sub-transactions queued while composing a new bill (「附加」).
  List<DraftSubTxn> _draftSubs = [];
  List<Account> _accounts = [];
  List<AssetType> _assetTypes = [];
  List<Category> _categories = [];
  String? _ledgerId;
  bool _loading = true;
  bool _saving = false;
  late DateTime _happenAt;
  LastBookkeepingChoice? _lastChoice;
  bool _rememberCategoryAccount = true;
  bool _rememberCategoryNote = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final seed = widget.initialHappenAt;
    if (existing != null) {
      // Filled in _load from existing.happenAt; placeholder until then.
      _happenAt = DateTime.now();
    } else if (seed != null) {
      final now = DateTime.now();
      _happenAt = DateTime(
        seed.year,
        seed.month,
        seed.day,
        now.hour,
        now.minute,
      );
    } else {
      _happenAt = DateTime.now();
    }
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
    final assetTypes = await db.loadAssetTypes(ledgerId);
    final rememberAccRaw = await db.getSetting(PrefKeys.rememberCategoryAccount);
    final rememberNoteRaw = await db.getSetting(PrefKeys.rememberCategoryNote);
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
    final template = widget.template;
    final last = existing == null && template == null
        ? await db.loadLastBookkeeping()
        : null;
    _lastChoice = last;
    if (last != null && _type == 'out') {
      _type = last.type;
    }
    if (_type == 'transfer') {
      await db.ensureDefaultTransferCategory(ledgerId);
    }
    var cats = await db.loadCategories(ledgerId, _categoryKind);
    // 备注 → 上次分类（手动记账同样生效）。
    String? recalledCategory;
    if (existing == null && template == null) {
      recalledCategory = await db.recallCategoryForNote(widget.initialNote);
    }
    if (!mounted) return;
    setState(() {
      _ledgerId = ledgerId;
      _accounts = accounts;
      _assetTypes = assetTypes;
      _rememberCategoryAccount = prefBool(rememberAccRaw);
      _rememberCategoryNote = prefBool(rememberNoteRaw);
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
        final pendingAmount = pendingDetailAmountMinor;
        pendingDetailAmountMinor = null;
        _accountId = existing.accountId;
        _toAccountId = existing.toAccountId;
        _categoryId = existing.categoryId;
        if (pendingAmount != null && pendingAmount > 0) {
          _amountText = fromMinor(existing.currency, pendingAmount)
              .toStringAsFixed(currencyDecimals[existing.currency] ?? 2);
          if (_amountText.contains('.')) {
            _amountText = _amountText.replaceFirst(RegExp(r'\.?0+$'), '');
            if (_amountText.isEmpty) _amountText = '0';
          }
        }
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
      } else if (template != null) {
        // 照着这笔再记一笔：复制分类 / 资产账户 / 标签 / 备注，金额留空。
        _type = template.type;
        _accountId = template.accountId;
        _toAccountId = template.toAccountId;
        _categoryId = template.categoryId;
        _noteCtrl.text = template.note ?? '';
        _tags = List<String>.from(decodeTxnTags(template.tags));
        _happenAt = DateTime.now();
      } else {
        final rememberedAcc = last?.accountId != null &&
                accounts.any((a) => a.id == last!.accountId)
            ? last!.accountId
            : null;
        _accountId =
            rememberedAcc ?? (accounts.isNotEmpty ? accounts.first.id : null);
        _toAccountId = accounts.length > 1 ? accounts[1].id : null;
        final preferredCat = recalledCategory ??
            last?.categoryByType[_categoryKind] ??
            last?.categoryId;
        _categoryId = preferredCat != null &&
                cats.any((c) => c.id == preferredCat)
            ? preferredCat
            : (cats.isNotEmpty ? cats.first.id : null);
        _noteCtrl.text = widget.initialNote ?? '';
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
    } else if (template != null && template.type != 'out') {
      // 模板是收入 / 转账时，分类列表要换成对应方向。
      if (template.type == 'transfer') {
        await db.ensureDefaultTransferCategory(ledgerId);
      }
      cats = await db.loadCategories(
        ledgerId,
        template.type == 'in'
            ? 'in'
            : template.type == 'transfer'
                ? 'transfer'
                : 'out',
      );
      if (mounted) {
        setState(() {
          _categories = cats;
          final keep = template.categoryId;
          _categoryId = keep != null && cats.any((c) => c.id == keep)
              ? keep
              : (cats.isNotEmpty ? cats.first.id : null);
        });
      }
    } else if (existing == null &&
        template == null &&
        _categoryId != null &&
        (widget.initialNote == null || widget.initialNote!.trim().isEmpty)) {
      // 打开面板时已带上次分类：同步回填该分类上次备注 / 账户。
      await _applyCategoryMemory(_categoryId!);
    }
  }

  Future<void> _reloadCategories({bool resetSelection = false}) async {
    if (_ledgerId == null) return;
    final db = ref.read(databaseProvider);
    if (_type == 'transfer') {
      await db.ensureDefaultTransferCategory(_ledgerId!);
    }
    final cats = await db.loadCategories(_ledgerId!, _categoryKind);
    setState(() {
      _categories = cats;
      if (resetSelection ||
          _categoryId == null ||
          !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
    if (resetSelection && _categoryId != null && _type != 'transfer') {
      await _applyCategoryMemory(_categoryId!);
    }
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

    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return CentliGlassDialog(
              title: Text('\u8de8\u5e01\u8f6c\u8d26 ($fromCcy \u2192 $toCcy)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '\u8f6c\u51fa ${formatMinor(fromCcy, toMinor(fromCcy, major))}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: CentliSpacing.section),
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
                  const SizedBox(height: CentliSpacing.section),
                  if (useTo)
                    TextField(
                      controller: toCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '\u8f6c\u5165\u91d1\u989d ($toCcy)',
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
      showGlassSnackBar(context, '\u8bf7\u8f93\u5165\u91d1\u989d');
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
        showGlassSnackBar(context, '\u8bf7\u9009\u62e9\u8f6c\u5165\u8d44\u4ea7\u8d26\u6237');
        return;
      }
      if (_toAccountId == _accountId) {
        showGlassSnackBar(context, '\u8f6c\u51fa\u4e0e\u8f6c\u5165\u8d44\u4ea7\u8d26\u6237\u4e0d\u80fd\u76f8\u540c',);
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
    }
    if (_categoryId == null) {
      showGlassSnackBar(context, '\u8bf7\u9009\u62e9\u5206\u7c7b');
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
            showGlassSnackBar(context, '\u8bf7\u8f93\u5165\u5bf9\u65b9\u91d1\u989d');
            return;
          }
          toAmountMinor = toMinor(_toCurrency, toMajor);
          fxRate = toMajor / major; // 1 from = rate to
        } else {
          fxRate = double.tryParse(_fxRateText ?? '');
          if (fxRate == null || fxRate <= 0) {
            showGlassSnackBar(context, '\u8bf7\u8f93\u5165\u6709\u6548\u6c47\u7387');
            return;
          }
          toAmountMinor = toMinor(_toCurrency, major * fxRate);
        }
      } else if (_type == 'transfer') {
        toAmountMinor = amountMinor;
      }

      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final toAcc = _type == 'transfer' ? _toAccountId : null;
      var cat = _categoryId;
      if (_type == 'transfer' && cat == null && _ledgerId != null) {
        cat = (await db.ensureDefaultTransferCategory(_ledgerId!)).id;
      }
      if (widget.existing != null) {
        await db.updateManualTransaction(
          id: widget.existing!.id,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          note: note,
          tags: _tags,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      } else {
        await db.transaction(() async {
          final parentId = await db.insertManualTransaction(
            ledgerId: _ledgerId!,
            type: _type,
            amountMinor: amountMinor,
            currency: _currency,
            accountId: _accountId!,
            toAccountId: toAcc,
            categoryId: cat,
            note: note,
            tags: _tags,
            happenAt: _happenAt,
            fxRate: fxRate,
            toAmountMinor: toAmountMinor,
          );
          for (final sub in _draftSubs) {
            await db.insertManualTransaction(
              ledgerId: _ledgerId!,
              type: sub.type,
              amountMinor: sub.amountMinor,
              currency: sub.currency,
              accountId: sub.accountId,
              note: sub.subTypeName,
              happenAt: _happenAt,
              includeInStat: sub.includeInStat,
              includeInBudget: sub.includeInBudget,
              parentId: parentId,
              subTypeId: sub.subTypeId,
            );
          }
        });
      }
      // 记住这次的选择：下次「记一笔」直接沿用资产账户 / 分类。
      if (!mounted) return;
      if (_accountId != null && _categoryId != null) {
        final byType = Map<String, String>.from(_lastChoice?.categoryByType ?? {});
        byType[_categoryKind] = _categoryId!;
        final choice = LastBookkeepingChoice(
          type: _type,
          accountId: _accountId,
          categoryId: _categoryId,
          categoryByType: byType,
        );
        _lastChoice = choice;
        await db.setSetting(
          CentliDatabase.lastBookkeepingKey,
          jsonEncode(choice.toJson()),
        );
        // 备注 → 分类：同一条备注下次自动带出这个分类。
        await db.rememberNoteCategories([?note], _categoryId!);
      }
      if (!mounted) return;
      if (keepOpen && widget.existing == null) {
        // 再记一笔：保留分类+账户，清空金额/备注/标签/附加，时间刷新为现在。
        setState(() {
          _amountText = '0';
          _toAmountText = '0';
          _fxRateText = null;
          _noteCtrl.clear();
          _tags = [];
          _draftSubs = [];
          _happenAt = DateTime.now();
        });
        showGlassSnackBar(context, '已保存，可继续记账');
      } else {
        Navigator.of(context).pop(true);
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
      // 先查记忆再 setState，备注进面板时已经填好，不出现「先空再出」.
      final memory = await _loadCategoryMemory(id);
      if (!mounted) return;
      setState(() {
        _categoryId = id;
        if (memory != null) {
          if (_rememberCategoryAccount &&
              memory.accountId != null &&
              _accounts.any((a) => a.id == memory.accountId)) {
            _accountId = memory.accountId;
          }
          if (_rememberCategoryNote && memory.note != null) {
            _noteCtrl.text = memory.note!;
          }
        }
      });
      return;
    }
    // Dismiss or 管理: refresh tree, keep selection when still valid.
    await _reloadCategories();
  }

  Future<({String? accountId, String? note})?> _loadCategoryMemory(
    String categoryId,
  ) async {
    if (_ledgerId == null || _type == 'transfer') return null;
    if (!_rememberCategoryAccount && !_rememberCategoryNote) return null;
    return ref.read(databaseProvider).lastFieldsForCategory(
          ledgerId: _ledgerId!,
          categoryId: categoryId,
        );
  }

  Future<void> _applyCategoryMemory(String categoryId) async {
    final last = await _loadCategoryMemory(categoryId);
    if (!mounted || last == null) return;
    setState(() {
      if (_rememberCategoryAccount &&
          last.accountId != null &&
          _accounts.any((a) => a.id == last.accountId)) {
        _accountId = last.accountId;
      }
      if (_rememberCategoryNote && last.note != null) {
        _noteCtrl.text = last.note!;
      }
    });
  }

  Future<void> _pickAccount({required bool toAccount}) async {
    final current = toAccount ? _toAccountId : _accountId;
    final pool = toAccount
        ? _accounts.where((a) => a.id != _accountId).toList()
        : _accounts;
    final id = await showAccountPickerSheet(
      context,
      accounts: pool,
      assetTypes: _assetTypes,
      selectedId: current,
      title: toAccount ? '选择转入资产账户' : '选择资产账户',
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
    return amt > 0 ||
        _noteCtrl.text.trim().isNotEmpty ||
        _tags.isNotEmpty ||
        _draftSubs.isNotEmpty;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty) return true;
    final major = _evalAmount(_amountText) ?? 0;
    final label = major > 0
        ? formatMinor(_currency, toMinor(_currency, major))
        : (_noteCtrl.text.trim().isNotEmpty
            ? '备注'
            : (_tags.isNotEmpty
                ? '标签'
                : (_draftSubs.isNotEmpty ? '附加子交易' : '内容')));
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
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
    final suggestions = _ledgerId == null
        ? <String>[]
        : await ref.read(databaseProvider).listDistinctTags(_ledgerId!);
    if (!mounted) return;
    final result = await showTagEditorDialog(
      context,
      initial: _tags,
      suggestions: suggestions,
      title: '标签',
    );
    if (result != null && mounted) setState(() => _tags = result);
  }

  Future<void> _editDraftSubs() async {
    if (_draftSubs.isNotEmpty) {
      final action = await showGlassSheet<_DraftSubAction>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  '附加子交易',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (var i = 0; i < _draftSubs.length; i++)
                ListTile(
                  title: Text(_draftSubs[i].subTypeName),
                  subtitle: Text(
                    formatMinor(
                      _draftSubs[i].currency,
                      _draftSubs[i].amountMinor,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => Navigator.pop(
                      ctx,
                      _DraftSubAction.remove(i),
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, _DraftSubAction.edit(i)),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('再加一条'),
                onTap: () => Navigator.pop(ctx, const _DraftSubAction.add()),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action.kind == _DraftSubKind.remove) {
        setState(() => _draftSubs = [
              for (var i = 0; i < _draftSubs.length; i++)
                if (i != action.index) _draftSubs[i],
            ]);
        return;
      }
      if (action.kind == _DraftSubKind.edit) {
        final current = _draftSubs[action.index!];
        final types =
            await ref.read(databaseProvider).loadSubTransactionTypes();
        if (!mounted) return;
        SubTransactionType? type;
        for (final t in types) {
          if (t.id == current.subTypeId) {
            type = t;
            break;
          }
        }
        type ??= SubTransactionType(
          id: current.subTypeId,
          name: current.subTypeName,
          sign: current.sign,
          sortOrder: 0,
          createdAt: 0,
          updatedAt: 0,
        );
        final draft = await showSubTransactionSheet(
          context,
          subType: type,
          ledgerId: _ledgerId,
          initialAccountId: _accountId,
          initialDraft: current,
        );
        if (draft != null && mounted) {
          setState(() {
            _draftSubs = [
              for (var i = 0; i < _draftSubs.length; i++)
                if (i == action.index) draft else _draftSubs[i],
            ];
          });
        }
        return;
      }
    }
    await _addDraftSub();
  }

  Future<void> _addDraftSub() async {
    final type = await showSubTransactionTypePicker(context, ref);
    if (type == null || !mounted) return;
    final draft = await showSubTransactionSheet(
      context,
      subType: type,
      ledgerId: _ledgerId,
      initialAccountId: _accountId,
    );
    if (draft != null && mounted) {
      setState(() => _draftSubs = [..._draftSubs, draft]);
    }
  }



  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final hide = ref.watch(hideAmountProvider);
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
                          const SizedBox(height: 0),
                          Builder(
                            builder: (context) {
                              final segs = <(String, String)>[
                                ('out', '支出'),
                                ('in', '收入'),
                                ('transfer', '转账'),
                              ];
                              return Padding(
                                key: const Key('bk_type_switcher'),
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: Row(
                                  children: [
                                    for (final entry in segs)
                                      Expanded(
                                        child: InkWell(
                                          key: Key('bk_type_seg_${entry.$1}'),
                                          onTap: () async {
                                            setState(() {
                                              _type = entry.$1;
                                              if (entry.$1 == 'transfer') {
                                                _draftSubs = [];
                                              }
                                            });
                                            await _reloadCategories(
                                              resetSelection: true,
                                            );
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
                                              const SizedBox(height: CentliSpacing.item),
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
                                            fontSize: 26,
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
                          const SizedBox(height: CentliSpacing.section),
                          // Chips: time / category / account / tags（与改版前同排，不挤「更多」）
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
                                        label: acc?.name ?? '资产账户',
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
                                if (widget.existing == null &&
                                    _type != 'transfer')
                                  _MetaChip(
                                    icon: Icons.account_tree_outlined,
                                    label: _draftSubs.isEmpty
                                        ? '附加'
                                        : '附加 · ${_draftSubs.length}',
                                    onTap: _editDraftSubs,
                                  ),
                              ],
                            ),
                          ),
                          if (_type == 'transfer' && _isCrossCurrency)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                              child: Text(
                                '跨币：保存时会询问对方金额/汇率',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          const SizedBox(height: CentliSpacing.item),
                          Padding(
                            key: const Key('bk_note'),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              height: 46,
                              child: TextField(
                                controller: _noteCtrl,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '备注',
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
                          const SizedBox(height: CentliSpacing.item),
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
    if (k == 'AC') return CentliTheme.keypadAcBg(context);
    if (k == '\u232b') return CentliTheme.keypadNumBg(context);
    if (k == '+' || k == '-' || k == '*' || k == '/' || k == '=') {
      return CentliTheme.keypadOpBg(context);
    }
    return CentliTheme.keypadNumBg(context);
  }

  Color _fg(BuildContext context, String k) {
    if (k == '\u2713') return Colors.white;
    if (k == 'AC') return CentliTheme.keypadAcFg(context);
    if (k == '\u232b') return CentliTheme.keypadNumFg(context);
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
              child: k == '\u232b'
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: _fg(context, k),
                    )
                  : Text(
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

enum _DraftSubKind { add, edit, remove }

class _DraftSubAction {
  const _DraftSubAction._(this.kind, this.index);
  const _DraftSubAction.add() : this._(_DraftSubKind.add, null);
  const _DraftSubAction.edit(int index) : this._(_DraftSubKind.edit, index);
  const _DraftSubAction.remove(int index) : this._(_DraftSubKind.remove, index);

  final _DraftSubKind kind;
  final int? index;
}
