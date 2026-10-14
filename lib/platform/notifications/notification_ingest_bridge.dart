import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import 'notification_listener_stub.dart';
import 'notification_parse.dart';
import 'noti_template_store.dart';

/// Wires native notification payloads → parse → [CentliDatabase.ingestParsedNotification]
/// → local push 「待确认 ¥xx」.
abstract final class NotificationIngestBridge {
  static bool _started = false;

  /// Idempotent. Call once after DB is available (e.g. from [CentliApp]).
  static Future<void> start(CentliDatabase db) async {
    if (_started) return;
    _started = true;

    await NotificationCaptureStub.bind(
      onCapture: (raw) => ingestRaw(db, raw),
    );

    // Keep native filter in sync with app setting (default true once bound;
    // seed DB has auto_capture_enabled=false until user opts in).
    final enabled = await db.getSetting('auto_capture_enabled');
    await NotificationCaptureStub.setAutoCaptureEnabled(enabled == 'true');
  }

  static Future<void> stop() async {
    NotificationCaptureStub.unbind();
    _started = false;
  }

  /// Parse + ingest one raw notification map from MethodChannel / samples.
  /// On success, posts local system notification 「待确认 ¥xx」.
  static Future<String?> ingestRaw(
    CentliDatabase db,
    Map<String, dynamic> raw,
  ) async {
    final enabled = await db.getSetting('auto_capture_enabled');
    if (enabled != 'true') return null;

    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null || ledgerId.isEmpty) return null;

    final notification = RawNotification.fromMap(raw);
    if (notification.title.isEmpty && notification.text.isEmpty) return null;

    final templates = await NotiTemplateStore.load();
    final parsed = parseNotification(notification, templates);
    final key = dedupeKey(notification, parsed);

    final currency = parsed.currency ?? 'CNY';
    final id = await db.ingestParsedNotification(
      ledgerId: ledgerId,
      sourcePkg: notification.pkg,
      rawTitle: notification.title,
      rawText: notification.text,
      dedupeKey: key,
      amountMinor: parsed.amountMinor,
      currency: currency,
      merchant: parsed.merchant,
      happenAt: parsed.happenAt?.millisecondsSinceEpoch ?? notification.whenMs,
      parseOk: parsed.ok,
      accountHint: parsed.accountHint,
    );

    if (id != null) {
      await _showLocalPendingPush(
        pendingId: id,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
      );
    }
    return id;
  }

  /// Title: 待确认 ¥xx — body: merchant (plan §4.1 / parse doc).
  static Future<void> _showLocalPendingPush({
    required String pendingId,
    int? amountMinor,
    required String currency,
    String? merchant,
  }) async {
    final String title;
    if (amountMinor != null) {
      title = '待确认 ${formatMinor(currency, amountMinor)}';
    } else {
      title = '待确认';
    }
    final body = (merchant != null && merchant.trim().isNotEmpty)
        ? merchant.trim()
        : null;
    await NotificationCaptureStub.showPendingConfirm(
      pendingId: pendingId,
      title: title,
      body: body,
    );
  }
}
