import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/picker_form_field.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../ledger/account_picker_sheet.dart';
import '../ledger/category_picker_sheet.dart';

/// 一条待确认通知里，「方向」的显示名（仅支出 / 收入）。
String pendingDirectionLabel(String? direction) {
  switch (NotiTemplate.normalizeDirection(direction)) {
    case 'in':
      return '收入';
    default:
      return '支出';
  }
}

/// 渠道显示名（支付宝 / 微信 / 包名）。
String pendingSourceLabel(String pkg) {
  if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
  if (pkg.contains('tencent.mm')) return '微信';
  return pkg;
}

/// 打开「确认入账」弹窗：填写金额 / 分类 / 资产账户 / 备注后直接入账。
///
/// 返回 true 表示已入账（调用方可以据此刷新或前移轮播）。
Future<bool> showPendingConfirmDialog(
  BuildContext context,
  WidgetRef ref, {
  required PendingCapture capture,
}) async {
  final db = ref.read(databaseProvider);
  // 分类按 pending 账本；账户可跨账本（标明所属），默认当前/pending 账本。
  final out = await db.loadCategories(capture.ledgerId, 'out');
  final inn = await db.loadCategories(capture.ledgerId, 'in');
  final accounts = await db.loadAllActiveAccounts();
  final ledgers = await db.loadAllLedgers();
  final ledgerNameMap = {for (final l in ledgers) l.id: l.name};
  final ledgerNamesByAccountId = {
    for (final a in accounts)
      if (ledgerNameMap[a.ledgerId] != null) a.id: ledgerNameMap[a.ledgerId]!,
  };
  if (!context.mounted) return false;
  final saved = await showGlassSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _ConfirmPendingSheet(
      capture: capture,
      categories: [...out, ...inn],
      accounts: accounts,
      ledgers: ledgers.where((l) => l.archived == 0).toList(),
      ledgerNamesByAccountId: ledgerNamesByAccountId,
    ),
  );
  return saved == true;
}

class _ConfirmPendingSheet extends ConsumerStatefulWidget {
  const _ConfirmPendingSheet({
    required this.capture,
    required this.categories,
    required this.accounts,
    required this.ledgers,
    required this.ledgerNamesByAccountId,
  });

  final PendingCapture capture;
  final List<Category> categories;
  final List<Account> accounts;
  final List<Ledger> ledgers;
  final Map<String, String> ledgerNamesByAccountId;

  @override
  ConsumerState<_ConfirmPendingSheet> createState() =>
      _ConfirmPendingSheetState();
}

