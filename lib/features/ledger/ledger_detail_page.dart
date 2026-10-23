import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'bookkeeping_sheet.dart' deferred as bookkeeping;

import '../../core/constants/currencies.dart';
import '../../core/utils/amount_expr.dart';
import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import 'account_picker_sheet.dart';
import 'category_picker_sheet.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

final _txnProvider =
    StreamProvider.family<Transaction?, String>((ref, id) {
  return ref.watch(databaseProvider).watchTransaction(id);
});

/// P0 bill detail: view fields, soft-delete, edit, toggle include-in-stat.
///
/// The top-right action is **保存** (enabled once a row was edited); the whole
/// amount / account / category / time / tags / note rows are each tappable and
/// persist on selection (commit-on-change).
class LedgerDetailPage extends ConsumerWidget {
  const LedgerDetailPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_txnProvider(transactionId));
    final hide = ref.watch(hideAmountProvider);
    final scheme = Theme.of(context).colorScheme;

    return async.when(
      loading: () => CentliGradientScaffold(
        appBar: AppBar(title: const Text('账单')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => CentliGradientScaffold(
        appBar: AppBar(title: const Text('账单')),
        body: Center(child: Text('加载失败: $e')),
      ),
      data: (txn) {
        if (txn == null || txn.deletedAt != null) {
          return CentliGradientScaffold(
            appBar: AppBar(title: const Text('账单')),
            body: const Center(child: Text('账单不存在或已删除')),
          );
        }
        return _DetailBody(
          key: ValueKey(txn.id),
          txn: txn,
          hide: hide,
          scheme: scheme,
        );
      },
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({
    super.key,
    required this.txn,
    required this.hide,
    required this.scheme,
  });

  final Transaction txn;
  final bool hide;
  final ColorScheme scheme;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  /// Fields edited through rows and not yet written (an edited amount is only
  /// persisted by 保存; picks are auto-committed and remembered so a failed
  /// write can be retried from 保存).
  int? _pendingAmountMinor;
  String? _pendingAccountId;
  String? _pendingToAccountId;
  String? _pendingCategoryId;
  DateTime? _pendingHappenAt;
  List<String>? _pendingTags;
  String? _pendingNote;
  String? _pendingType;
  int? _pendingIncludeInStat;
  int? _pendingIncludeInBudget;

  bool _saving = false;

  /// Picker sources, loaded once (include archived / historical ids).
  Future<_EditSources>? _sources;
  _EditSources? _sourceCache;

  Transaction get txn => widget.txn;

  @override
  void initState() {
    super.initState();
    // Warm the cache so account / category names (and the subtitle) resolve
    // without a per-build FutureBuilder; rows stay tappable meanwhile.
    _loadSources().then((s) {
      if (mounted) setState(() => _sourceCache = s);
    }).catchError((Object _) {});
  }

  bool get _isPendingEdit =>
      _pendingAmountMinor != null ||
      _pendingAccountId != null ||
      _pendingToAccountId != null ||
      _pendingCategoryId != null ||
      _pendingHappenAt != null ||
      _pendingTags != null ||
      _pendingNote != null ||
      _pendingType != null ||
      _pendingIncludeInStat != null ||
      _pendingIncludeInBudget != null;

  String get _type => _pendingType ?? txn.type;

  bool get _isTransfer => _type == 'transfer';

  int get _amountMinor => _pendingAmountMinor ?? txn.amountMinor;

  String? get _accountId => _pendingAccountId ?? txn.accountId;

  String? get _toAccountId => _pendingToAccountId ?? txn.toAccountId;

  String? get _categoryId => _pendingCategoryId ?? txn.categoryId;

  DateTime get _happenAt =>
      _pendingHappenAt ??
      DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true).toLocal();

  List<String> get _tags => _pendingTags ?? decodeTxnTags(txn.tags);

  String? get _note {
    final raw = (_pendingNote ?? txn.note ?? '').trim();
    return raw.isEmpty ? null : raw;
  }

  int get _includeInStat => _pendingIncludeInStat ?? txn.includeInStat;

  int get _includeInBudget => _pendingIncludeInBudget ?? txn.includeInBudget;

  // ---------------------------------------------------------------- styles

  ListTileThemeData _rowTheme(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      minLeadingWidth: 0,
      tileColor: Colors.transparent,
      textColor: scheme.onSurface,
      titleTextStyle: Theme.of(context).textTheme.bodyLarge,
      subtitleTextStyle: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: scheme.onSurfaceVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconColor: scheme.onSurfaceVariant,
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final hide = widget.hide;
    final isOut = txn.type == 'out';
    final isTransfer = txn.type == 'transfer';
    final prefix = isTransfer ? '' : (isOut ? '-' : '+');
    final amountColor = isTransfer
        ? CentliTheme.transferBlue
        : (isOut ? scheme.error : scheme.primary);

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          IconButton(
            tooltip: '再记一笔',
            key: const Key('ledger_detail_again'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _saving ? null : () => _again(context),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : () => _confirmDelete(context, ref),
          ),
          TextButton(
            key: const Key('ledger_detail_save'),
            onPressed: _isPendingEdit && !_saving ? () => _save() : null,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: PopScope(
        // Picks are only written by 保存; warn before throwing them away.
        canPop: !_isPendingEdit || _saving,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop || _saving) return;
          final ok = await _confirmDiscard(context);
          if (ok && context.mounted) Navigator.of(context).pop();
        },
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: CentliSpacing.sectionLoose),
          Center(
            child: InkWell(
              key: const Key('ledger_detail_amount'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editAmount(context),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  '$prefix${formatMinor(txn.currency, _amountMinor, hide: hide)}',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: amountColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CentliSpacing.item),
          Center(
            child: _Subtitle(
              type: txn.type,
              isTransfer: isTransfer,
              categoryName: _categoryNameOf(_categoryId),
              fromAccountName: _accountNameOf(_accountId) ?? '?',
              sourceFuture: _sourceCache == null ? _ensureSources() : null,
              toAccountName:
                  isTransfer ? _accountNameOf(_toAccountId) : null,
              onResolved: (s) {
                if (!mounted || _sourceCache == s) return;
                // First paint races initState's load; repaint once.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _sourceCache != s) {
                    setState(() => _sourceCache = s);
                  }
                });
              },
            ),
          ),
          // Type (支出 / 收入 / 转账)
          Center(
            child: TextButton.icon(
              key: const Key('ledger_detail_type'),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: Text('改类型'),
              onPressed: () => _editType(context),
            ),
          ),
          if ((txn.note ?? '').trim() == '余额校正') ...[
            const SizedBox(height: CentliSpacing.item),
            Center(
              child: Chip(
                avatar: Icon(Icons.tune, size: 16, color: scheme.primary),
                label: const Text('余额校正（不计入统计）'),
              ),
            ),
          ],
          const SizedBox(height: CentliSpacing.sectionLoose + CentliSpacing.item),
          CentliSoftCard(
            clipBehavior: Clip.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(context, '基本信息'),
                _accountRows(context),
                if (isTransfer) ..._transferAmountRows(context),
                _sectionHeader(context, '来源与时间'),
                _EditRow(
                  key: const Key('ledger_detail_time'),
                  theme: _rowTheme(context),
                  icon: Icons.schedule,
                  title: '时间',
                  value: DateFormat('yyyy-MM-dd HH:mm').format(_happenAt),
                  onTap: () => _editHappenAt(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _infoRow(
                  context,
                  icon: Icons.input,
                  title: '来源',
                  value: _sourceLabel(txn.source),
                ),
                _sectionHeader(context, '其它'),
                _EditRow(
                  key: const Key('ledger_detail_tags'),
                  theme: _rowTheme(context),
                  icon: Icons.sell_outlined,
                  title: '标签',
                  value: _tags.isEmpty ? null : _tags.join('  '),
                  emptyText: '—',
                  onTap: () => _editTags(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _EditRow(
                  key: const Key('ledger_detail_note'),
                  theme: _rowTheme(context),
                  icon: Icons.edit_note,
                  title: '备注',
                  value: _note,
                  emptyText: '—',
                  onTap: () => _editNote(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  key: const Key('ledger_detail_include_stat'),
                  contentPadding: const EdgeInsets.only(left: 16, right: 8),
                  secondary: const Icon(Icons.bar_chart_outlined),
                  title: const Text('计入统计'),
                  subtitle: const Text('影响收支统计与趋势'),
                  value: _includeInStat == 1,
                  onChanged: isTransfer || _saving
                      ? null
                      : (v) {
                          setState(() => _pendingIncludeInStat = v ? 1 : 0);
                        },
                ),
                SwitchListTile(
                  key: const Key('ledger_detail_include_budget'),
                  contentPadding: const EdgeInsets.only(left: 16, right: 8),
                  secondary: const Icon(Icons.savings_outlined),
                  title: const Text('计入预算'),
                  subtitle: const Text('影响月度预算进度'),
                  value: _includeInBudget == 1,
                  onChanged: isTransfer || _saving
                      ? null
                      : (v) {
                          setState(() => _pendingIncludeInBudget = v ? 1 : 0);
                        },
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _accountRows(BuildContext context) {
    final theme = _rowTheme(context);
    if (!_isTransfer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EditRow(
            key: const Key('ledger_detail_account'),
            theme: theme,
            icon: Icons.account_balance_wallet_outlined,
            title: '资产账户',
            value: _accountNameOf(_accountId),
            emptyText: '—',
            onTap: () => _editAccount(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _EditRow(
            key: const Key('ledger_detail_category'),
            theme: theme,
            icon: Icons.local_offer_outlined,
            title: '分类',
            value: _categoryNameOf(_categoryId),
            emptyText: '—',
            onTap: () => _editCategory(context),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditRow(
          key: const Key('ledger_detail_account'),
          theme: theme,
          icon: Icons.south_west_rounded,
          title: '转出资产账户',
          value: _accountNameOf(_accountId),
          emptyText: '—',
          onTap: () => _editAccount(context),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _EditRow(
          key: const Key('ledger_detail_to_account'),
          theme: theme,
          icon: Icons.north_east_rounded,
          title: '转入资产账户',
          value: _accountNameOf(_toAccountId),
          emptyText: '—',
          onTap: () => _editToAccount(context),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        _EditRow(
          key: const Key('ledger_detail_category'),
          theme: theme,
          icon: Icons.local_offer_outlined,
          title: '分类',
          value: _categoryNameOf(_categoryId),
          emptyText: '—',
          onTap: () => _switchToTransferOrCategory(context),
        ),
      ],
    );
  }

  List<Widget> _transferAmountRows(BuildContext context) {
    final fx = txn.fxRate;
    if (txn.toAmountMinor == null && fx == null) return const [];
    final toCcy = _currencyOfAccount(_toAccountId) ?? txn.currency;
    return [
      const Divider(height: 1, indent: 16, endIndent: 16),
      _infoRow(
        context,
        icon: Icons.swap_vert,
        title: '对方金额',
        value: txn.toAmountMinor == null
            ? '—'
            : formatMinor(toCcy, txn.toAmountMinor!, hide: widget.hide),
      ),
      if (fx != null) ...[
        const Divider(height: 1, indent: 16, endIndent: 16),
        _infoRow(
          context,
          icon: Icons.currency_exchange,
          title: '汇率',
          value: fx.toStringAsFixed(6),
        ),
      ],
    ];
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(title),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  // ------------------------------------------------------- name lookups

  String? _accountNameOf(String? id) {
    if (id == null) return null;
    final s = _sourceCache;
    if (s != null) {
      for (final a in s.accounts) {
        if (a.id == id) return a.name;
      }
    }
    return id;
  }

  String? _currencyOfAccount(String? id) {
    if (id == null) return null;
    final s = _sourceCache;
    if (s != null) {
      for (final a in s.accounts) {
        if (a.id == id) return a.currency;
      }
    }
    return null;
  }

  String? _categoryNameOf(String? id) {
    if (id == null) return null;
    final s = _sourceCache;
    if (s != null) {
      for (final c in s.categories) {
        if (c.id == id) return c.name;
      }
    }
    return id;
  }

  Future<_EditSources> _loadSources() {
    return _sources ??= () async {
      final db = ref.read(databaseProvider);
      final accounts = await db.loadAccountsIncludingArchived(txn.ledgerId);
      final assetTypes = await db.loadAssetTypes(txn.ledgerId);
      final outCats = await db.loadCategories(txn.ledgerId, 'out');
      final inCats = await db.loadCategories(txn.ledgerId, 'in');
      final transferCats = await db.loadCategories(txn.ledgerId, 'transfer');
      final tags = await db.listDistinctTags(txn.ledgerId);
      // Keep archived current category selectable / displayable.
      var cats = [...outCats, ...inCats, ...transferCats];
      final cur = _categoryId;
      if (cur != null && !cats.any((c) => c.id == cur)) {
        final c = await db.getCategory(cur);
        if (c != null) cats = [...cats, c];
      }
      return _EditSources(
        accounts: accounts,
        assetTypes: assetTypes,
        outCats: outCats,
        inCats: inCats,
        transferCats: transferCats,
        categories: cats,
        tagSuggestions: tags,
      );
    }();
  }

  Future<_EditSources?> _ensureSources() async {
    try {
      final s = await _loadSources();
      if (mounted) {
        // Repaint labels with resolved names.
        setState(() => _sourceCache = s);
      }
      return s;
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, '加载选项失败: $e');
      }
      return null;
    }
  }

  // --------------------------------------------------------- persistence

  /// Writes every pending field at once. Nothing is written until the user
  /// taps 保存 (explicit request: no auto-save).
  Future<bool> _commit() async {
    if (!_isPendingEdit) return true;

    final snapshot = (
      amount: _pendingAmountMinor,
      account: _pendingAccountId,
      toAccount: _pendingToAccountId,
      category: _pendingCategoryId,
      happen: _pendingHappenAt,
      tags: _pendingTags,
      note: _pendingNote,
      type: _pendingType,
      stat: _pendingIncludeInStat,
      budget: _pendingIncludeInBudget,
    );
    setState(() => _saving = true);
    try {
      final int? amount = snapshot.amount;
      final String? type = snapshot.type;
      // Category follows the (possibly new) direction for amount edits.
      var category = snapshot.category;
      final String direction = type ?? _type;
      if (category != null) {
        final s = await _loadSources();
        final pool = switch (direction) {
          'in' => s.inCats,
          'transfer' => s.transferCats,
          _ => s.outCats,
        };
        if (pool.isNotEmpty && !pool.any((c) => c.id == category)) {
          category = pool.first.id;
        }
      } else if (direction == 'transfer') {
        final s = await _loadSources();
        if (s.transferCats.isNotEmpty) {
          category = s.transferCats.first.id;
        } else {
          category = (await ref
                  .read(databaseProvider)
                  .ensureDefaultTransferCategory(txn.ledgerId))
              .id;
        }
      }
      final fromAccount = snapshot.account ?? _accountId;
      Value<String?>? toAccountValue;
      Value<int?>? toAmountValue;
      Value<double?>? fxRateValue;
      if (direction == 'transfer') {
        final to = snapshot.toAccount ?? _toAccountId;
        if (to == null || to.isEmpty || to == fromAccount) {
          if (mounted) {
            showGlassSnackBar(context, '转账请选择不同的转入资产账户');
            setState(() => _saving = false);
          }
          return false;
        }
        toAccountValue = Value(to);
        // 同币种：对方金额跟转出对齐；跨币种保留已有 to_amount / fx。
        final fromCcy = _currencyOfAccount(fromAccount) ?? txn.currency;
        final toCcy = _currencyOfAccount(to) ?? fromCcy;
        if (fromCcy == toCcy) {
          final amt = amount ?? _amountMinor;
          toAmountValue = Value(amt);
          fxRateValue = const Value(null);
        }
      } else if (type != null && type != 'transfer') {
        // 从转账改回收支：清掉转入相关字段，避免错挂余额。
        toAccountValue = const Value(null);
        toAmountValue = const Value(null);
        fxRateValue = const Value(null);
      }
      await ref.read(databaseProvider).updateTransactionFields(
            id: txn.id,
            type: type,
            amountMinor: amount,
            accountId: snapshot.account,
            toAccountId: toAccountValue,
            categoryId: category,
            happenAt: snapshot.happen,
            tags: snapshot.tags,
            note: snapshot.note,
            includeInStat: snapshot.stat,
            includeInBudget: snapshot.budget,
            toAmountMinor: toAmountValue,
            fxRate: fxRateValue,
          );
      if (!mounted) return true;
      setState(() {
        _pendingAmountMinor = null;
        _pendingAccountId = null;
        _pendingToAccountId = null;
        _pendingCategoryId = null;
        _pendingHappenAt = null;
        _pendingTags = null;
        _pendingNote = null;
        _pendingType = null;
        _pendingIncludeInStat = null;
        _pendingIncludeInBudget = null;
      });
      return true;
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, '保存失败: $e。可再点「保存」重试');
        setState(() {});
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final ok = await _commit();
    if (ok && mounted) {
      showGlassSnackBar(context, '已保存');
    }
  }

  /// 「照着这笔再记一笔」: open the panel as a new bill prefilled from this one.
  Future<void> _again(BuildContext context) async {
    if (_isPendingEdit) {
      final ok = await _confirmDiscard(context);
      if (ok != true || !context.mounted) return;
    }
    await bookkeeping.loadLibrary();
    if (!context.mounted) return;
    await bookkeeping.showBookkeepingSheet(context, template: txn);
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final leave = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('放弃修改？'),
        content: const Text('这笔账单还有未保存的修改，离开后会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ------------------------------------------------------------- editors

  Future<void> _editType(BuildContext context) async {
    final picked = await _pickTransactionType(context, initial: _type);
    if (picked == null || picked == _type) return;
    setState(() {
      _pendingType = picked;
      if (picked == 'transfer') {
        var to = _toAccountId;
        if (to == null || to == _accountId) {
          final others = _sourceCache?.accounts
                  .where((a) => a.id != _accountId)
                  .toList() ??
              const <Account>[];
          to = others.isEmpty ? null : others.first.id;
        }
        _pendingToAccountId = to;
      } else {
        _pendingToAccountId = null;
      }
    });
    // New direction: keep the category only when it belongs to that side,
    // otherwise fall back to the first category of the new direction.
    final s = await _ensureSources();
    var pool = switch (picked) {
      'in' => s?.inCats ?? const <Category>[],
      'transfer' => s?.transferCats ?? const <Category>[],
      _ => s?.outCats ?? const <Category>[],
    };
    if (picked == 'transfer' && pool.isEmpty) {
      final ensured = await ref
          .read(databaseProvider)
          .ensureDefaultTransferCategory(txn.ledgerId);
      _sources = null;
      _sourceCache = null;
      final refreshed = await _ensureSources();
      pool = refreshed?.transferCats ?? [ensured];
    }
    if (mounted) {
      setState(() {
        final keep = _categoryId;
        _pendingCategoryId = keep != null && pool.any((c) => c.id == keep)
            ? keep
            : (pool.isEmpty ? null : pool.first.id);
      });
    }
  }

  Future<void> _editAccount(BuildContext context) async {
    final s = await _ensureSources();
    if (s == null || !context.mounted) return;
    final id = await showAccountPickerSheet(
      context,
      accounts: s.accounts,
      assetTypes: s.assetTypes,
      selectedId: _accountId,
      title: _isTransfer ? '选择转出资产账户' : '选择资产账户',
    );
    if (id == null || id == _accountId) return;
    setState(() {
      _pendingCategoryId = _categoryId; // re-validate category direction
      _pendingAccountId = id;
      if (_isTransfer && _toAccountId == id) {
        final others = s.accounts.where((a) => a.id != id);
        _pendingToAccountId = others.isEmpty ? null : others.first.id;
      }
    });
    if (mounted) setState(() {});
  }

  Future<void> _editToAccount(BuildContext context) async {
    final s = await _ensureSources();
    if (s == null || !context.mounted) return;
    final id = await showAccountPickerSheet(
      context,
      accounts: s.accounts.where((a) => a.id != _accountId).toList(),
      assetTypes: s.assetTypes,
      selectedId: _toAccountId,
      title: '选择转入资产账户',
    );
    if (id == null || id == _toAccountId) return;
    setState(() => _pendingToAccountId = id);
    if (mounted) setState(() {});
  }

  Future<void> _switchToTransferOrCategory(BuildContext context) async {
    if (_isTransfer) {
      final picked = await _pickTransactionType(context, initial: 'transfer');
      if (picked == null || picked == 'transfer') return;
      setState(() {
        _pendingType = picked;
        _pendingToAccountId = null;
      });
      if (mounted) setState(() {});
      return;
    }
    await _editCategory(context);
  }

  Future<void> _editCategory(BuildContext context) async {
    final s = await _ensureSources();
    if (s == null || !context.mounted) return;
    final pool = switch (_type) {
      'in' => s.inCats,
      'transfer' => s.transferCats,
      _ => s.outCats,
    };
    final categories = pool.isEmpty ? s.categories : pool;
    final id = await showCategoryPickerSheet(
      context,
      categories: categories,
      selectedId: _categoryId,
    );
    if (id == null || id == _categoryId || !context.mounted) return;
    setState(() => _pendingCategoryId = id);
    if (mounted) setState(() {});
  }

  Future<void> _editHappenAt(BuildContext context) async {
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
    if (date == null || !context.mounted) return;
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
    final next = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (next.millisecondsSinceEpoch == _happenAt.millisecondsSinceEpoch) {
      return; // no change
    }
    setState(() => _pendingHappenAt = next);
    if (mounted) setState(() {});
  }

  Future<void> _editTags(BuildContext context) async {
    final s = await _ensureSources();
    if (s == null || !context.mounted) return;
    final result = await showTagEditorDialog(
      context,
      initial: _tags,
      suggestions: s.tagSuggestions,
      title: '编辑标签',
    );
    if (result == null || !context.mounted) return;
    setState(() => _pendingTags = result);
    if (mounted) setState(() {});
  }

  Future<void> _editNote(BuildContext context) async {
    final ctrl = TextEditingController(text: _note ?? '');
    final ok = await _promptText(
      context,
      title: '备注',
      controller: ctrl,
      hint: '例如：和同事午餐',
      maxLength: 200,
    );
    if (ok != true || !mounted) return;
    final next = ctrl.text.trim();
    if (next == (_note ?? '')) return;
    setState(() => _pendingNote = next);
    if (mounted) setState(() {});
  }

  Future<void> _editAmount(BuildContext context) async {
    if (_isTransfer) {
      final fromCcy = _currencyOfAccount(_accountId) ?? txn.currency;
      final toId = _toAccountId;
      final toCcy =
          toId == null ? fromCcy : (_currencyOfAccount(toId) ?? fromCcy);
      if (fromCcy != toCcy) {
        if (!context.mounted) return;
        showGlassSnackBar(context, '跨币种转账请用「记一笔」修改金额与汇率');
        return;
      }
    }
    final ccy = _currencyOfAccount(_accountId) ?? txn.currency;
    // Amt is stored in txn.currency (same ccy the amount row renders with).
    var text = fromMinor(txn.currency, _amountMinor)
        .toStringAsFixed(currencyDecimals[txn.currency] ?? 2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    final newText = await _promptAmount(context, initial: text, currency: ccy);
    if (newText == null || !context.mounted) return;
    final major = evalAmountExpr(newText);
    if (major == null || major <= 0) {
      showGlassSnackBar(context, '请输入有效金额');
      return;
    }
    final minor = toMinor(ccy, major);
    if (minor == txn.amountMinor && _pendingAmountMinor == null) return;
    setState(() => _pendingAmountMinor = minor);
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('删除账单'),
        content: const Text('确定删除这笔账单？可在「回收站」恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(databaseProvider).softDeleteTransaction(txn.id);
    if (context.mounted) {
      showGlassSnackBar(context, '已删除');
      context.pop();
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'notification':
        return '通知自动';
      case 'ocr':
        return '截图导入';
      case 'clipboard':
        return '剪贴板导入';
      case 'share':
        return '分享导入';
      case 'share_image':
        return '分享图片';
      case 'url':
        return '链接导入';
      case 'manual':
        return '手动';
      default:
        return '手动';
    }
  }
}


// ---------------------------------------------------------------------------
// Dialogs / sheets (also used by the bookkeeping sheet for consistent editing)
// ---------------------------------------------------------------------------

/// Type picker for 支出 / 收入 / 转账. Refund keeps its own type when untouched.
Future<String?> _pickTransactionType(
  BuildContext context, {
  required String initial,
}) {
  const options = <(String, String, IconData)>[
    ('out', '支出', Icons.south_west_rounded),
    ('in', '收入', Icons.north_east_rounded),
    ('transfer', '转账', Icons.swap_horiz_rounded),
  ];
  return showGlassSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '修改类型',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final o in options)
              ListTile(
                leading: Icon(o.$3, color: scheme.onSurfaceVariant),
                title: Text(o.$2),
                trailing: initial == o.$1
                    ? Icon(Icons.check_circle, color: CentliTheme.softBlue)
                    : null,
                onTap: () => Navigator.pop(ctx, o.$1),
              ),
            const SizedBox(height: CentliSpacing.item),
          ],
        ),
      );
    },
  );
}

/// Small numeric prompt (evaluates + - × ÷ expressions like the keypad).
Future<String?> _promptAmount(
  BuildContext context, {
  required String initial,
  required String currency,
}) {
  final ctrl = TextEditingController(text: initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: initial.length,
    );
  final formKey = GlobalKey<FormState>();
  final done = showGlassDialog<String>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: Text('修改金额 ($currency)'),
      content: Form(
        key: formKey,
        child: TextFormField(
          key: const Key('ledger_detail_amount_field'),
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-×÷*/ ]')),
          ],
          decoration: const InputDecoration(
            prefixText: '¥ ',
            helperText: '支持 12+8 之类的算式',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
          validator: (v) {
            final major = evalAmountExpr((v ?? '').trim());
            if (major == null || major <= 0) return '请输入有效金额';
            return null;
          },
          onFieldSubmitted: (_) {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, ctrl.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('ledger_detail_amount_ok'),
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(ctx, ctrl.text.trim());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // Hold the controller until the dialog route (exit animation included) is
  // fully gone: popping returns before the TextField is unmounted.
  return done.whenComplete(() {
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  });
}

/// Single-line text prompt; pops `true` when confirmed.
Future<bool?> _promptText(
  BuildContext context, {
  required String title,
  required TextEditingController controller,
  String? hint,
  int maxLength = 200,
}) {
  final done = showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: Text(title),
      content: TextField(
        key: const Key('ledger_detail_text_field'),
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  // Caller-owned controller: release it only after the exit animation.
  return done.whenComplete(() {
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
  });
}

/// Tag editor shared by the detail rows and the bookkeeping sheet.
Future<List<String>?> showTagEditorDialog(
  BuildContext context, {
  required List<String> initial,
  List<String> suggestions = const [],
  String title = '编辑标签',
}) {
  final current = List<String>.from(initial);
  final ctrl = TextEditingController();
  final done = showGlassDialog<List<String>>(
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

          return CentliGlassDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in current)
                        InputChip(
                          label: Text(t),
                          onDeleted: () => setLocal(() => current.remove(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: '新标签',
                      hintText: '回车确认，最多 5 个',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                    onSubmitted: addTag,
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: CentliSpacing.item),
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
                key: const Key('ledger_detail_tags_save'),
                onPressed: () =>
                    Navigator.pop(ctx, List<String>.from(current)),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
  // Release after the route's exit animation (see _promptAmount).
  return done.whenComplete(() {
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  });
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _EditSources {
  const _EditSources({
    required this.accounts,
    required this.assetTypes,
    required this.outCats,
    required this.inCats,
    required this.transferCats,
    required this.categories,
    required this.tagSuggestions,
  });

  final List<Account> accounts;
  final List<AssetType> assetTypes;
  final List<Category> outCats;
  final List<Category> inCats;
  final List<Category> transferCats;
  final List<Category> categories;
  final List<String> tagSuggestions;
}

/// Tappable list row: label on the left, value + chevron on the right.
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.emptyText = '—',
  });

  final ListTileThemeData theme;
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.trim().isNotEmpty;
    return ListTileTheme(
      data: theme,
      child: ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                hasValue ? value! : emptyText,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue
                      ? scheme.onSurfaceVariant
                      : scheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Title line under the amount: "支出 · 午餐" / "转账 · 支付宝 → 余额宝".
class _Subtitle extends ConsumerWidget {
  const _Subtitle({
    required this.type,
    required this.isTransfer,
    required this.categoryName,
    required this.fromAccountName,
    required this.toAccountName,
    required this.onResolved,
    this.sourceFuture,
  });

  final String type;
  final bool isTransfer;
  final String? categoryName;
  final String fromAccountName;
  final String? toAccountName;
  final void Function(_EditSources sources) onResolved;
  final Future<_EditSources?>? sourceFuture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pending = sourceFuture;
    if (pending != null) {
      pending.then((s) {
        if (s != null) onResolved(s);
      }, onError: (Object _) {});
    }
    final typeLabel = _typeLabel(type);
    final text = isTransfer
        ? '$typeLabel  ·  $fromAccountName → ${toAccountName ?? '?'}'
        : '$typeLabel${categoryName != null ? '  ·  $categoryName' : ''}';
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'in':
        return '收入';
      case 'transfer':
        return '转账';
      default:
        return '支出';
    }
  }
}