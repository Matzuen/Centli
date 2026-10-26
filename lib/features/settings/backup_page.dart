import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants/pref_keys.dart';
import '../../core/widgets/glass.dart';
import '../../data/db/database_provider.dart';
import '../../data/export/backup_service.dart';

final backupConfigProvider = FutureProvider.autoDispose<BackupConfig>((ref) async {
  final db = ref.watch(databaseProvider);
  // 主动读一次；设置页在改动后会 invalidate。
  return BackupService(db).loadConfig();
});

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  BackupService get _svc => BackupService(ref.read(databaseProvider));

  Future<void> _refresh() async {
    ref.invalidate(backupConfigProvider);
  }

  Future<void> _pickDir() async {
    setState(() => _busy = true);
    try {
      final path = await _svc.pickDirectory();
      if (path == null || path.isEmpty) return;
      await _svc.setDirectory(path);
      await _refresh();
      if (!mounted) return;
      showGlassSnackBar(context, '已选择备份目录');
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '选择目录失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setFrequency(BackupFrequency freq) async {
    await _svc.setFrequency(freq);
    await _refresh();
    // 触发其它监听 backupDir 之外的键：轻触写一下 last error 不变的键不够，
    // 直接 invalidate。
  }

  Future<void> _runNow() async {
    final config = ref.read(backupConfigProvider).valueOrNull;
    if (config == null || !config.hasDirectory) {
      showGlassSnackBar(context, '请先选择备份目录');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _svc.runBackup();
      await _refresh();
      if (!mounted) return;
      showGlassSnackBar(
        context,
        '已备份 ${result.ledgerCount} 本 → ${result.fileNames.length} 个文件',
      );
    } catch (e) {
      await ref.read(databaseProvider).setSetting(
            PrefKeys.backupLastError,
            '$e',
          );
      await _refresh();
      if (!mounted) return;
      showGlassSnackBar(context, '备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatLast(DateTime? utcOrLocal) {
    if (utcOrLocal == null) return '尚未备份';
    final local = utcOrLocal.toLocal();
    return DateFormat('yyyy-MM-dd HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(backupConfigProvider);
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('备份设置')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('加载失败：$e'))),
        data: (config) {
          return ListView(
            padding: CentliSpacing.pagePadding,
            children: [
              Text(
                '数据只保存在本机，没有 Centli 云。选择一个你自己的文件夹'
                '（本地磁盘，或已登录的网盘同步目录均可），按频率自动写入 JSON 备份；'
                '也可用下方「立即备份」。还原请到「我的 → 导入」。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: CentliSpacing.section),
              CentliSoftCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('备份目录'),
                      subtitle: Text(
                        config.hasDirectory
                            ? config.directory!
                            : '未选择（点此用系统目录选择器）',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: _busy ? null : _pickDir,
                      isThreeLine: config.hasDirectory,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('自动备份频率'),
                      subtitle: Text(config.frequency.labelZh),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: _busy
                          ? null
                          : () async {
                              final picked =
                                  await showGlassDialog<BackupFrequency>(
                                context: context,
                                builder: (ctx) {
                                  return CentliGlassDialog(
                                    title: const Text('自动备份频率'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final f in BackupFrequency.values)
                                          ListTile(
                                            title: Text(f.labelZh),
                                            trailing: f == config.frequency
                                                ? const Icon(Icons.check)
                                                : null,
                                            onTap: () =>
                                                Navigator.pop(ctx, f),
                                          ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx),
                                        child: const Text('取消'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (picked == null) return;
                              await _setFrequency(picked);
                              await _refresh();
                            },
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: const Text('上次备份'),
                      subtitle: Text(_formatLast(config.lastSuccessAt)),
                    ),
                    if (config.lastError != null) ...[
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(
                          Icons.error_outline,
                          color: scheme.error,
                        ),
                        title: Text(
                          '上次失败原因',
                          style: TextStyle(color: scheme.error),
                        ),
                        subtitle: Text(config.lastError!),
                        isThreeLine: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              FilledButton.icon(
                onPressed: _busy ? null : _runNow,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_outlined),
                label: Text(_busy ? '备份中…' : '立即备份'),
              ),
              const SizedBox(height: CentliSpacing.section),
              CentliSoftCard(
                onTap: () => context.push('/me/export'),
                child: const ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('手动导出并分享'),
                  subtitle: Text('原有能力：JSON / Excel，经系统分享送出'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              Text(
                '说明：自动备份在每次打开 App 或从后台回到前台时检查是否到期；'
                '不依赖常驻后台。Android 上请优先选择「下载」「Documents」等'
                '系统能稳定写入的位置；若写入失败，失败原因会显示在上方。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: CentliSpacing.section),
            ],
          );
        },
      ),
    );
  }
}
