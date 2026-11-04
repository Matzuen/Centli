import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/app_version.dart';
import '../../core/update_check.dart';
import '../../core/widgets/glass.dart';
import '../../platform/notifications/notification_listener_stub.dart';

/// About hub: version, privacy policy, OSS licenses.
/// Wireframe §8: 关于 — 版本、开源许可、隐私说明链接.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// Fallback when [PackageInfo] is unavailable (tests / early frame).
  static final String _fallbackVersion =
      displayAppVersion(kAppVersionFallback);

  late final Future<String> _versionFuture = loadDisplayAppVersion();
  bool _checkingUpdate = false;

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
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: _checkingUpdate
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt_outlined),
                      title: const Text('检查更新'),
                      subtitle: const Text('对照 GitHub 版本标签检测新版本'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _checkingUpdate ? null : _onCheckUpdate,
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
              if (kDebugMode) ...[
                const SizedBox(height: CentliSpacing.section),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    4,
                    0,
                    4,
                    CentliSpacing.dense,
                  ),
                  child: Text(
                    '开发者',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('预览支付悬浮窗'),
                    subtitle: const Text('无需真支付，强制弹出调试悬浮窗'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _previewPaymentOverlay,
                  ),
                ),
              ],
              const SizedBox(height: CentliSpacing.section),
            ],
          );
        },
      ),
    );
  }

  Future<void> _previewPaymentOverlay() async {
    final id = await NotificationCaptureStub.previewPaymentOverlay();
    if (!mounted) return;
    if (id == null) {
      showGlassSnackBar(context, '预览失败：仅 debug 包可用，或缺少账本');
    } else {
      showGlassSnackBar(context, '已弹出调试悬浮窗');
    }
  }

  Future<void> _onCheckUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final result = await checkForAppUpdate();
      if (!mounted) return;
      if (result.hasUpdate) {
        final open = await showGlassDialog<bool>(
          context: context,
          builder: (ctx) => CentliGlassDialog(
            title: const Text('发现新版本'),
            content: Text(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('查看下载'),
              ),
            ],
          ),
        );
        if (open == true) {
          final ok = await openAppUpdatePage(result.openUrl);
          if (!mounted) return;
          if (!ok) {
            showGlassSnackBar(context, '无法打开下载页，请稍后重试');
          }
        }
      } else {
        showGlassSnackBar(context, result.message);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }
}
