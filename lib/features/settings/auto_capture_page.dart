import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/ai_noti_trace.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/notification_llm_parse.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

/// Full auto-capture settings at `/me/auto` (wireframe §8).
class AutoCapturePage extends ConsumerStatefulWidget {
  const AutoCapturePage({super.key});

  @override
  ConsumerState<AutoCapturePage> createState() => _AutoCapturePageState();
}

class _AutoCapturePageState extends ConsumerState<AutoCapturePage>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = false;
  bool _granted = false;
  bool _postNotificationsGranted = true;
  bool _listenerConnected = false;
  bool _listenerConnecting = false;
  int _templateVersion = kNotiTemplateFallbackVersion;
  String? _templateUpdatedAt;
  String _templateSource = 'builtin';
  int _pendingCount = 0;
  bool _busy = false;
  bool _batteryIgnored = false;
  bool _resurrectScheduled = false;
  bool _overlayEnabled = true;
  bool _overlayGranted = false;
  Map<String, String> _accountMap = {};
  List<Account> _accounts = const [];
  List<DroppedNotification> _dropped = const [];
  String _aiTraceHint = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload(soft: true);
    }
  }

  Future<void> _reload({bool soft = false}) async {
    if (!soft && mounted) setState(() => _loading = true);
    final db = ref.read(databaseProvider);

    // Fast path: paint without waiting up to 5s for listener rebind.
    final enabledF = db.getSetting('auto_capture_enabled');
    final grantedF = NotificationCaptureStub.isPermissionGranted();
    final postF = NotificationCaptureStub.isPostNotificationsGranted();
    final connectedF = NotificationCaptureStub.isListenerConnected();
    final batteryF = NotificationCaptureStub.isBatteryOptimizationIgnored();
    final resurrectF = NotificationCaptureStub.isResurrectScheduled();
    final overlayOnF = NotificationCaptureStub.isOverlayEnabled();
    final overlayPermF = NotificationCaptureStub.isOverlayPermissionGranted();
    final ledgerIdF = db.currentLedgerId();
    final accountMapF = db.getCaptureAccountMap();
    final droppedF = NotificationCaptureStub.getDroppedNotifications();

    final enabled = (await enabledF) == 'true';
    final granted = await grantedF;
    final postGranted = await postF;
    final connected = await connectedF;
    final batteryIgnored = await batteryF;
    final resurrectScheduled = await resurrectF;
    final overlayEnabled = await overlayOnF;
    final overlayGranted = await overlayPermF;
    final ledgerId = await ledgerIdF;
    final accountMap = await accountMapF;
    final dropped = await droppedF;

    var pending = 0;
    List<Account> accounts = const [];
    if (ledgerId != null) {
      final pendingF = db.countPendingCaptures(ledgerId);
      final accountsF = db.loadActiveAccounts(ledgerId);
      pending = await pendingF;
      accounts = await accountsF;
    }

    NotiTemplateStore.bindDatabase(db);
    // Prefer cache; avoid blocking open on network/disk template refresh.
    final templates = NotiTemplateStore.peek().isNotEmpty
        ? NotiTemplateStore.peek()
        : await NotiTemplateStore.load();
    final version = NotiTemplateStore.version;
    final updatedAt = NotiTemplateStore.updatedAt;
    final source = NotiTemplateStore.source;
    final aiRules = [
      for (final t in templates)
        if (isDistillRuleId(t.id)) t,
    ];
    // Cache only — force disk flush was making open feel stuck.
    final trace = await AiNotiTrace.load(force: false);
    final latest = trace.isEmpty ? null : trace.first;
    final hint = latest == null
        ? (aiRules.isEmpty
            ? '官方 v$version · 尚无 AI 反写，点进查看处理记录'
            : '官方 v$version · AI 规则 ${aiRules.length} 条')
        : 'AI 规则 ${aiRules.length} 条 · 最近：${latest.kindLabel}';

    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _granted = granted;
      _postNotificationsGranted = postGranted;
      _listenerConnected = connected;
      _listenerConnecting = granted && enabled && !connected;
      _batteryIgnored = batteryIgnored;
      _resurrectScheduled = resurrectScheduled;
      _overlayEnabled = overlayEnabled;
      _overlayGranted = overlayGranted;
      _templateVersion = version;
      _templateUpdatedAt = updatedAt;
      _templateSource = source;
      _pendingCount = pending;
      _accountMap = accountMap;
      _accounts = accounts;
      _dropped = dropped;
      _aiTraceHint = hint;
      _loading = false;
    });

    // Soft rebind in background — never block first paint.
    if (granted && enabled && !connected) {
      unawaited(_refreshListenerInBackground());
    }

    // Persist template version off the critical path.
    unawaited(db.setSetting('notification_template_version', '$version'));
  }

  Future<void> _refreshListenerInBackground() async {
    try {
      await NotificationCaptureStub.ensureListenerRebind();
      final connected = await NotificationCaptureStub.awaitListenerConnected(
        timeout: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() {
        _listenerConnected = connected;
        _listenerConnecting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _listenerConnecting = false);
    }
  }

  Future<void> _requestPostNotifications() async {
    setState(() => _busy = true);
    try {
      final ok =
          await NotificationCaptureStub.requestPostNotificationsPermission();
      if (!mounted) return;
      setState(() => _postNotificationsGranted = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请在系统设置中允许 Centli 发送通知')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOverlayPermission() async {
    setState(() => _busy = true);
    try {
      await NotificationCaptureStub.openOverlayPermissionSettings();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) await _reload(soft: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool wantOn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      var granted = _granted;
      if (wantOn && NotificationCaptureStub.supported && !granted) {
        final result = await context.push<bool>('/me/permission?open=1');
        if (!mounted) return;
        granted = result == true
            ? true
            : await NotificationCaptureStub.isPermissionGranted();
        if (!mounted) return;
        setState(() => _granted = granted);
        if (!granted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请先在系统设置中开启通知使用权')));
          return;
        }
      }
      await db.setSetting('auto_capture_enabled', wantOn ? 'true' : 'false');
      await NotificationCaptureStub.setAutoCaptureEnabled(wantOn);
      if (wantOn) {
        // Background listen dies under battery optimization on most OEMs.
        final ignored =
            await NotificationCaptureStub.isBatteryOptimizationIgnored();
        if (!ignored) {
          await NotificationCaptureStub.openBatteryOptimizationSettings();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        // Soft rebind is enough after enabling; hard toggle drops the bind.
        if (mounted) setState(() => _listenerConnecting = true);
        await NotificationCaptureStub.ensureListenerRebind();
      }
      if (!mounted) return;
      final batteryIgnored =
          await NotificationCaptureStub.isBatteryOptimizationIgnored();
      final connected = wantOn
          ? await NotificationCaptureStub.awaitListenerConnected()
          : await NotificationCaptureStub.isListenerConnected();
      if (!mounted) return;
      setState(() {
        _enabled = wantOn;
        _batteryIgnored = batteryIgnored;
        _listenerConnected = connected;
        _listenerConnecting = false;
      });
      if (wantOn && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              batteryIgnored
                  ? '已开启。清后台后仍会继续捕获（不显示常驻通知）。'
                  : '已开启，但未关闭电池优化时，清后台后可能丢通知，请在系统里允许无限制。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPermission() async {
    if (_granted && !_listenerConnected) {
      // Explicit user action — hard rebind OK here.
      if (mounted) setState(() => _listenerConnecting = true);
      await NotificationCaptureStub.forceListenerRebind();
      final connected = await NotificationCaptureStub.awaitListenerConnected();
      if (!mounted) return;
      setState(() {
        _listenerConnected = connected;
        _listenerConnecting = false;
      });
      if (connected) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已重新连接通知监听')));
        return;
      }
    }
    final result = await context.push<bool>(
      _granted ? '/me/permission' : '/me/permission?open=1',
    );
    if (!mounted) return;
    final granted = result == true
        ? true
        : await NotificationCaptureStub.isPermissionGranted();
    setState(() => _granted = granted);
    await _reload(soft: true);
  }

  /// 「重新安排」：软重绑 + 排上后台复活任务（勿硬 toggle，否则会打断正在监听）。
  Future<void> _rescheduleResurrect() async {
    setState(() => _busy = true);
    try {
      await NotificationCaptureStub.ensureListenerRebind();
      final scheduled = await NotificationCaptureStub.isResurrectScheduled();
      final connected = await NotificationCaptureStub.isListenerConnected();
      if (!mounted) return;
      setState(() {
        _resurrectScheduled = scheduled;
        _listenerConnected = connected;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scheduled
                ? '后台复活任务已安排（约 15 分钟一次，无常驻通知）'
                : '未能安排：请确认已开启自动记账，并允许自启动/后台运行',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBattery() async {
    setState(() => _busy = true);
    try {
      await NotificationCaptureStub.openBatteryOptimizationSettings();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final ignored =
          await NotificationCaptureStub.isBatteryOptimizationIgnored();
      if (!mounted) return;
      setState(() => _batteryIgnored = ignored);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAppAccount(String hint, String? accountId) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(databaseProvider)
          .setCaptureAccountForHint(hint, accountId);
      final map = await ref.read(databaseProvider).getCaptureAccountMap();
      if (!mounted) return;
      setState(() => _accountMap = map);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accountId == null ? '已清除映射' : '已保存默认资产账户')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkTemplateUpdate() async {
    setState(() => _busy = true);
    try {
      final result = await NotiTemplateStore.checkAndApplyUpdate();
      await ref
          .read(databaseProvider)
          .setSetting(
            'notification_template_version',
            '${result.activeVersion}',
          );
      if (!mounted) return;
      setState(() {
        _templateVersion = result.activeVersion;
        _templateUpdatedAt = NotiTemplateStore.updatedAt;
        _templateSource = result.source;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearPending() async {
    final ledgerId = await ref.read(databaseProvider).currentLedgerId();
    if (ledgerId == null) return;
    if (_pendingCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无待确认账单')));
      return;
    }

    if (!mounted) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('清空待确认'),
        content: Text('将删除当前记账本下 $_pendingCount 条待确认记录（不影响已入账流水）。此操作不可撤销。'),
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

    setState(() => _busy = true);
    try {
      final n = await ref.read(databaseProvider).clearPendingCaptures(ledgerId);
      await NotificationCaptureStub.cancelAllPendingConfirm();
      if (!mounted) return;
      setState(() => _pendingCount = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n == 0 ? '没有可清空的记录' : '已清空 $n 条待确认')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTemplateVersion() {
    final templates = NotiTemplateStore.peek();
    final apps = <String>{};
    for (final t in templates) {
      for (final pkg in t.packages) {
        apps.add(_pkgLabel(pkg));
      }
    }

    showGlassDialog<void>(
      context: context,
      builder: (ctx) {
        return CentliGlassDialog(
          title: const Text('解析模板'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('版本：$_templateVersion'),
                Text('来源：$_templateSource'),
                if (_templateUpdatedAt != null) Text('更新于：$_templateUpdatedAt'),
                const SizedBox(height: CentliSpacing.section),
                Text(
                  '模板共 ${templates.length} 条',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: CentliSpacing.item),
                for (final t in templates) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(t.id),
                    subtitle: Text(t.packages.map(_pkgLabel).join('、')),
                  ),
                ],
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '监听应用：${apps.join('、')}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
    if (pkg.contains('tencent.mm')) return '微信';
    return pkg;
  }

  String _relTime(int whenMs) {
    if (whenMs <= 0) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - whenMs;
    if (diff < 60 * 1000) return '刚刚';
    if (diff < 60 * 60 * 1000) return '${diff ~/ (60 * 1000)} 分钟前';
    if (diff < 24 * 60 * 60 * 1000) return '${diff ~/ (60 * 60 * 1000)} 小时前';
    return '${diff ~/ (24 * 60 * 60 * 1000)} 天前';
  }

  Future<void> _joinWatch(DroppedNotification d) async {
    final db = ref.read(databaseProvider);
    NotiTemplateStore.bindDatabase(db);
    await NotiTemplateStore.addExtraWatchedPackage(d.pkg);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入监听：${d.pkg}')),
    );
    await _reload(soft: true);
  }

  Future<void> _clearDropped() async {
    await NotificationCaptureStub.clearDroppedNotifications();
    if (!mounted) return;
    setState(() => _dropped = const []);
  }

  Widget _buildReadyChecklist(BuildContext context, ColorScheme scheme) {
    final listenOk = _granted && _listenerConnected;
    final items = <({
      String title,
      String okHint,
      String badHint,
      bool ok,
      VoidCallback? onFix,
    })>[
      (
        title: '1. 通知使用权',
        okHint: '已开启',
        badHint: '未开启 · 去系统授权',
        ok: _granted,
        onFix: _busy ? null : _openPermission,
      ),
      (
        title: '2. 发送通知',
        okHint: '已允许（待确认提醒）',
        badHint: '未允许 · 点此申请',
        ok: _postNotificationsGranted,
        onFix: _busy ? null : _requestPostNotifications,
      ),
      (
        title: '3. 支付悬浮窗（LiteNote 式）',
        okHint: _overlayEnabled
            ? '已授权 · 支付后弹出快速记账'
            : '已授权 · 下方开关已关',
        badHint: '需「显示在其他应用上层」；小米/OPPO/vivo 还要开「后台弹出界面」',
        ok: _overlayGranted && _overlayEnabled,
        onFix: _busy
            ? null
            : (_overlayGranted
                ? () async {
                    await NotificationCaptureStub.setOverlayEnabled(true);
                    if (mounted) setState(() => _overlayEnabled = true);
                  }
                : _openOverlayPermission),
      ),
      (
        title: '4. 电池优化',
        okHint: '已忽略，利于后台捕获',
        badHint: '建议设为「不优化」',
        ok: _batteryIgnored,
        onFix: _busy ? null : _openBattery,
      ),
    ];
    final readyCount = items.where((e) => e.ok).length + (listenOk ? 1 : 0);
    final total = items.length + 1;

    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            title: const Text('就绪检查'),
            subtitle: Text(
              listenOk && readyCount == total
                  ? '权限已齐 · 支付后可走悬浮窗或待确认'
                  : '建议按序完成 $readyCount/$total · 监听${listenOk ? '已连接' : (_listenerConnecting ? '连接中…' : '未连接')}',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(
              listenOk ? Icons.check_circle : Icons.radio_button_unchecked,
              color: listenOk ? scheme.primary : scheme.outline,
              size: 22,
            ),
            title: const Text('监听连接'),
            subtitle: Text(
              !_granted
                  ? '需先开通知使用权'
                  : (_listenerConnected
                      ? '已连接'
                      : (_listenerConnecting ? '正在连接…' : '未连接 · 点此重连')),
            ),
            trailing: (!_granted || _listenerConnected || _busy)
                ? null
                : TextButton(
                    onPressed: _openPermission,
                    child: const Text('重连'),
                  ),
            onTap: (!_granted || _listenerConnected || _busy)
                ? null
                : _openPermission,
          ),
          for (final item in items)
            ListTile(
              dense: true,
              leading: Icon(
                item.ok ? Icons.check_circle : Icons.radio_button_unchecked,
                color: item.ok ? scheme.primary : scheme.outline,
                size: 22,
              ),
              title: Text(item.title),
              subtitle: Text(item.ok ? item.okHint : item.badHint),
              trailing: item.ok
                  ? null
                  : TextButton(
                      onPressed: item.onFix,
                      child: const Text('去设置'),
                    ),
              onTap: item.ok ? null : item.onFix,
            ),
          const SizedBox(height: CentliSpacing.dense),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final supported = NotificationCaptureStub.supported;
    final switchOn = supported && _enabled && _granted;

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('自动记账')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: CentliSpacing.pagePadding,
              children: [
                Text(
                  '支付通知优先走自动线：捕获后进悬浮窗或待确认，点一下才入账。\n'
                  '按下方清单一次配齐权限，之后少打断。\n'
                  '也可在系统控制中心添加「自动记账」快捷开关，下拉即可开/关监听。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: CentliSpacing.section),
                if (supported) ...[
                  _buildReadyChecklist(context, scheme),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                ],
                if (!supported) ...[
                  CentliSoftCard(
                    child: ListTile(
                      leading: Icon(
                        Icons.desktop_windows_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('当前平台不支持通知监听'),
                      subtitle: const Text(
                        '仅 Android 支持。Windows 上可在「待确认」页用示例数据调试解析与入队。',
                      ),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                ],
                CentliSoftCard(
                  child: SwitchListTile(
                    title: const Text('启用通知捕获'),
                    subtitle: Text(
                      !supported
                          ? '当前平台不可用'
                          : (_granted
                                ? (_enabled ? '已开启' : '已关闭')
                                : '需先授予通知使用权'),
                    ),
                    value: switchOn,
                    onChanged: (!supported || _busy)
                        ? null
                        : (v) => _setEnabled(v),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.rule_outlined),
                    title: const Text('识别规则'),
                    subtitle: Text(
                      _aiTraceHint.isEmpty
                          ? '官方 v$_templateVersion · 含 AI 反写规则与最近处理记录'
                          : _aiTraceHint,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/me/auto/rules');
                      if (mounted) await _reload(soft: true);
                    },
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.picture_in_picture_alt_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('支付悬浮窗'),
                    subtitle: Text(
                      !supported
                          ? '仅 Android 支持'
                          : (!_overlayGranted
                                ? '未授权「显示在其他应用上层」'
                                : (_overlayEnabled
                                      ? '捕获后弹出快速记账（选分类即可入账）'
                                      : '已关闭 · 仍会发待确认通知')),
                    ),
                    trailing: !supported
                        ? null
                        : (!_overlayGranted
                              ? TextButton(
                                  onPressed:
                                      _busy ? null : _openOverlayPermission,
                                  child: const Text('去开启'),
                                )
                              : Switch(
                                  value: _overlayEnabled,
                                  onChanged: _busy
                                      ? null
                                      : (v) async {
                                          await NotificationCaptureStub
                                              .setOverlayEnabled(v);
                                          if (mounted) {
                                            setState(() => _overlayEnabled = v);
                                          }
                                        },
                                )),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: Icon(
                      _resurrectScheduled
                          ? Icons.autorenew
                          : Icons.error_outline,
                      color:
                          _resurrectScheduled ? scheme.primary : scheme.error,
                    ),
                    title: const Text('后台复活任务'),
                    subtitle: Text(
                      !supported
                          ? '仅 Android 相关：用于被系统清理后补回监听'
                          : _resurrectScheduled
                              ? '已安排（约 15 分钟一次，无常驻通知）'
                              : '未安排 · 点右侧重新安排；仍无效请允许自启动/后台运行',
                    ),
                    trailing: supported
                        ? TextButton(
                            onPressed: _busy ? null : _rescheduleResurrect,
                            child:
                                Text(_resurrectScheduled ? '重新安排' : '立即安排'),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: CentliSpacing.sectionLoose),
                Text(
                  '应用 → 默认资产账户',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '解析成功后预填资产账户；仍需在待确认页点「入账」。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: CentliSpacing.section),
                for (final def in kCaptureAppDefs) ...[
                  CentliSoftCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: CentliSpacing.item,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              def.label,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey(
                                'cap-map-${def.hint}-${_accountMap[def.hint]}',
                              ),
                              initialValue:
                                  _accountMap[def.hint] != null &&
                                      _accounts.any(
                                        (a) => a.id == _accountMap[def.hint],
                                      )
                                  ? _accountMap[def.hint]
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                                labelText: '默认资产账户',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('自动（按资产账户名）'),
                                ),
                                for (final a in _accounts)
                                  DropdownMenuItem<String?>(
                                    value: a.id,
                                    child: Text('${a.name} · ${a.currency}'),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (v) => _setAppAccount(def.hint, v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                ],
                const SizedBox(height: CentliSpacing.section),
                if (_dropped.isNotEmpty) ...[
                  CentliSoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: const Text('最近被忽略的通知'),
                          subtitle: const Text(
                            '这些通知因为不在监听列表里被跳过了。加入后，同类通知会进入「待确认」。',
                          ),
                          trailing: TextButton(
                            onPressed: _clearDropped,
                            child: const Text('清空'),
                          ),
                        ),
                        for (final d in _dropped)
                          ListTile(
                            dense: true,
                            title: Text(
                              '${d.pkg} · ${d.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_relTime(d.whenMs)),
                            trailing: TextButton(
                              onPressed: () => _joinWatch(d),
                              child: const Text('加入监听'),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                ],
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.rule_folder_outlined),
                    title: const Text('解析模板'),
                    subtitle: Text(
                      _templateUpdatedAt == null
                          ? 'v$_templateVersion · $_templateSource'
                          : 'v$_templateVersion · $_templateSource · $_templateUpdatedAt',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showTemplateVersion,
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.system_update_alt),
                    title: const Text('检查模板更新'),
                    subtitle: const Text('对比内置 assets；有更新或尚无本地覆盖时写入 documents'),
                    trailing: _busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    onTap: _busy ? null : _checkTemplateUpdate,
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                Text('发出去没通知？', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '微信/支付宝发出去的红包、转账常无系统通知。可用分享账单、截图 OCR、剪贴板/快捷指令 URL 加入同一待确认队列',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('分享账单到 Centli'),
                    subtitle: const Text('在微信/支付宝「账单」详情页分享文字或图片到本 App'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/me/auto/manual-help'),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.document_scanner_outlined),
                    title: const Text('从截图识别'),
                    subtitle: const Text('相册/相机选图，设备本地 OCR 后入待确认'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/home/pending'),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.link_outlined),
                    title: const Text('剪贴板 / 快捷指令'),
                    subtitle: const Text(
                      'centli://pending?text=... 或待确认页「从剪贴板导入」',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/me/auto/manual-help'),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: ListTile(
                    leading: const Icon(Icons.pending_actions_outlined),
                    title: const Text('待确认队列'),
                    subtitle: Text(
                      _pendingCount == 0 ? '暂无待确认' : '$_pendingCount 条待确认',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/home/pending'),
                  ),
                ),
                const SizedBox(height: CentliSpacing.sectionLoose),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _clearPending,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('清空待确认'),
                      ),
                    ),
                    const SizedBox(width: CentliSpacing.section),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showTemplateVersion,
                        icon: const Icon(Icons.info_outline),
                        label: const Text('查看模板'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
