import 'package:flutter/material.dart';

import '../../core/app_version.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme.dart';

/// About hub: version, privacy policy, OSS licenses.
/// Wireframe §8: 关于 — 版本、开源许可、隐私说明链接.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// Fallback when [PackageInfo] is unavailable (tests / early frame).
  static const String _fallbackVersion = kAppVersionFallback;

  late final Future<String> _versionFuture = _loadVersion();

  static Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final name = info.version.trim();
      final build = info.buildNumber.trim();
      if (name.isEmpty) return _fallbackVersion;
      if (build.isEmpty) return name;
      return '$name+$build';
    } catch (_) {
      return _fallbackVersion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('关于 Centli')),
      body: FutureBuilder<String>(
        future: _versionFuture,
        builder: (context, snap) {
          final appVersion = snap.data ?? _fallbackVersion;
          return ListView(
            padding: CentliSpacing.pagePadding,
            children: [
              const SizedBox(height: CentliSpacing.item),
              Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 28,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: CentliSpacing.item),
              Text(
                '厘记 · Centli',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CentliSpacing.dense),
              Text(
                '厘清资产，安心记账',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CentliSpacing.dense),
              Text(
                '版本 $appVersion',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              CentliSoftCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('隐私政策'),
                      subtitle: const Text('本地存储 · 通知范围 · 无云同步'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/me/about/privacy'),
                    ),
                    const Divider(height: 1, indent: 56),
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
                          applicationLegalese: '厘记 · 厘清资产，安心记账',
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CentliSpacing.section),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  4,
                  0,
                  4,
                  CentliSpacing.dense,
                ),
                child: Text(
                  '使用说明',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              CentliSoftCard(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.tune_outlined),
                      title: Text('余额校正'),
                      subtitle: Text('记「余额校正」流水，不改期初、不计入统计'),
                      isThreeLine: true,
                    ),
                    const Divider(height: 1, indent: 56),
                    const ListTile(
                      leading: Icon(Icons.currency_exchange),
                      title: Text('多币种'),
                      subtitle: Text(
                        '首页 / 统计 / 资产净额按本位币折算（我的 · 汇率）；'
                        '无汇率标未折算',
                      ),
                      isThreeLine: true,
                    ),
                  ],
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
