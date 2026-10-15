import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/currencies.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/home_widget/centli_home_widget_sync.dart';
import '../../platform/notifications/notification_listener_stub.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('\u6211\u7684')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ledgerAsync.when(
            loading: () => const ListTile(
              leading: CircleAvatar(child: Icon(Icons.book_outlined)),
              title: Text('\u8d26\u672c'),
              subtitle: Text('...'),
            ),
            error: (e, _) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.book_outlined)),
              title: const Text('\u8d26\u672c'),
              subtitle: Text('$e'),
            ),
            data: (ledger) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.book_outlined)),
              title: const Text('\u8d26\u672c'),
              subtitle: Text(
                ledger == null
                    ? '\u672a\u521d\u59cb\u5316'
                    : '${ledger.name} \u00b7 \u672c\u4f4d\u5e01 ${ledger.baseCurrency}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/me/ledgers'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(_themeLabel(ref)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('回收站'),
            subtitle: const Text('恢复已删除流水'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/recycle'),
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('已忽略通知'),
            subtitle: const Text('查看 / 恢复待确认'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/home/pending?tab=ignored'),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('\u5206\u7c7b'),
            subtitle: const Text('\u652f\u51fa / \u6536\u5165\u5206\u7c7b'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('预算'),
            subtitle: const Text('月度总额 / 分类预算与进度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/budget'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('\u81ea\u52a8\u8bb0\u8d26'),
            subtitle: Text(
              NotificationCaptureStub.supported
                  ? '\u901a\u77e5\u76d1\u542c\u00b7\u5f85\u786e\u8ba4\u5165\u8d26'
                  : '\u4ec5 Android \u652f\u6301\uff1bWindows \u4e0a\u53ef\u7528\u793a\u4f8b\u6570\u636e\u8c03\u8bd5',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/auto'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('智能填单'),
            subtitle: const Text('本地解析 · 可选大模型增强'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/smart-fill'),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('桌面小组件'),
            subtitle: Text(
              CentliHomeWidgetSync.supported
                  ? '今日支出 · 待确认（P3 MVP）'
                  : '仅 Android 支持；可在桌面长按添加 Centli 小组件',
            ),
            trailing: const Icon(Icons.chevron_right),
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
              await CentliHomeWidgetSync.sync(ref.read(databaseProvider));
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
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('\u5b89\u5168'),
            subtitle: const Text('\u5e94\u7528\u9501 \u00b7 \u9690\u85cf\u91d1\u989d\uff08P2\uff09'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/security'),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('\u6c47\u7387'),
            subtitle: const Text(
              '\u624b\u5de5 + \u8fdc\u7a0b\u65e5\u9891\uff1b\u6298\u7b97\u4e3a\u672c\u4f4d\u5e01',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/fx'),
          ),
          ListTile(
            leading: const Icon(Icons.import_export),
            title: const Text('\u5bfc\u51fa'),
            subtitle: const Text('JSON / Excel\uff08\u5206\u4eab\uff09'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/export'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('\u5bfc\u5165'),
            subtitle: const Text('JSON \u8fd8\u539f\uff08P3\uff09'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/import'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('\u5173\u4e8e Centli'),
            subtitle: const Text(
              '\u5398\u8bb0 \u00b7 \u7248\u672c 1.0.0+1\n'
              '\u9690\u79c1\u653f\u7b56 \u00b7 \u5f00\u6e90\u8bb8\u53ef',
            ),
            trailing: const Icon(Icons.chevron_right),
            isThreeLine: true,
            onTap: () => context.push('/me/about'),
          ),
          ListTile(
            leading: const Icon(Icons.tour_outlined),
            title: const Text('\u91cd\u65b0\u67e5\u770b\u5f15\u5bfc'),
            subtitle: const Text(
              '\u6d4b\u8bd5\uff1a\u91cd\u7f6e onboarding_done \u5e76\u6253\u5f00\u5f15\u5bfc',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await ref
                  .read(databaseProvider)
                  .setSetting('onboarding_done', 'false');
              if (context.mounted) context.go('/onboarding');
            },
          ),
        ],
      ),
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
            trailing: cur == ThemeMode.system
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.pop(ctx, ThemeMode.system),
          ),
          ListTile(
            title: const Text('浅色'),
            trailing:
                cur == ThemeMode.light ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ThemeMode.light),
          ),
          ListTile(
            title: const Text('深色'),
            trailing:
                cur == ThemeMode.dark ? const Icon(Icons.check) : null,
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
            title: const Text('\u8d26\u672c\u8bbe\u7f6e'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '\u8d26\u672c\u540d\u79f0',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: base,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => base = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '\u672c\u4f4d\u5e01',
                      border: OutlineInputBorder(),
                      helperText:
                          '\u5f71\u54cd\u9996\u9875/\u7edf\u8ba1/\u8d44\u4ea7\u6c47\u603b\u5e01\u79cd\uff1b\u5916\u5e01\u6309\u6c47\u7387\u6298\u7b97',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('\u53d6\u6d88'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('\u4fdd\u5b58'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u8d26\u672c\u540d\u79f0')),
      );
    }
    return;
  }

  await ref.read(databaseProvider).updateLedger(
        id: ledger.id,
        name: name,
        baseCurrency: base,
      );
}