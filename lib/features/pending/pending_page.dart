import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../capture/capture_intake_actions.dart';
import 'pending_confirm_sheet.dart';
import '../../app/theme.dart';


/// Badge label for pending capture cards. Status takes priority over parseOk.
@visibleForTesting
String? pendingCaptureBadgeLabel({
  required String status,
  required int parseOk,
}) {
  if (status == 'confirmed') return '已入账';
  if (status == 'ignored') return '已忽略';
  if (status == 'pending' && parseOk == 0) return '解析失败';
  return null;
}

final _pendingFilterProvider = StateProvider<String>((ref) => 'pending');

final _pendingListProvider =
    StreamProvider.family<List<PendingCapture>, ({String ledgerId, String status})>(
  (ref, args) {
    final db = ref.watch(databaseProvider);
    // Strict partition: pending(ok) / parse_failed / ignored / confirmed.
    // Legacy route tab=all maps to confirmed (see initState).
    final status = args.status == 'all' ? 'confirmed' : args.status;
    if (status == 'confirmed') {
      return db.watchConfirmedCaptures(args.ledgerId);
    }
    if (status == 'parse_failed') {
      return db.watchParseFailedCaptures(args.ledgerId);
    }
    if (status == 'pending') {
      return db.watchPendingOkCaptures(args.ledgerId);
    }
    return db.watchPendingCaptures(args.ledgerId, status: status);
  },
);

class PendingPage extends ConsumerStatefulWidget {
  const PendingPage({super.key, this.initialFilter});

  /// Optional tab: pending | parse_failed | ignored | confirmed
  /// (`all` accepted as legacy alias for confirmed).
  final String? initialFilter;

  @override
  ConsumerState<PendingPage> createState() => _PendingPageBodyState();
}

class _PendingPageBodyState extends ConsumerState<PendingPage> {
  Future<({List<Category> cats, List<Account> accounts})>? _listsFuture;

