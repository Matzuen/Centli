import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/picker_form_field.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../capture/capture_intake_actions.dart';
import '../ledger/account_picker_sheet.dart';
import '../ledger/category_picker_sheet.dart';
import 'pending_confirm_sheet.dart';


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
    // Re-subscribe after native SQLite writes that Drift streams miss.
    ref.watch(pendingExternalWriteTickProvider);
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
  const PendingPage({
    super.key,
    this.initialFilter,
    this.focusPendingId,
    this.openConfirm = false,
  });

  /// Optional tab: pending | parse_failed | ignored | confirmed
  /// (`all` accepted as legacy alias for confirmed).
  final String? initialFilter;

  /// Deep-link target from notification tap / 「确认」 action.
  final String? focusPendingId;

  /// When true, open [showPendingConfirmDialog] for [focusPendingId].
  final bool openConfirm;

  @override
  ConsumerState<PendingPage> createState() => _PendingPageBodyState();
}

class _PendingPageBodyState extends ConsumerState<PendingPage> {
  Future<({List<Category> cats, List<Account> accounts})>? _listsFuture;
  String? _handledFocusId;

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
    final focus = widget.focusPendingId;
    if (focus != null && focus.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_focusPending(focus, openConfirm: widget.openConfirm));
      });
    }
  }

  Future<void> _focusPending(String id, {required bool openConfirm}) async {
    if (!mounted || _handledFocusId == id) return;
    _handledFocusId = id;
    // Native insert may land just before we open — tick + short retry.
    final db = ref.read(databaseProvider);
    notifyExternalSqliteWrite(
      db,
      ref.read(pendingExternalWriteTickProvider.notifier),
    );
    PendingCapture? capture;
    for (var i = 0; i < 6; i++) {
      capture = await db.getPendingCapture(id);
      if (capture != null) break;
      await Future<void>.delayed(Duration(milliseconds: 120 * (i + 1)));
      if (!mounted) return;
    }
    if (!mounted) return;
    if (capture == null) {
      showGlassSnackBar(context, '未找到这条待确认，请下拉刷新或稍后再试');
      return;
    }
    final tab = capture.status == 'ignored'
        ? 'ignored'
        : capture.status == 'pending'
            ? (capture.parseOk == 1 ? 'pending' : 'parse_failed')
            : 'confirmed';
    ref.read(_pendingFilterProvider.notifier).state = tab;
    if (!openConfirm || capture.status != 'pending') return;
    await showPendingConfirmDialog(context, ref, capture: capture);
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final filter = ref.watch(_pendingFilterProvider);

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('待确认'),
        actions: [
          // 6 个动作收进「更多」，顶栏只留一个入口。
          CentliGlassPopupButton<String>(
            key: const Key('pending_more_menu'),
            tooltip: '更多',
            maxWidth: 220,
            onSelected: (v) => _onPendingAction(context, v),
            items: [
              if (filter == 'pending' || filter == 'parse_failed')
                const CentliMenuItem(
                  value: 'ignore_all',
                  label: '全部忽略',
                  icon: Icons.playlist_remove_outlined,
                ),
              if (filter == 'ignored')
                const CentliMenuItem(
                  value: 'clear_ignored',
                  label: '清空已忽略',
                  icon: Icons.delete_sweep_outlined,
                ),
              if (filter != 'ignored')
                const CentliMenuItem(
                  value: 'screenshot',
                  label: '截图识别',
                  icon: Icons.document_scanner_outlined,
                ),
              if (filter != 'ignored')
                const CentliMenuItem(
                  value: 'clipboard',
                  label: '从剪贴板导入',
                  icon: Icons.content_paste_go_outlined,
                ),
              const CentliMenuItem(
                value: 'help',
                label: '发出去没通知？',
                icon: Icons.help_outline,
              ),
              if (kDebugMode)
                const CentliMenuItem(
                  value: 'sample',
                  label: '添加示例通知',
                  icon: Icons.science_outlined,
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
            return const Center(child: Text('尚未初始化记账本'));
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
          showGlassSnackBar(context, n == 0 ? '示例已存在（去重）' : '已加入 $n 条示例');
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
        showGlassSnackBar(context, '暂无待确认账单');
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('全部忽略'),
        content: Text('将忽略当前记账本下 $count 条待确认记录（可在「已忽略」查看）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
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
      showGlassSnackBar(context, n == 0 ? '没有可忽略的记录' : '已忽略 $n 条');
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
        showGlassSnackBar(context, '暂无已忽略记录');
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('清空已忽略'),
        content: Text('将永久删除 $count 条已忽略记录，不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
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
      showGlassSnackBar(context, n == 0 ? '无记录' : '已清空 $n 条');
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
    // Prefer category kind matching parse direction (in → income cats).
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
    if (id == null) return '未选资产账户';
    for (final a in widget.accounts) {
      if (a.id == id) return a.name;
    }
    return '未选资产账户';
  }

  Category? get _selectedCategory {
    final id = _categoryId;
    if (id == null) return null;
    for (final cat in widget.categories) {
      if (cat.id == id) return cat;
    }
    return null;
  }

  Account? get _selectedAccount {
    final id = _accountId;
    if (id == null) return null;
    for (final a in widget.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Category> get _catsForDirection {
    final preferredKind = _direction == 'in' ? 'in' : 'out';
    final preferred = [
      for (final x in widget.categories)
        if (x.kind == preferredKind) x,
    ];
    return preferred.isNotEmpty ? preferred : widget.categories;
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _catsForDirection,
      selectedId: _categoryId,
    );
    if (id == null || !mounted) return;
    setState(() {
      _categoryId = id;
      _categoryFallback = false;
    });
  }

  Future<void> _pickAccount() async {
    final types =
        await ref.read(databaseProvider).loadAssetTypes(widget.ledgerId);
    if (!mounted) return;
    final id = await showAccountPickerSheet(
      context,
      accounts: widget.accounts,
      assetTypes: types,
      selectedId: _accountId,
    );
    if (id == null || !mounted) return;
    setState(() {
      _accountId = id;
      _accountFallback = false;
    });
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
                if (_categoryFallback || _accountFallback)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (_categoryFallback) '分类已回落第一项',
                        if (_accountFallback) '资产账户已回落第一项',
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
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _busy ? null : _ignore,
                      child: const Text('忽略'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await showPendingConfirmDialog(
                                context,
                                ref,
                                capture: c,
                              );
                              if (ok && context.mounted) {
                                showGlassSnackBar(context, '已入账');
                              }
                            },
                      child: const Text('调整'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
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
                Builder(
                  builder: (context) {
                    final cat = _selectedCategory;
                    return CentliPickerFormField(
                      label: '分类',
                      value: cat?.name ?? '选择分类',
                      outlined: true,
                      error: _categoryFallback,
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
                const SizedBox(height: CentliSpacing.item),
                Builder(
                  builder: (context) {
                    final acc = _selectedAccount;
                    return CentliPickerFormField(
                      label: '资产账户',
                      value: acc == null
                          ? '选择资产账户'
                          : '${acc.name} · ${acc.currency}',
                      outlined: true,
                      error: _accountFallback,
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
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
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
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
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
      showGlassSnackBar(context, '请输入有效金额');
      return;
    }
    if (_accountId == null) {
      showGlassSnackBar(context, '请选择资产账户');
      return;
    }
    if (_categoryId == null) {
      showGlassSnackBar(context, '请选择分类');
      return;
    }
    setState(() => _busy = true);
    try {
      // Resolve type from already-loaded category lists (parent provider).
      final inCats = widget.categories.where((x) => x.kind == 'in');
      final outCats = widget.categories.where((x) => x.kind == 'out');
      final known = outCats.any((x) => x.id == _categoryId) ||
          inCats.any((x) => x.id == _categoryId);
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
          );
      await NotificationCaptureStub.cancelPendingConfirm(c.id);
      if (mounted) {
        showGlassSnackBar(context, '已入账');
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, '入账失败: $e');
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
