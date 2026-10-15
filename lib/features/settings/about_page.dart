import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// About hub: version, privacy policy, OSS licenses.
/// Wireframe §8: 关于 — 版本、开源许可、隐私说明链接.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String appVersion = '1.0.1+2';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('关于 Centli')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 36,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '厘记 · Centli',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '厘清每一笔账单',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 $appVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            subtitle: const Text('本地存储 · 通知范围 · 无云同步'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/me/about/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('开源许可'),
            subtitle: const Text('查看第三方依赖许可证'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Centli',
                applicationVersion: appVersion,
                applicationLegalese: '厘记 · 厘清每一笔账单',
              );
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '使用说明',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const ListTile(
            leading: Icon(Icons.tune_outlined),
            title: Text('余额校正'),
            subtitle: Text(
              '记「余额校正」流水，不改期初、不计入统计',
            ),
            isThreeLine: true,
          ),
          const ListTile(
            leading: Icon(Icons.currency_exchange),
            title: Text('多币种'),
            subtitle: Text(
              '首页 / 统计 / 资产净额按本位币折算（我的 · 汇率）；'
              '无汇率标未折算',
            ),
            isThreeLine: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
