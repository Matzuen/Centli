import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
  static void Function(String route, String? pendingId)? onOpenRoute;

  /// Share / deep-link payload (`pending_intake`).
  static void Function(Map<String, dynamic> payload)? onPendingIntake;

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

  /// Ask the system to re-bind the notification listener service.
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
          await handler(raw);
        }
      }
      return null;
    }
    if (call.method == 'open_route') {
      final args = call.arguments;
      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        final route = map['route'] as String?;
        final pendingId = map['pendingId'] as String?;
        if (route != null && route.isNotEmpty) {
          onOpenRoute?.call(route, pendingId);
        }
      }
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
}