  Future<({List<Category> cats, List<Account> accounts})> _loadLists(
    String ledgerId,
  ) {
    return _listsFuture ??= () async {
      final db = ref.read(databaseProvider);
      final out = await db.loadCategories(ledgerId, 'out');
      final inn = await db.loadCategories(ledgerId, 'in');
      final accounts = await db.loadActiveAccounts(ledgerId);
      return (cats: [...out, ...inn], accounts: accounts);
    }();
  }

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilter;
    if (f != null &&
        // 'all' kept only as legacy alias for confirmed (router ?tab=all).
        {'pending', 'parse_failed', 'ignored', 'confirmed', 'all'}
            .contains(f)) {
      // Legacy route ?tab=all → confirmed (partition replaced "全部").
      final mapped = f == 'all' ? 'confirmed' : f;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_pendingFilterProvider.notifier).state = mapped;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final filter = ref.watch(_pendingFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('待确认'),
        actions: [
          // 6 个动作收进「更多」，顶栏只留一个入口。
          PopupMenuButton<String>(
            key: const Key('pending_more_menu'),
            tooltip: '更多',
            onSelected: (v) => _onPendingAction(context, v),
            itemBuilder: (ctx) => [
              if (filter == 'pending' || filter == 'parse_failed')
                const PopupMenuItem(
                  value: 'ignore_all',
                  child: ListTile(
                    leading: Icon(Icons.playlist_remove_outlined),
                    title: Text('全部忽略'),
                  ),
                ),
              if (filter == 'ignored')
                const PopupMenuItem(
                  value: 'clear_ignored',
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('清空已忽略'),
                  ),
                ),
              if (filter != 'ignored')
                const PopupMenuItem(
                  value: 'screenshot',
                  child: ListTile(
                    leading: Icon(Icons.document_scanner_outlined),
                    title: Text('截图识别'),
                  ),
                ),
              if (filter != 'ignored')
                const PopupMenuItem(
                  value: 'clipboard',
                  child: ListTile(
                    leading: Icon(Icons.content_paste_go_outlined),
                    title: Text('从剪贴板导入'),
                  ),
                ),
              const PopupMenuItem(
                value: 'help',
                child: ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('发出去没通知？'),
                ),
              ),
              if (kDebugMode)
                const PopupMenuItem(
                  value: 'sample',
                  child: ListTile(
                    leading: Icon(Icons.science_outlined),
                    title: Text('添加示例通知'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('尚未初始化账本'));
          }
          final listAsync = ref.watch(
            _pendingListProvider((ledgerId: ledger.id, status: filter)),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(CentliSpacing.pageH, CentliSpacing.item, CentliSpacing.pageH, 0),
                child: Center(
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    segments: const [
                      ButtonSegment(value: 'pending', label: Text('待确认')),
                      ButtonSegment(
                        value: 'parse_failed',
                        label: Text('解析失败'),
                      ),
                      ButtonSegment(value: 'ignored', label: Text('已忽略')),
                      ButtonSegment(value: 'confirmed', label: Text('已入账')),
                    ],
                    selected: {filter},
                    onSelectionChanged: (s) {
                      ref.read(_pendingFilterProvider.notifier).state = s.first;
                    },
                  ),
                ),
              ),
              Expanded(
                child: listAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (items) {
                    if (items.isEmpty) {
                      final title = filter == 'pending'
                          ? '暂无待确认账单'
                          : filter == 'parse_failed'
                              ? '暂无解析失败项'
                              : filter == 'ignored'
                                  ? '暂无已忽略记录'
                                  : filter == 'confirmed'
                                      ? '暂无已入账记录'
                                      : '暂无记录';
                      final msg = filter == 'pending'
                          ? '开启自动记账后，支付成功通知会集中在此确认入账。'
                              '发出去的红包/转账往往没有通知，可用截图识别或剪贴板导入。'
                          : filter == 'parse_failed'
                              ? '解析失败的通知会出现在这里，可到「识别规则」页点「试一试」调整模板。'
                              : filter == 'ignored'
                                  ? '忽略的待确认会出现在这里；可清空以释放空间。'
                                  : filter == 'confirmed'
                                      ? '已确认入账的捕获会出现在这里。'
                                      : '切换上方筛选查看不同状态的捕获记录。';
                      return CentliEmptyState(
                        icon: Icons.pending_actions_outlined,
                        title: title,
                        message: msg,
                        action: filter == 'pending' || filter == 'parse_failed'
                            ? Wrap(
                                alignment: WrapAlignment.center,
                                spacing: CentliSpacing.item,
                                runSpacing: CentliSpacing.item,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        context.push('/me/auto'),
                                    icon: const Icon(Icons.auto_awesome_outlined),
                                    label: const Text('自动记账'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => importCaptureFromScreenshot(context, ref),
                                    icon: const Icon(
                                      Icons.document_scanner_outlined,
                                    ),
                                    label: const Text('截图识别'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => importCaptureFromClipboard(context, ref),
                                    icon: const Icon(
                                      Icons.content_paste_go_outlined,
                                    ),
                                    label: const Text('剪贴板'),
                                  ),
                                ],
                              )
                            : null,
                      );
                    }
                    return FutureBuilder<
                        ({List<Category> cats, List<Account> accounts})>(
                      future: _loadLists(ledger.id),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final cats = snap.data!.cats;
                        final accounts = snap.data!.accounts;
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            CentliSpacing.pageH,
                            CentliSpacing.section,
                            CentliSpacing.pageH,
                            CentliSpacing.pageBottom,
                          ),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: CentliSpacing.item),
                          itemBuilder: (context, i) {
                            final capture = items[i];
                            return _PendingCard(
                              key: ValueKey(capture.id),
                              capture: capture,
                              ledgerId: ledger.id,
                              categories: cats,
                              accounts: accounts,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  Future<void> _onPendingAction(BuildContext context, String value) async {
    switch (value) {
      case 'ignore_all':
        await _ignoreAll(context);
      case 'clear_ignored':
        await _clearIgnored(context);
      case 'screenshot':
        await importCaptureFromScreenshot(context, ref);
      case 'clipboard':
        await importCaptureFromClipboard(context, ref);
      case 'help':
        if (context.mounted) context.push('/me/auto/manual-help');
      case 'sample':
        final ledger = ref.read(currentLedgerProvider).valueOrNull;
        if (ledger == null) return;
        final db = ref.read(databaseProvider);
        final templates = await NotiTemplateStore.load();
        final n = await seedSamplePendingCaptures(
          ledgerId: ledger.id,
          ingest: db.ingestParsedNotification,
          templates: templates,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(n == 0 ? '示例已存在（去重）' : '已加入 $n 条示例')),
          );
        }
    }
  }

  Future<void> _ignoreAll(BuildContext context) async {
    final ledger = ref.read(currentLedgerProvider).valueOrNull;
    if (ledger == null) return;
    final count =
        await ref.read(databaseProvider).countPendingCaptures(ledger.id);
    if (count == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无待确认账单')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部忽略'),
        content: Text('将忽略当前账本下 $count 条待确认记录（可在「已忽略」查看）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部忽略'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n =
        await ref.read(databaseProvider).ignoreAllPendingCaptures(ledger.id);
    await NotificationCaptureStub.cancelAllPendingConfirm();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? '没有可忽略的记录' : '已忽略 $n 条')),
      );
    }
  }

