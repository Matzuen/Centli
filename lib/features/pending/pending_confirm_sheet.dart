import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../core/widgets/glass.dart';

/// 一条待确认通知里，「方向」的显示名。
String pendingDirectionLabel(String? direction) {
  switch (NotiTemplate.normalizeDirection(direction)) {
    case 'in':
      return '收入';
    case 'refund':
      return '退款';
    case 'repay':
      return '还款';
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
  // 分类 / 资产账户选项：只加载一次，交给弹窗同步渲染。
  final out = await db.loadCategories(capture.ledgerId, 'out');
  final inn = await db.loadCategories(capture.ledgerId, 'in');
  final accounts = await db.loadActiveAccounts(capture.ledgerId);
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
    ),
  );
  return saved == true;
}

class _ConfirmPendingSheet extends ConsumerStatefulWidget {
  const _ConfirmPendingSheet({
    required this.capture,
    required this.categories,
    required this.accounts,
  });

  final PendingCapture capture;
  final List<Category> categories;
  final List<Account> accounts;

  @override
  ConsumerState<_ConfirmPendingSheet> createState() =>
      _ConfirmPendingSheetState();
}

class _ConfirmPendingSheetState extends ConsumerState<_ConfirmPendingSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  String? _categoryId;
  String? _accountId;
  String? _directionOverride;
  var _busy = false;
  var _includeRepayInStat = false;

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
      for (final x in widget.categories)
        if (x.kind == (wantIn ? 'in' : 'out')) x,
    ];
    return wanted.isNotEmpty ? wanted : widget.categories;
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
    _noteCtrl = TextEditingController(text: c.note ?? '');
    final cats = _catsForDirection;
    final suggested = c.suggestedCategoryId;
    _categoryId = cats.any((x) => x.id == suggested)
        ? suggested
        : (cats.isNotEmpty ? cats.first.id : null);
    final accounts = widget.accounts;
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
      final inCats = widget.categories.where((x) => x.kind == 'in');
      final outCats = widget.categories.where((x) => x.kind == 'out');
      final known = outCats.any((x) => x.id == _categoryId) ||
          inCats.any((x) => x.id == _categoryId);
      final String txnType;
      if (_direction == 'refund') {
        txnType = 'refund';
      } else if (!known) {
        txnType = 'out';
      } else {
        txnType = inCats.any((x) => x.id == _categoryId) ? 'in' : 'out';
      }
      final isRepay = _direction == 'repay';
      final include = isRepay ? (_includeRepayInStat ? 1 : 0) : 1;
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
      await ref.read(databaseProvider).confirmPendingCapture(
            pendingId: c.id,
            amountMinor: toMinor(ccy, major),
            currency: ccy,
            accountId: _accountId!,
            categoryId: _categoryId!,
            note: _noteCtrl.text.trim().isEmpty
                ? null
                : _noteCtrl.text.trim(),
            merchantForRule: parsedForRule.merchant,
            type: isRepay ? 'out' : txnType,
            includeInStat: include,
            includeInBudget: include,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ccy = c.currency ?? 'CNY';
    final cats = _catsForDirection;
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
                PopupMenuButton<String>(
                  key: const Key('confirm_pending_type'),
                  initialValue: _direction,
                  onSelected: _busy
                      ? null
                      : (dir) {
                          setState(() {
                            _directionOverride = dir;
                            final cats = _catsForDirection;
                            if (!cats.any((x) => x.id == _categoryId)) {
                              _categoryId =
                                  cats.isEmpty ? null : cats.first.id;
                            }
                          });
                        },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'out', child: Text('支出')),
                    PopupMenuItem(value: 'in', child: Text('收入')),
                    PopupMenuItem(value: 'refund', child: Text('退款')),
                    PopupMenuItem(value: 'repay', child: Text('还款')),
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
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('confirm_pending_amount'),
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '金额 ($ccy)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('acc_${_accountId ?? ''}'),
                    initialValue: _accountId,
                    isExpanded: true,
                    items: [
                      for (final a in widget.accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${a.name} · ${a.currency}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _accountId = v),
                    decoration: const InputDecoration(
                      labelText: '资产账户',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CentliSpacing.item),
            DropdownButtonFormField<String>(
              key: ValueKey('cat_${_categoryId ?? ''}_$_direction'),
              initialValue: _categoryId,
              isExpanded: true,
              items: [
                for (final cat in cats)
                  DropdownMenuItem(value: cat.id, child: Text(cat.name)),
              ],
              onChanged:
                  _busy ? null : (v) => setState(() => _categoryId = v),
              decoration: const InputDecoration(
                labelText: '分类',
                isDense: true,
              ),
            ),
            const SizedBox(height: CentliSpacing.item),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '备注',
                isDense: true,
              ),
            ),
            if (_direction == 'repay') ...[
              const SizedBox(height: CentliSpacing.item),
              Text(
                '还款默认不计入收支统计，避免与花呗消费重复计算',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('计入统计'),
                value: _includeRepayInStat,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _includeRepayInStat = v),
              ),
            ],
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
