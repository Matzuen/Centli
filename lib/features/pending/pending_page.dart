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
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(CentliSpacing.pageH, CentliSpacing.section, CentliSpacing.pageH, CentliSpacing.pageBottom),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final capture = items[i];
                        return _PendingCard(
                          key: ValueKey(capture.id),
                          capture: capture,
                          ledgerId: ledger.id,
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
  const _PendingCard({super.key, required this.capture, required this.ledgerId});
  final PendingCapture capture;
  final String ledgerId;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  late String? _categoryId;
  late String? _accountId;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _amountCtrl;
  bool _busy = false;

  PendingCapture get c => widget.capture;

  @override
  void initState() {
    super.initState();
    _categoryId = c.suggestedCategoryId;
    _accountId = c.suggestedAccountId;
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
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
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
            const SizedBox(height: 4),
            if (isPending) ...[
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '金额 ($ccy)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _merchantCtrl,
                decoration: const InputDecoration(
                  labelText: '商户',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Category>>(
                future: () async {
                  final db = ref.read(databaseProvider);
                  final out = await db.loadCategories(widget.ledgerId, 'out');
                  final inn = await db.loadCategories(widget.ledgerId, 'in');
                  return [...out, ...inn];
                }(),
                builder: (context, snap) {
                  final cats = snap.data ?? const <Category>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _categoryId != null &&
                            cats.any((x) => x.id == _categoryId)
                        ? _categoryId
                        : null,
                    items: [
                      for (final cat in cats)
                        DropdownMenuItem(value: cat.id, child: Text(cat.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                    decoration: const InputDecoration(
                      labelText: '分类',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Account>>(
                future: ref
                    .read(databaseProvider)
                    .loadActiveAccounts(widget.ledgerId),
                builder: (context, snap) {
                  final accounts = snap.data ?? const <Account>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _accountId != null &&
                            accounts.any((x) => x.id == _accountId)
                        ? _accountId
                        : null,
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.name} · ${a.currency}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _accountId = v),
                    decoration: const InputDecoration(
                      labelText: '账户',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                c.rawText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _ignore,
                    child: const Text('忽略'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _confirm,
                    child: const Text('入账'),
                  ),
                ],
              ),
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
              if (c.status == 'ignored') ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _unignore,
                    icon: const Icon(Icons.undo),
                    label: const Text('恢复待确认'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _unignore() async {
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).unignorePendingCapture(c.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复为待确认')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$e')),
        );
      }
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
      await ref.read(databaseProvider).confirmPendingCapture(
            pendingId: c.id,
            amountMinor: toMinor(ccy, major),
            currency: ccy,
            accountId: _accountId!,
            categoryId: _categoryId!,
            merchant: _merchantCtrl.text.trim().isEmpty
                ? null
                : _merchantCtrl.text.trim(),
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

  Future<void> _ignore() async {
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).ignorePendingCapture(c.id);
      await NotificationCaptureStub.cancelPendingConfirm(c.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
    if (pkg.contains('tencent.mm')) return '微信';
    return pkg;
  }
}
