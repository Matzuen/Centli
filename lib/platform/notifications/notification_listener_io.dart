import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

import 'dropped_notification.dart';
import 'notification_parse.dart';

export 'dropped_notification.dart';

/// IO platforms: real MethodChannel on Android; graceful no-op elsewhere
/// (Windows / macOS / Linux / iOS).
abstract final class NotificationCaptureStub {
  static const String channelName = 'centli/notification_capture';
  static const int templateVersion = 3;

  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<void> Function(Map<String, dynamic> raw)? _onCapture;
  static bool _bound = false;

  /// Deep-link from local-push tap (`open_route`).
  static void Function(String route, String? pendingId, {bool review})?
      onOpenRoute;

  /// Share / deep-link payload (`pending_intake`).
  static void Function(Map<String, dynamic> payload)? onPendingIntake;

  /// Native SQLite mutated pending_captures outside Drift.
  static void Function()? onPendingDbChanged;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// MethodChannel available for share / deeplink on Android + iOS.
  static bool get channelSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<bool> isPermissionGranted() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isPermissionGranted');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Android 13+：是否已允许 App 弹出通知（POST_NOTIFICATIONS）。
  static Future<bool> isPostNotificationsGranted() async {
    if (!supported) return true;
    try {
      final v =
          await _channel.invokeMethod<bool>('isPostNotificationsGranted');
      return v ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// 弹出系统「允许发送通知」对话框。已授权或低版本直接返回 true。
  static Future<bool> requestPostNotificationsPermission() async {
    if (!supported) return true;
    try {
      final v = await _channel
          .invokeMethod<bool>('requestPostNotificationsPermission');
      return v ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// Whether NotificationListenerService.onListenerConnected has fired.
  /// Permission can be ON while this is false (OEM dropped the binding).
  static Future<bool> isListenerConnected() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isListenerConnected');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Soft rebind: no-op when already connected. Safe for page reload / resume.
  static Future<void> ensureListenerRebind() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('ensureListenerRebind');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  /// After [ensureListenerRebind], wait until the system fires
  /// `onListenerConnected` (cold start often needs 0.5–3s).
  static Future<bool> awaitListenerConnected({
    Duration timeout = const Duration(seconds: 5),
    Duration step = const Duration(milliseconds: 250),
  }) async {
    if (!supported) return false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isListenerConnected()) return true;
      await Future<void>.delayed(step);
    }
    return isListenerConnected();
  }

  /// Hard disable/enable of the NLS component. Only for explicit「重新连接」—
  /// calling this on every reload drops live notifications.
  static Future<void> forceListenerRebind() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('forceListenerRebind');
    } on MissingPluginException {
      // Older builds: fall back to soft.
      await ensureListenerRebind();
    } on PlatformException {
      // no-op
    }
  }

