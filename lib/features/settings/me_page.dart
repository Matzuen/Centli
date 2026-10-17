import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/home_widget/centli_home_widget_sync.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: CentliTheme.scaffoldGradient(dark: dark),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: CentliSpacing.pagePaddingNav,
            children: [
              Text(
                '设置',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: CentliSpacing.section),
              CentliSoftCard(
                onTap: () => context.push('/me/ledgers'),
                padding: const EdgeInsets.all(CentliSpacing.cardPad),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: CentliTheme.softBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.savings_rounded,
                        color: CentliTheme.softBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ledgerAsync.when(
                        loading: () => const Text('账本 …'),
                        error: (e, _) => Text('账本 · $e'),
                        data: (ledger) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ledger?.name ?? '账本',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ledger == null
                                  ? '未初始化'
                                  : '本位币 ${currencyLabel(ledger.baseCurrency)}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              _sectionHeader(context, '通用'),
              CentliSoftCard(
                child: Column(
                  children: [
                    _tile(
                      context,
                      icon: Icons.palette_outlined,
                      title: '主题',
                      subtitle: _themeLabel(ref),
                      onTap: () => _pickTheme(context, ref),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.menu_book_outlined,
                      title: '账本管理',
                      onTap: () => context.push('/me/ledgers'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.category_outlined,
                      title: '分类管理',
                      subtitle: '支出 / 收入分类',
                      onTap: () => context.push('/me/categories'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.pie_chart_outline,
                      title: '预算',
                      subtitle: '月度总额 / 分类预算与进度',
                      onTap: () => context.push('/me/budget'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.repeat,
                      title: '周期记账',
                      subtitle: '工资 / 房租等自动入账',
                      onTap: () => context.push('/me/recurring'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              _sectionHeader(context, '功能'),
              CentliSoftCard(
                child: Column(
                  children: [
                    _tile(
                      context,
                      icon: Icons.notifications_active_outlined,
                      title: '自动记账',
                      subtitle: NotificationCaptureStub.supported
                          ? '通知监听 · 待确认入账'
                          : '仅 Android 支持；Windows 上可用示例数据调试',
                      onTap: () => context.push('/me/auto'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.auto_awesome,
                      title: '智能填单',
                      subtitle: '本地解析 · 可选大模型增强',
                      onTap: () => context.push('/me/smart-fill'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.widgets_outlined,
                      title: '桌面小组件',
                      subtitle: CentliHomeWidgetSync.supported
                          ? '今日支出 · 待确认'
                          : '仅 Android 支持；可在桌面长按添加 Centli 小组件',
                      onTap: () async {
                        if (!CentliHomeWidgetSync.supported) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('桌面小组件仅 Android 可用'),
                              ),
                            );
                          }
                          return;
                        }
                        await CentliHomeWidgetSync.sync(
                          ref.read(databaseProvider),
                        );
                        final pinned = await CentliHomeWidgetSync.requestPin();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              pinned
                                  ? '已请求添加到桌面，请在系统弹窗中确认'
                                  : '请长按桌面空白处 → 小组件 → 选择 Centli',
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.lock_outline,
                      title: '安全',
                      subtitle: '应用锁 · 隐藏金额',
                      onTap: () => context.push('/me/security'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.currency_exchange,
                      title: '汇率',
                      subtitle: '手动 + 远程日频；折算为本位币',
                      onTap: () => context.push('/me/fx'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              _sectionHeader(context, '数据'),
              CentliSoftCard(
                child: Column(
                  children: [
                    _tile(
                      context,
                      icon: Icons.delete_outline,
                      title: '回收站',
                      subtitle: '恢复已删除流水',
                      onTap: () => context.push('/me/recycle'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.history_outlined,
                      title: '已忽略通知',
                      subtitle: '查看 / 恢复待确认',
                      onTap: () => context.push('/home/pending?tab=ignored'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.import_export,
                      title: '导出',
                      subtitle: 'JSON / Excel（分享）',
                      onTap: () => context.push('/me/export'),
                    ),
                    const Divider(height: 1),
                    _tile(
                      context,
                      icon: Icons.settings_backup_restore,
                      title: '导入',
                      subtitle: 'JSON 还原',
                      onTap: () => context.push('/me/import'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              _sectionHeader(context, '关于'),
              CentliSoftCard(
                child: Column(
                  children: [
                    FutureBuilder<String>(
                      future: PackageInfo.fromPlatform().then((info) {
                        final name = info.version.trim();
                        final build = info.buildNumber.trim();
                        if (name.isEmpty) return '1.1.1+4';
                        if (build.isEmpty) return name;
                        return '$name+$build';
                      }).catchError((_) => '1.1.1+4'),
                      builder: (context, snap) {
                        final v = snap.data ?? '…';
                        return _tile(
                          context,
                          icon: Icons.info_outline,
                          title: '关于 Centli',
                          subtitle: '版本 $v',
                          onTap: () => context.push('/me/about'),
                        );
                      },
                    ),
                    if (kDebugMode) ...[
                      const Divider(height: 1),
                      _tile(
                        context,
                        icon: Icons.tour_outlined,
                        title: '重新查看引导',
                        subtitle: '测试：重置引导完成标记并打开引导',
                        onTap: () async {
                          await ref
                              .read(databaseProvider)
                              .setSetting('onboarding_done', 'false');
                          if (context.mounted) context.go('/onboarding');
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool threeLine = false,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      isThreeLine: threeLine,
      onTap: onTap,
    );
  }
}

String _themeLabel(WidgetRef ref) {
  final mode = ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
  switch (mode) {
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
    case ThemeMode.system:
      return '跟随系统';
  }
}

Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final cur = ref.read(themeModeProvider).valueOrNull ?? ThemeMode.system;
  final picked = await showModalBottomSheet<ThemeMode>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('跟随系统'),
            trailing: cur == ThemeMode.system ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ThemeMode.system),
          ),
          ListTile(
            title: const Text('浅色'),
            trailing: cur == ThemeMode.light ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ThemeMode.light),
          ),
          ListTile(
            title: const Text('深色'),
            trailing: cur == ThemeMode.dark ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ThemeMode.dark),
          ),
        ],
      ),
    ),
  );
  if (picked == null) return;
  final key = switch (picked) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  await ref.read(databaseProvider).setSetting('theme_mode', key);
}

Future<void> showLedgerEditor(
  BuildContext context,
  WidgetRef ref, {
  required Ledger ledger,
}) async {
  final nameCtrl = TextEditingController(text: ledger.name);
  var base = ledger.baseCurrency;
  if (!supportedCurrencies.contains(base)) {
    base = 'CNY';
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('账本设置'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '账本名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: base,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(
                          value: c,
                          child: Text(currencyLabel(c)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => base = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '本位币',
                      border: OutlineInputBorder(),
                      helperText: '影响首页/统计/资产汇总币种；外币按汇率折算',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  if (saved != true) {
    nameCtrl.dispose();
    return;
  }

  final name = nameCtrl.text.trim();
  nameCtrl.dispose();
  if (name.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入账本名称')));
    }
    return;
  }

  await ref
      .read(databaseProvider)
      .updateLedger(id: ledger.id, name: name, baseCurrency: base);
}
