/// Outcome of [NotificationCaptureStub.previewPaymentOverlayDetailed].
enum PreviewOverlayKind {
  /// Native WM overlay shown (Android debug).
  shown,

  /// Not an Android capture platform (desktop / iOS / web).
  unsupported,

  /// Release / non-debuggable APK.
  notDebug,

  /// No ledger in DB — cannot invent pending.
  noLedger,

  /// SYSTEM_ALERT_WINDOW missing (rare for preview path).
  noOverlayPermission,

  /// MissingPlugin / channel dead — caller may Flutter-fallback.
  channelFailed,

  /// Other failure.
  failed,
}

final class PreviewOverlayOutcome {
  const PreviewOverlayOutcome._(this.kind, {this.pendingId, this.message});

  factory PreviewOverlayOutcome.shown(String pendingId) =>
      PreviewOverlayOutcome._(PreviewOverlayKind.shown, pendingId: pendingId);

  factory PreviewOverlayOutcome.unsupported([String? message]) =>
      PreviewOverlayOutcome._(
        PreviewOverlayKind.unsupported,
        message: message ?? '当前平台无系统悬浮窗',
      );

  factory PreviewOverlayOutcome.notDebug() => const PreviewOverlayOutcome._(
        PreviewOverlayKind.notDebug,
        message: '仅 debug 包可用',
      );

  factory PreviewOverlayOutcome.noLedger() => const PreviewOverlayOutcome._(
        PreviewOverlayKind.noLedger,
        message: '缺少账本，请先创建账本',
      );

  factory PreviewOverlayOutcome.noOverlayPermission() =>
      const PreviewOverlayOutcome._(
        PreviewOverlayKind.noOverlayPermission,
        message: '缺少悬浮窗权限',
      );

  factory PreviewOverlayOutcome.channelFailed([String? message]) =>
      PreviewOverlayOutcome._(
        PreviewOverlayKind.channelFailed,
        message: message ?? '系统悬浮窗通道不可用',
      );

  factory PreviewOverlayOutcome.failed(String message) =>
      PreviewOverlayOutcome._(PreviewOverlayKind.failed, message: message);

  final PreviewOverlayKind kind;
  final String? pendingId;
  final String? message;

  bool get ok => kind == PreviewOverlayKind.shown;
}