  Future<void> _clearIgnored(BuildContext context) async {
    final ledger = ref.read(currentLedgerProvider).valueOrNull;
    if (ledger == null) return;
    final ignored = await ref
        .read(databaseProvider)
        .watchPendingCaptures(ledger.id, status: 'ignored')
        .first;
    final count = ignored.length;
    if (count == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无已忽略记录')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空已忽略'),
        content: Text('将永久删除 $count 条已忽略记录，不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n =
        await ref.read(databaseProvider).clearIgnoredCaptures(ledger.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? '无记录' : '已清空 $n 条')),
      );
    }
  }

}

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({
    super.key,
    required this.capture,
    required this.ledgerId,
    required this.categories,
    required this.accounts,
  });
  final PendingCapture capture;
  final String ledgerId;
  final List<Category> categories;
  final List<Account> accounts;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  late String? _categoryId;
  late String? _accountId;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _amountCtrl;
  bool _busy = false;
  bool _expanded = false;
  bool _categoryFallback = false;
  bool _accountFallback = false;
  /// Repay default: exclude from stats/budget (T0B-5).
  bool _includeRepayInStat = false;

  PendingCapture get c => widget.capture;

  @override
  void initState() {
    super.initState();
    _noteCtrl = TextEditingController(text: c.note ?? '');
    final ccy = c.currency ?? 'CNY';
    final amt = c.amountMinor;
    _amountCtrl = TextEditingController(
      text: amt == null
          ? ''
          : fromMinor(ccy, amt).toStringAsFixed(
              (ccy == 'JPY') ? 0 : 2,
            ),
    );
    _applySuggestions();
  }

  @override
  void didUpdateWidget(covariant _PendingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories ||
        oldWidget.accounts != widget.accounts ||
        oldWidget.capture.id != widget.capture.id) {
      _applySuggestions();
    }
  }

  void _applySuggestions() {
    final cats = widget.categories;
    final accounts = widget.accounts;
    // T1-5: prefer category kind matching parse direction (refund → out).
    // Confirm still derives txn type from category kind (B1-2).
    final preferredKind = _direction == 'in' ? 'in' : 'out';
    final preferred =
        cats.where((x) => x.kind == preferredKind).toList(growable: false);
    final pool = preferred.isNotEmpty ? preferred : cats;

    var catId = c.suggestedCategoryId;
    var catFb = false;
    if (pool.isNotEmpty) {
      final suggestedOk =
          catId != null && cats.any((x) => x.id == catId);
      final suggestedMatchesKind = suggestedOk &&
          preferred.any((x) => x.id == catId);
      if (!suggestedOk || (preferred.isNotEmpty && !suggestedMatchesKind)) {
        catId = pool.first.id;
        catFb = catId != c.suggestedCategoryId;
      }
    } else {
      catId = null;
    }
    var accId = c.suggestedAccountId;
    var accFb = false;
    if (accounts.isNotEmpty) {
      if (accId == null || !accounts.any((x) => x.id == accId)) {
        accId = accounts.first.id;
        accFb = accId != c.suggestedAccountId;
      }
    } else {
      accId = null;
    }
    _categoryId = catId;
    _accountId = accId;
    _categoryFallback = catFb;
    _accountFallback = accFb;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String get _categoryName {
    final id = _categoryId;
    if (id == null) return '未选分类';
    for (final cat in widget.categories) {
      if (cat.id == id) return cat.name;
    }
    return '未选分类';
  }

  String get _accountName {
    final id = _accountId;
    if (id == null) return '未选账户';
    for (final a in widget.accounts) {
      if (a.id == id) return a.name;
    }
    return '未选账户';
  }

  /// Prefer persisted direction; fall back to re-parse.
  String get _direction {
    final stored = c.direction?.trim();
    if (stored != null && stored.isNotEmpty) {
      return NotiTemplate.normalizeDirection(stored);
    }
    final templates = NotiTemplateStore.peek();
    final raw = RawNotification(
      pkg: c.sourcePkg,
      title: c.rawTitle ?? '',
      text: c.rawText,
      whenMs: c.happenAt ?? c.createdAt,
    );
    final parsed = parseNotification(
      raw,
      templates.isEmpty ? null : templates,
    );
    return NotiTemplate.normalizeDirection(parsed.direction);
  }

  String get _directionLabel {
    switch (_direction) {
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

  String get _amountLabel {
    final ccy = c.currency ?? 'CNY';
    final raw = _amountCtrl.text.trim();
    if (raw.isEmpty) {
      if (c.amountMinor == null) return '金额未知';
      return formatMinor(ccy, c.amountMinor!);
    }
    final major = double.tryParse(raw.replaceAll(',', ''));
    if (major == null) return raw;
    return formatMinor(ccy, toMinor(ccy, major));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ccy = c.currency ?? 'CNY';
    final when = c.happenAt == null
        ? '—'
        : DateFormat('MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(c.happenAt!),
          );
    final isPending = c.status == 'pending';
    final merchant = _noteCtrl.text.trim().isEmpty
        ? ((c.note ?? '').isEmpty ? '无备注' : c.note!)
        : _noteCtrl.text.trim();

    return CentliSoftCard(
      child: Padding(
        padding: const EdgeInsets.all(CentliSpacing.cardPad - 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$when · ${_pkgLabel(c.sourcePkg)}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                // Badge by status first (not parseOk): confirmed stays 已入账.
                Builder(
                  builder: (context) {
                    final label = pendingCaptureBadgeLabel(
                      status: c.status,
                      parseOk: c.parseOk,
                    );
                    if (label == null) return const SizedBox.shrink();
                    return Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: label == '解析失败'
                          ? scheme.errorContainer
                          : null,
                    );
                  },
                ),
              ],
            ),
            if (isPending) ...[
              if (!_expanded) ...[
                const SizedBox(height: CentliSpacing.item),
                Text(
                  '$_directionLabel · $_amountLabel · $merchant · $_categoryName · $_accountName',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (_direction == 'repay') ...[
                  const SizedBox(height: CentliSpacing.item),
                  Text(
                    '还款不计入收支统计，避免与花呗消费重复计算',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                if (_categoryFallback || _accountFallback)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (_categoryFallback) '分类已回落第一项',
                        if (_accountFallback) '账户已回落第一项',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ),
                const SizedBox(height: CentliSpacing.item),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _ignore,
                      child: const Text('忽略'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await showPendingConfirmDialog(
                                context,
                                ref,
                                capture: c,
                              );
                              if (ok) {
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('已入账')),
                                );
                              }
                            },
                      child: const Text('调整'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: const Text('入账'),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: CentliSpacing.item),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '金额 ($ccy)',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: CentliSpacing.item),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: CentliSpacing.item),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId != null &&
                          widget.categories.any((x) => x.id == _categoryId)
                      ? _categoryId
                      : null,
                  items: [
                    for (final cat in widget.categories)
                      DropdownMenuItem(value: cat.id, child: Text(cat.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _categoryId = v;
                    _categoryFallback = false;
                  }),
                  decoration: InputDecoration(
                    labelText: '分类',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    isDense: true,
                    enabledBorder: _categoryFallback
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: scheme.error,
                              width: 1.2,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: CentliSpacing.item),
                DropdownButtonFormField<String>(
                  initialValue: _accountId != null &&
                          widget.accounts.any((x) => x.id == _accountId)
                      ? _accountId
                      : null,
                  items: [
                    for (final a in widget.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text('${a.name} · ${a.currency}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _accountId = v;
                    _accountFallback = false;
                  }),
                  decoration: InputDecoration(
                    labelText: '账户',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    isDense: true,
                    enabledBorder: _accountFallback
                        ? OutlineInputBorder(
                            borderSide: BorderSide(
                              color: scheme.error,
                              width: 1.2,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: CentliSpacing.dense),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      '原文',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          c.rawText,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CentliSpacing.item),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _ignore,
                      child: const Text('忽略'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _expanded = false),
                      child: const Text('收起'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: const Text('入账'),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Text(
                c.amountMinor == null
                    ? '金额未知'
                    : formatMinor(ccy, c.amountMinor!),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if ((c.note ?? '').isNotEmpty) Text(c.note!),
              Text(
                c.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _ignore() async {
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).ignorePendingCapture(c.id);
      await NotificationCaptureStub.cancelPendingConfirm(c.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final ccy = c.currency ?? 'CNY';
    final major = double.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择账户')),
      );
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择分类')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // Resolve type from already-loaded category lists (parent provider).
      final inCats = widget.categories.where((x) => x.kind == 'in');
      final outCats = widget.categories.where((x) => x.kind == 'out');
      final known = outCats.any((x) => x.id == _categoryId) ||
          inCats.any((x) => x.id == _categoryId);
      // T4-2: direction refund maps to type refund (never income).
      final String txnType;
      if (_direction == 'refund') {
        txnType = 'refund';
      } else if (!known) {
        txnType = 'out'; // deleted/archived category → fallback expense
      } else {
        txnType = inCats.any((x) => x.id == _categoryId) ? 'in' : 'out';
      }
      final isRepay = _direction == 'repay';
      final include = isRepay ? (_includeRepayInStat ? 1 : 0) : 1;
      // Merchant text for auto-categorize rules (not stored as a column).
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已入账')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('入账失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
    if (pkg.contains('tencent.mm')) return '微信';
    if (pkg.startsWith('manual:')) {
      final kind = pkg.substring('manual:'.length);
      switch (kind) {
        case 'share':
          return '分享导入';
        case 'share_image':
          return '分享图片';
        case 'clipboard':
          return '剪贴板导入';
        case 'ocr':
          return '截图识别';
        case 'url':
          return '快捷指令';
        default:
          return '手动导入';
      }
    }
    return '其它应用';
  }
}
