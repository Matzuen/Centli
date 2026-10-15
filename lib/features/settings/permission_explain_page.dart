import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_listener_stub.dart';

/// Shown after (or while) returning from system notification-listener settings.
/// Wireframe §9: 权限说明页 — 系统设置返回后说明 [P1].
class PermissionExplainPage extends ConsumerStatefulWidget {
  const PermissionExplainPage({
    super.key,
    this.openSettingsOnEntry = false,
    this.finishOnboarding = false,
  });

  /// When true, jump to system settings once after first frame (e.g. from「去开启」).
  final bool openSettingsOnEntry;

  /// When true, write onboarding_done and go `/home` on continue.
  final bool finishOnboarding;

  @override
  ConsumerState<PermissionExplainPage> createState() =>
      _PermissionExplainPageState();
}

class _PermissionExplainPageState extends ConsumerState<PermissionExplainPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _granted = false;
  bool _awaitingReturn = false;
  bool _busy = false;
  bool _openedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    if (widget.openSettingsOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_openedOnce) {
          _openedOnce = true;
          _openSettings();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(fromSettingsReturn: _awaitingReturn);
    }
  }

  Future<void> _refresh({bool fromSettingsReturn = false}) async {
    final granted = await NotificationCaptureStub.isPermissionGranted();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _loading = false;
      if (fromSettingsReturn) _awaitingReturn = false;
    });

    if (granted) {
      // Keep preference in sync once the user has granted access.
      final db = ref.read(databaseProvider);
      await db.setSetting('auto_capture_enabled', 'true');
      await NotificationCaptureStub.setAutoCaptureEnabled(true);
      // Binding often stays dead until an explicit rebind after toggle.
      await NotificationCaptureStub.ensureListenerRebind();
    }
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _awaitingReturn = true;
    });
    try {
      await NotificationCaptureStub.openPermissionSettings();
      // Recheck in case the platform returns without leaving (stub / desktop).
      await _refresh(fromSettingsReturn: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    if (widget.finishOnboarding) {
      await ref.read(databaseProvider).setSetting('onboarding_done', 'true');
      if (!mounted) return;
      context.go('/home');
      return;
    }
    if (context.canPop()) {
      context.pop(_granted);
    } else {
      context.go('/me/auto');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final supported = NotificationCaptureStub.supported;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知权限说明'),
        automaticallyImplyLeading: !widget.finishOnboarding,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                Icon(
                  _granted
                      ? Icons.verified_user_outlined
                      : Icons.privacy_tip_outlined,
                  size: 56,
                  color: _granted ? scheme.primary : scheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  !supported
                      ? '当前平台不支持通知监听'
                      : (_granted ? '权限已开启' : '尚未开启通知使用权'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  !supported
                      ? '通知自动记账仅在 Android 可用。你可以稍后再说，或在「我的 · 自动记账」查看说明；Windows 上可用「待确认」页的示例数据调试解析。'
                      : (_granted
                          ? '已获得通知使用权。支付成功类通知会进入待确认队列，确认后才会写入流水，不会静默入账。'
                          : '请在系统设置中找到 Centli，开启「通知使用权 / 通知访问权限」。返回本页后我们会自动检测状态。'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '权限用途',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text('· 读取支付宝 / 微信等支付成功类通知'),
                        const SizedBox(height: 4),
                        const Text('· 解析金额与商户，生成待确认账单'),
                        const SizedBox(height: 4),
                        const Text('· 默认不自动入账；可随时在「自动记账」关闭'),
                      ],
                    ),
                  ),
                ),
                if (_awaitingReturn) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.secondaryContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.hourglass_top,
                        color: scheme.onSecondaryContainer,
                      ),
                      title: Text(
                        '从系统设置返回后将自动检测',
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                if (supported && !_granted) ...[
                  FilledButton(
                    onPressed: _busy ? null : _openSettings,
                    child: Text(_awaitingReturn ? '再次打开系统设置' : '打开系统设置'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _continue,
                    child: Text(
                      widget.finishOnboarding ? '稍后再说' : '返回',
                    ),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _busy ? null : _continue,
                    child: Text(
                      widget.finishOnboarding
                          ? '进入首页'
                          : (_granted ? '完成' : '返回'),
                    ),
                  ),
                  if (supported && _granted) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _openSettings,
                      child: const Text('重新打开系统设置'),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}