class _ConfirmPendingSheetState extends ConsumerState<_ConfirmPendingSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  String? _categoryId;
  String? _accountId;
  late String _ledgerId;
  List<Category> _categories = const [];
  String? _directionOverride;
  var _busy = false;

  PendingCapture get c => widget.capture;

  /// 先看用户在弹窗里改过的类型，再看持久化方向，最后重新解析。
  String get _direction {
    final chosen = _directionOverride;
    if (chosen != null && chosen.isNotEmpty) {
      return NotiTemplate.normalizeDirection(chosen);
    }
    final stored = c.direction?.trim();
    if (stored != null && stored.isNotEmpty) {
      return NotiTemplate.normalizeDirection(stored);
    }
    final templates = NotiTemplateStore.peek();
    return NotiTemplate.normalizeDirection(
      parseNotification(
        RawNotification(
          pkg: c.sourcePkg,
          title: c.rawTitle ?? '',
          text: c.rawText,
          whenMs: c.happenAt ?? c.createdAt,
        ),
        templates.isEmpty ? null : templates,
      ).direction,
    );
  }

  List<Category> get _catsForDirection {
    final wantIn = _direction == 'in';
    final wanted = [
      for (final x in _categories)
        if (x.kind == (wantIn ? 'in' : 'out')) x,
    ];
    return wanted.isNotEmpty ? wanted : _categories;
  }

  String get _ledgerLabel {
    for (final l in widget.ledgers) {
      if (l.id == _ledgerId) return l.name;
    }
    return '选择账本';
  }

  @override
  void initState() {
    super.initState();
    final ccy = c.currency ?? 'CNY';
    _amountCtrl = TextEditingController(
      text: c.amountMinor == null
          ? ''
          : fromMinor(ccy, c.amountMinor!).toStringAsFixed(ccy == 'JPY' ? 0 : 2),
    );
    final seedNote = () {
      final base = (c.note ?? '').trim();
      if (isRefundSignal(
            direction: c.direction,
            title: c.rawTitle,
            text: c.rawText,
          ) &&
          !base.contains('退款')) {
        return base.isEmpty ? '退款' : '$base · 退款';
      }
      return base;
    }();
    _noteCtrl = TextEditingController(text: seedNote);
    _ledgerId = c.ledgerId;
    _categories = List<Category>.from(widget.categories);
    final cats = _catsForDirection;
    final suggested = c.suggestedCategoryId;
    _categoryId = cats.any((x) => x.id == suggested)
        ? suggested
        : (cats.isNotEmpty ? cats.first.id : null);
    // Prefer accounts in pending/current ledger; fall back to any.
    final inLedger = [
      for (final a in widget.accounts)
        if (a.ledgerId == _ledgerId) a,
    ];
    final accounts = inLedger.isNotEmpty ? inLedger : widget.accounts;
    final acc = c.suggestedAccountId;
    _accountId = accounts.any((x) => x.id == acc)
        ? acc
        : (accounts.isNotEmpty ? accounts.first.id : null);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Category? _categoryById(String? id) {
    if (id == null) return null;
    for (final c in _catsForDirection) {
      if (c.id == id) return c;
    }
    return null;
  }

  Account? _accountById(String? id) {
    if (id == null) return null;
    for (final a in widget.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _catsForDirection,
      selectedId: _categoryId,
    );
    if (id == null || !mounted) return;
    setState(() => _categoryId = id);
  }

  Future<void> _reloadCategoriesForLedger(String ledgerId) async {
    final db = ref.read(databaseProvider);
    final out = await db.loadCategories(ledgerId, 'out');
    final inn = await db.loadCategories(ledgerId, 'in');
    if (!mounted) return;
    setState(() {
      _ledgerId = ledgerId;
      _categories = [...out, ...inn];
      final cats = _catsForDirection;
      if (!cats.any((x) => x.id == _categoryId)) {
        _categoryId = cats.isEmpty ? null : cats.first.id;
      }
      // Keep account if still valid; else prefer one in this ledger.
      final stillOk = widget.accounts.any((a) => a.id == _accountId);
      if (!stillOk) {
        final inLedger = [
          for (final a in widget.accounts)
            if (a.ledgerId == ledgerId) a,
        ];
        _accountId = inLedger.isNotEmpty
            ? inLedger.first.id
            : (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
      } else {
        final acc = _accountById(_accountId);
        if (acc != null &&
            acc.ledgerId.isNotEmpty &&
            acc.ledgerId != ledgerId) {
          // Account binds ledger — follow account (caller may have set both).
        }
      }
    });
  }

  Future<void> _pickLedger() async {
    if (widget.ledgers.isEmpty) return;
    final chosen = await showGlassSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  '选择账本',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final l in widget.ledgers)
                ListTile(
                  title: Text(l.name),
                  trailing: l.id == _ledgerId
                      ? Icon(
                          Icons.check,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, l.id),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted || chosen == _ledgerId) return;
    await _reloadCategoriesForLedger(chosen);
    // Prefer an account in the newly selected ledger.
    final inLedger = [
      for (final a in widget.accounts)
        if (a.ledgerId == chosen) a,
    ];
    if (inLedger.isNotEmpty && mounted) {
      setState(() {
        if (!inLedger.any((a) => a.id == _accountId)) {
          _accountId = inLedger.first.id;
        }
      });
    }
  }

  Future<void> _pickAccount() async {
    final db = ref.read(databaseProvider);
    final types = await db.loadAssetTypes(_ledgerId);
    if (!mounted) return;
    final id = await showAccountPickerSheet(
      context,
      accounts: widget.accounts,
      assetTypes: types,
      selectedId: _accountId,
      ledgerNamesByAccountId: widget.ledgerNamesByAccountId,
      preferredLedgerId: _ledgerId,
    );
    if (id == null || !mounted) return;
    final acc = _accountById(id);
    setState(() => _accountId = id);
    // Follow account's ledger so confirm never mis-attributes.
    if (acc != null &&
        acc.ledgerId.isNotEmpty &&
        acc.ledgerId != _ledgerId) {
      await _reloadCategoriesForLedger(acc.ledgerId);
    }
  }

  Future<void> _confirm() async {
    final ccy = c.currency ?? 'CNY';
    final major = double.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (major == null || major <= 0) {
      _toast('请输入有效金额');
      return;
    }
    if (_accountId == null) {
      _toast('请选择资产账户');
      return;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }
    setState(() => _busy = true);
    try {
      final inCats = _categories.where((x) => x.kind == 'in');
      final outCats = _categories.where((x) => x.kind == 'out');
      final known = outCats.any((x) => x.id == _categoryId) ||
          inCats.any((x) => x.id == _categoryId);
      // 仅支出 / 收入；退款走收入 + 标签「退款」。
      final String txnType;
      if (!known) {
        txnType = _direction == 'in' ? 'in' : 'out';
      } else {
        txnType = inCats.any((x) => x.id == _categoryId) ? 'in' : 'out';
      }
      final templates = NotiTemplateStore.peek();
      final parsedForRule = parseNotification(
        RawNotification(
          pkg: c.sourcePkg,
          title: c.rawTitle ?? '',
          text: c.rawText,
          whenMs: c.happenAt ?? c.createdAt,
        ),
        templates.isEmpty ? null : templates,
      );
      final refund = isRefundSignal(
        direction: c.direction,
        templateId: parsedForRule.templateId,
        title: c.rawTitle,
        text: c.rawText,
      );
      final repay = isRepaySignal(
        direction: c.direction,
        templateId: parsedForRule.templateId,
        title: c.rawTitle,
        text: c.rawText,
      );
      final tags = <String>[
        if (refund) '退款',
        if (repay) '还款',
      ];
      var note = _noteCtrl.text.trim();
      if (refund && note.isNotEmpty && !note.contains('退款')) {
        note = '$note · 退款';
      } else if (refund && note.isEmpty) {
        note = '退款';
      }
      // Account's ledger wins when set (confirmPendingCapture also enforces).
      final acc = _accountById(_accountId);
      final targetLedger = (acc != null && acc.ledgerId.isNotEmpty)
          ? acc.ledgerId
          : _ledgerId;
      await ref.read(databaseProvider).confirmPendingCapture(
            pendingId: c.id,
            amountMinor: toMinor(ccy, major),
            currency: ccy,
            accountId: _accountId!,
            categoryId: _categoryId!,
            note: note.isEmpty ? null : note,
            merchantForRule: parsedForRule.merchant,
            type: txnType,
            tags: tags.isEmpty ? null : tags,
            includeInStat: 1,
            includeInBudget: 1,
            ledgerId: targetLedger,
          );
      await NotificationCaptureStub.cancelPendingConfirm(c.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('入账失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    showGlassSnackBar(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ccy = c.currency ?? 'CNY';
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '确认入账',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CentliGlassPopupButton<String>(
                  key: const Key('confirm_pending_type'),
                  enabled: !_busy,
                  alignEnd: true,
                  onSelected: (dir) {
                    setState(() {
                      _directionOverride = dir;
                      final cats = _catsForDirection;
                      if (!cats.any((x) => x.id == _categoryId)) {
                        _categoryId = cats.isEmpty ? null : cats.first.id;
                      }
                    });
                  },
                  items: [
                    CentliMenuItem(
                      value: 'out',
                      label: '支出',
                      selected: _direction == 'out',
                    ),
                    CentliMenuItem(
                      value: 'in',
                      label: '收入',
                      selected: _direction == 'in',
                    ),
                  ],
                  child: Chip(
                    label: Text(pendingDirectionLabel(_direction)),
                    avatar: const Icon(Icons.unfold_more, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CentliSpacing.dense),
            Text(
              '${pendingSourceLabel(c.sourcePkg)} · ${c.rawTitle?.trim().isNotEmpty == true ? c.rawTitle!.trim() : c.rawText}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CentliSpacing.section),
            CentliPickerFormField(
              key: ValueKey('ledger_$_ledgerId'),
              label: '入账账本',
              value: _ledgerLabel,
              enabled: !_busy && widget.ledgers.length > 1,
              isDense: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 18,
              ),
              onTap: _pickLedger,
            ),
            const SizedBox(height: CentliSpacing.item + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('confirm_pending_amount'),
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '金额 ($ccy)',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CentliSpacing.item + 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final cat = _categoryById(_categoryId);
                      return CentliPickerFormField(
                        key: ValueKey('cat_${_categoryId ?? ''}_$_direction'),
                        label: '分类',
                        value: cat?.name ?? '选择分类',
                        enabled: !_busy,
                        isDense: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 18,
                        ),
                        leading: cat == null
                            ? null
                            : CentliIconChip(
                                name: cat.name,
                                kind: cat.kind,
                                iconKey: cat.icon,
                                size: 22,
                              ),
                        onTap: _pickCategory,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final acc = _accountById(_accountId);
                      return CentliPickerFormField(
                        key: ValueKey('acc_${_accountId ?? ''}'),
                        label: '资产账户',
                        value: acc?.name ?? '选择资产账户',
                        enabled: !_busy,
                        isDense: false,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 18,
                        ),
                        leading: acc == null
                            ? null
                            : CentliIconChip(
                                name: acc.name,
                                kind: 'account',
                                iconKey: acc.icon,
                                size: 22,
                              ),
                        onTap: _pickAccount,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: CentliSpacing.item),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('confirm_pending_submit'),
                  onPressed: _busy ? null : _confirm,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('入账'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