  /// 让 native 自己处理这条通知（Dart 侧失败时的兜底）。
  static Future<void> _fallbackToNativeIngest(Map<String, dynamic> raw) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<String>('nativeIngestCapture', raw);
    } on MissingPluginException {
      // 旧版本没有这个通道，只能记录。
    } on PlatformException {
      // ignore
    }
  }

  static Future<void> openPermissionSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openPermissionSettings');
    } on MissingPluginException {
      // Graceful: plugin not registered (e.g. hot-restart edge).
    } on PlatformException {
      // Ignore; user can open settings manually.
    }
  }

  static Future<void> setAutoCaptureEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setAutoCaptureEnabled', enabled);
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }


  /// Sync package watch list to native SharedPreferences (Android).
  /// Native unions this with its builtin WeChat/Alipay set.
  static Future<void> setWatchedPackages(List<String> packages) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setWatchedPackages', packages);
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  /// Push merged recognition rules JSON for native kill-path matching (T2-2).
  static Future<void> setRulesJson(String rulesJson) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setRulesJson', rulesJson);
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  static Future<bool> isAutoCaptureEnabled() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isAutoCaptureEnabled');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Listen for native to Dart `notification_capture` / `open_route` /
  /// `pending_intake` invokes.
  static Future<void> bind({
    required Future<void> Function(Map<String, dynamic> raw) onCapture,
  }) async {
    _onCapture = onCapture;
    await _ensureChannelHandler();
  }

  /// Register handler for native share / deep-link (`pending_intake`).
  /// Binds on Android and iOS (not gated by [supported] notification listener).
  static Future<void> bindPendingIntake(
    void Function(Map<String, dynamic> payload) onIntake,
  ) async {
    onPendingIntake = onIntake;
    await _ensureChannelHandler();
  }

  static Future<void> _ensureChannelHandler() async {
    if (!channelSupported) return;
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler(_onMethodCall);
    // Ask native to flush queues only after Dart handler is bound (#10).
    try {
      await _channel.invokeMethod<void>('bridgeReady');
    } on MissingPluginException {
      // iOS / older builds may not implement yet.
    } on PlatformException {
      // ignore
    }
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'notification_capture') {
      final args = call.arguments;
      if (args is Map) {
        final raw = Map<String, dynamic>.from(args);
        final handler = _onCapture;
        if (handler != null) {
          // Do not await AI/network here — blocking the MethodChannel makes
          // subsequent captures stall and feels like「开了 AI 就没反应」.
          unawaited(
            handler(raw).catchError((Object e, StackTrace st) {
              debugPrint('notification_capture handler failed: $e\n$st');
              // 处理失败时把 payload 交回 native：它会自己写库并推送待确认，
              // 否则这条通知会在「已交给 Dart」之后静默丢失。
              return _fallbackToNativeIngest(raw);
            }),
          );
        }
      }
      return null;
    }
    // Native bridgeReady flush：逐条 await，返回仍失败、需保留在队列的项。
    if (call.method == 'notification_capture_flush') {
      final args = call.arguments;
      if (args is! List) return <Map<String, dynamic>>[];
      final handler = _onCapture;
      final keep = <Map<String, dynamic>>[];
      for (final item in args) {
        if (item is! Map) continue;
        final raw = Map<String, dynamic>.from(item);
        if (handler == null) {
          keep.add(raw);
          continue;
        }
        try {
          await handler(raw).timeout(const Duration(seconds: 20));
        } catch (e, st) {
          debugPrint('notification_capture_flush item failed: $e\n$st');
          try {
            await _fallbackToNativeIngest(raw)
                .timeout(const Duration(seconds: 8));
          } catch (e2, st2) {
            debugPrint('flush fallback failed: $e2\n$st2');
            keep.add(raw);
          }
        }
      }
      return keep;
    }
    if (call.method == 'open_route') {
      final args = call.arguments;
      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        final route = map['route'] as String?;
        final pendingId = map['pendingId'] as String?;
        final review = map['review'] == true;
        if (route != null && route.isNotEmpty) {
          onOpenRoute?.call(route, pendingId, review: review);
        }
      }
      return null;
    }
    if (call.method == 'pending_db_changed') {
      onPendingDbChanged?.call();
      return null;
    }
    if (call.method == 'pending_intake') {
      final args = call.arguments;
      if (args is Map) {
        onPendingIntake?.call(Map<String, dynamic>.from(args));
      }
      return null;
    }
    throw MissingPluginException(
      'No handler for method ${call.method} on $channelName',
    );
  }

  static void unbind() {
    _onCapture = null;
    onPendingIntake = null;
    if (_bound && channelSupported) {
      _channel.setMethodCallHandler(null);
      _bound = false;
    }
  }

  static ParseResult parseRaw(Map<String, dynamic> raw) {
    return parseNotification(RawNotification.fromMap(raw));
  }


  /// 后台复活（周期任务）是否已排上；详情见 native `CentliResurrect`。
  static Future<bool> isResurrectScheduled() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isResurrectScheduled');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!supported) return true;
    try {
      final v = await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  /// LiteNote 式悬浮窗：是否已授予「显示在其他应用上层」。
  static Future<bool> isOverlayPermissionGranted() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isOverlayPermissionGranted');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isOverlayEnabled() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isOverlayEnabled');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setOverlayEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setOverlayEnabled', enabled);
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  static Future<void> openOverlayPermissionSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openOverlayPermissionSettings');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  /// System local notification: pending confirm title + optional merchant body.
  static Future<void> showPendingConfirm({
    required String pendingId,
    required String title,
    String? body,
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('showPendingConfirm', {
        'pendingId': pendingId,
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op (e.g. permission denied)
    }
  }

  static Future<void> cancelPendingConfirm(String pendingId) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelPendingConfirm', {
        'pendingId': pendingId,
      });
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  static Future<void> cancelAllPendingConfirm() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancelAllPendingConfirm');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }


  static Future<List<DroppedNotification>> getDroppedNotifications() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getDroppedNotifications');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) => DroppedNotification.fromMap(Map<Object?, Object?>.from(e)))
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> clearDroppedNotifications() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clearDroppedNotifications');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  static Future<void> recordDroppedNotification({
    required String pkg,
    required String title,
    String reason = 'weak',
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('recordDroppedNotification', {
        'pkg': pkg,
        'title': title,
        'reason': reason,
      });
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }

  /// Installed launchable apps: `{packageName, label}`.
  static Future<List<LaunchableAppInfo>> listLaunchableApps() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listLaunchableApps');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) {
            final m = Map<Object?, Object?>.from(e);
            final pkg = '${m['packageName'] ?? ''}'.trim();
            final label = '${m['label'] ?? ''}'.trim();
            if (pkg.isEmpty) return null;
            return LaunchableAppInfo(
              packageName: pkg,
              label: label.isEmpty ? pkg : label,
            );
          })
          .whereType<LaunchableAppInfo>()
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}

class LaunchableAppInfo {
  const LaunchableAppInfo({
    required this.packageName,
    required this.label,
  });

  final String packageName;
  final String label;
}
