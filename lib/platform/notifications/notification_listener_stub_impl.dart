import 'dropped_notification.dart';
import 'notification_parse.dart';

export 'dropped_notification.dart';

/// Non-Android / web stub. Windows desktop keeps this path via conditional
/// import so MethodChannel is never touched.
abstract final class NotificationCaptureStub {
  static const bool supported = false;
  static const bool channelSupported = false;
  static const String channelName = 'centli/notification_capture';
  static const int templateVersion = 3;

  /// Optional deep-link handler (local-push tap). Stub never invokes it.
  static void Function(String route, String? pendingId, {bool review})?
      onOpenRoute;

  static void Function(Map<String, dynamic> payload)? onPendingIntake;

  /// Native wrote pending_captures outside Drift — refresh UI lists.
  static void Function()? onPendingDbChanged;

  static Future<bool> isPermissionGranted() async => false;

  static Future<bool> isListenerConnected() async => false;

  static Future<void> ensureListenerRebind() async {}

  static Future<void> openPermissionSettings() async {
    // No-op on platforms without NotificationListenerService.
  }

  static Future<void> setAutoCaptureEnabled(bool enabled) async {}

  static Future<void> setWatchedPackages(List<String> packages) async {}

  static Future<void> setRulesJson(String rulesJson) async {}

  static Future<bool> isAutoCaptureEnabled() async => false;

  /// Register a handler for native `notification_capture` events.
  /// Stub: ignored.
  static Future<void> bind({
    required Future<void> Function(Map<String, dynamic> raw) onCapture,
  }) async {}

  static Future<void> bindPendingIntake(
    void Function(Map<String, dynamic> payload) onIntake,
  ) async {
    onPendingIntake = onIntake;
  }

  static void unbind() {}

  /// Parse a raw notification map (pkg/title/text/when) without DB writes.
  static ParseResult parseRaw(Map<String, dynamic> raw) {
    return parseNotification(RawNotification.fromMap(raw));
  }

  /// Local push after pending ingest. No-op on non-Android.
  static Future<void> showPendingConfirm({
    required String pendingId,
    required String title,
    String? body,
  }) async {}

  static Future<void> cancelPendingConfirm(String pendingId) async {}

  static Future<void> cancelAllPendingConfirm() async {}

  /// Desktop stub: treat as ignored (no OEM battery killer).
  static Future<bool> isResurrectScheduled() async => false;

  static Future<bool> isBatteryOptimizationIgnored() async => true;

  static Future<void> openBatteryOptimizationSettings() async {}

  static Future<List<DroppedNotification>> getDroppedNotifications() async =>
      const [];

  static Future<void> clearDroppedNotifications() async {}

  static Future<void> recordDroppedNotification({
    required String pkg,
    required String title,
    String reason = 'weak',
  }) async {}
}

