import '../platform/home_widget/centli_home_widget_sync.dart';

/// Holds a cold-start deep link until splash finishes and takes it once.
class PendingDeepLink {
  static String? _target;

  static String? take() {
    final t = _target;
    _target = null;
    return t;
  }

  static void capture(String raw) {
    _target = resolveInitialDeepLink(raw);
  }

  static bool get has => _target != null;

  /// Maps platform default route / widget URI to an in-app path.
  static String? resolveInitialDeepLink(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == '/') return null;
    if (s.startsWith('centli://')) {
      return CentliHomeWidgetSync.routeForUri(Uri.tryParse(s));
    }
    if (s.startsWith('/')) return s;
    return null;
  }
}