import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../platform/pending/pending_capture_intake.dart';
import '../../app/theme.dart';

final _pendingFilterProvider = StateProvider<String>((ref) => 'pending');

final _pendingListProvider =
    StreamProvider.family<List<PendingCapture>, ({String ledgerId, String status})>(
  (ref, args) {
    final db = ref.watch(databaseProvider);
    if (args.status == 'all') {
      return db.watchAllCaptures(args.ledgerId);
    }
    if (args.status == 'parse_failed') {
      return db.watchParseFailedCaptures(args.ledgerId);
    }
    return db.watchPendingCaptures(args.ledgerId, status: args.status);
  },
);

class PendingPage extends ConsumerStatefulWidget {
  const PendingPage({super.key, this.initialFilter});

  /// Optional tab: pending | parse_failed | ignored | all
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
        {'pending', 'parse_failed', 'ignored', 'all'}.contains(f)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_pendingFilterProvider.notifier).state = f;
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
          if (filter == 'pending' || filter == 'parse_failed')
            IconButton(
              tooltip: '全部忽略',
              icon: const Icon(Icons.playlist_remove_outlined),
              onPressed: () => _ignoreAll(context),
            ),
          if (filter == 'ignored')
            IconButton(
              tooltip: '清空已忽略',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clearIgnored(context),
            ),
          IconButton(
            tooltip: '从截图识别',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => _fromScreenshot(context),
          ),
          IconButton(
            tooltip: '从剪贴板导入',
            icon: const Icon(Icons.content_paste_go_outlined),
            onPressed: () => _fromClipboard(context),
          ),
          IconButton(
            tooltip: '发出去没通知？',
            icon: const Icon(Icons.help_outline),
            onPressed: () => context.push('/me/auto/manual-help'),
          ),
          if (kDebugMode)
            IconButton(
            tooltip: '添加示例通知',
            icon: const Icon(Icons.science_outlined),
            onPressed: () async {
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
                  SnackBar(
                    content: Text(
                      n == 0 ? '示例已存在（去重）' : '已加入 $n 条示例',
                    ),
                  ),
                );
              }
            },
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pending', label: Text('待确认')),
                      ButtonSegment(
                        value: 'parse_failed',
                        label: Text('解析失败'),
                      ),
                      ButtonSegment(value: 'ignored', label: Text('已忽略')),
                      ButtonSegment(value: 'all', label: Text('全部')),
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
                                  : '暂无记录';
                      final msg = filter == 'pending'
                          ? '开启自动记账后，支付成功通知会集中在此确认入账。'
                              '发出去的红包/转账往往没有通知，可用截图识别或剪贴板导入。'
                          : filter == 'parse_failed'
                              ? '解析失败的通知会出现在这里，可对照「识别规则 · 试一试」调整模板。'
                              : filter == 'ignored'
                                  ? '忽略的待确认会出现在这里；可清空以释放空间。'
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
                                    onPressed: () => _fromScreenshot(context),
                                    icon: const Icon(
                                      Icons.document_scanner_outlined,
                                    ),
                                    label: const Text('截图识别'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _fromClipboard(context),
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
                              const SizedBox(height: 8),
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


  Future<void> _fromClipboard(BuildContext context) async {
    final db = ref.read(databaseProvider);
    final result = await PendingCaptureIntake.ingestClipboard(db);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.snackbarText())),
    );
  }

  Future<void> _fromScreenshot(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 92);
    if (file == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在识别截图…')),
    );
    final db = ref.read(databaseProvider);
    final result = await PendingCaptureIntake.ingestImagePath(
      db,
      file.path,
      sourceKind: 'ocr',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.snackbarText())),
    );
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
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  bool _busy = false;
  bool _expanded = false;
  bool _categoryFallback = false;
  bool _accountFallback = false;

  PendingCapture get c => widget.capture;

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: c.merchant ?? '');
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
    var catId = c.suggestedCategoryId;
    var catFb = false;
    if (cats.isNotEmpty) {
      if (catId == null || !cats.any((x) => x.id == catId)) {
        catId = cats.first.id;
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
    _merchantCtrl.dispose();
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
    final merchant = _merchantCtrl.text.trim().isEmpty
        ? ((c.merchant ?? '').isEmpty ? '无商户' : c.merchant!)
        : _merchantCtrl.text.trim();

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
                if (c.parseOk == 0)
                  Chip(
                    label: const Text('解析失败'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.errorContainer,
                  )
                else if (!isPending)
                  Chip(
                    label: Text(c.status == 'confirmed' ? '已入账' : '已忽略'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (isPending) ...[
              if (!_expanded) ...[
                const SizedBox(height: 6),
                Text(
                  '$_amountLabel · $merchant · $_categoryName · $_accountName',
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
                        if (_accountFallback) '账户已回落第一项',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ),
                const SizedBox(height: 8),
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
                          : () => setState(() => _expanded = true),
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
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '金额 ($ccy)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(
                    labelText: '商户',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
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
                    border: const OutlineInputBorder(),
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
                const SizedBox(height: 8),
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
                    border: const OutlineInputBorder(),
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
                const SizedBox(height: 4),
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
                const SizedBox(height: 8),
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
              if ((c.merchant ?? '').isNotEmpty) Text(c.merchant!),
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
      final txnType = !known
          ? 'out' // deleted/archived category → fallback expense
          : (inCats.any((x) => x.id == _categoryId) ? 'in' : 'out');
      await ref.read(databaseProvider).confirmPendingCapture(
            pendingId: c.id,
            amountMinor: toMinor(ccy, major),
            currency: ccy,
            accountId: _accountId!,
            categoryId: _categoryId!,
            merchant: _merchantCtrl.text.trim().isEmpty
                ? null
                : _merchantCtrl.text.trim(),
            type: txnType,
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
