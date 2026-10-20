import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../features/ledger/llm_text_fill.dart';
import 'notification_listener_stub.dart';
import 'notification_llm_parse.dart';
import 'notification_noise.dart';
import 'notification_parse.dart';
import 'noti_template_store.dart';
import 'recognition_rule_distill.dart';

/// Wires native notification payloads → parse → [CentliDatabase.ingestParsedNotification]
/// → local push 「待确认 ¥xx」.
///
/// Flutter-alive path: **包名已由 native 过滤** → 本地排除规则 → AI（若就绪）→
/// 失败则本地捕获模板。AI 判支付则蒸馏「软件名-支出/收入」；判非支付则蒸馏
/// 「软件名-排除」，供杀进程路径直接丢弃。
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

    // AI 学到的排除规则优先：命中即丢弃，不再问模型（这正是"循环往复"里
    // 越用越省的那一半）。但排除规则绝不能吞掉真实支付——本地捕获模板若能
    // 匹配出金额，就以捕获为准，宁可多问一次模型。
    final excl = matchDistillExcludeRule(notification, templates);
    if (excl != null) {
      final localCapture = parseNotification(notification, templates);
      final realPayment = localCapture.templateId != null &&
          localCapture.amountMinor != null;
      if (!realPayment) {
        await NotificationCaptureStub.recordDroppedNotification(
          pkg: notification.pkg,
          title: notification.title,
          reason: 'exclude_rule',
        );
        return null;
      }
    }

    final resolved = await _resolveParse(db, notification, templates);

    if (resolved.exclude) {
      // AI said non-payment — distill 软件名-排除 for next time / kill-path.
      if (resolved.fromAi) {
        _distillSafely(
          () => distillExcludeRecognitionRuleFromAi(
            raw: notification,
            mustHint: resolved.mustHint,
          ),
        );
      }
      await NotificationCaptureStub.recordDroppedNotification(
        pkg: notification.pkg,
        title: notification.title,
        reason: 'ai_exclude',
      );
      return null;
    }

    final parsed = resolved.parse;
    final matched = parsed.templateId != null;

    // G29.1: widened native gate + Dart noise filter → G28 drops (reason=weak).
    if (shouldDropAsWeakNoise(
          templateMatched: matched,
          amountMinor: parsed.amountMinor,
          title: notification.title,
          text: notification.text,
        ) ||
        (!matched && parsed.amountMinor == null)) {
      await NotificationCaptureStub.recordDroppedNotification(
        pkg: notification.pkg,
        title: notification.title,
        reason: 'weak',
      );
      return null;
    }
    if (!matched) {
      await NotificationCaptureStub.recordDroppedNotification(
        pkg: notification.pkg,
        title: notification.title,
        reason: 'weak',
      );
      return null;
    }
    final key = dedupeKey(notification, parsed);

    final currency = parsed.currency ?? 'CNY';
    String? id;
    try {
      id = await db.ingestParsedNotification(
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
        direction: parsed.direction,
      );
    } catch (e) {
      // Native path may have inserted the same dedupe_key already.
      return null;
    }

    if (id != null) {
      await _showLocalPendingPush(
        pendingId: id,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
      );
      if (resolved.fromAi) {
        // Distill after ingest so kill-path can match next time without AI.
        _distillSafely(
          () => distillRecognitionRuleFromAi(
            raw: notification,
            parsed: parsed,
            mustHint: resolved.mustHint,
          ),
        );
      }
    }
    return id;
  }

  /// 蒸馏不阻塞入库（下一个进程里才用得上），但异常必须自己消化：
  /// `unawaited` 抛出的错误会变成未捕获异步错误，在 debug 下直接打断运行。
  static void _distillSafely(Future<String?> Function() task) {
    unawaited(
      task().catchError((Object e) {
        debugPrint('noti distill failed: $e');
        return null;
      }),
    );
  }

  /// AI first when ready; otherwise / on failure → local [parseNotification].
  static Future<
      ({
        ParseResult parse,
        bool fromAi,
        bool exclude,
        String? mustHint,
      })> _resolveParse(
    CentliDatabase db,
    RawNotification notification,
    List<NotiTemplate> templates,
  ) async {
    try {
      final cfg = await SmartFillLlmSettings().load(db);
      if (cfg.isReady) {
        final llm = await parseNotificationWithLlm(notification, config: cfg);
        if (llm != null) {
          if (!llm.isPayment) {
            return (
              parse: llm.parse ??
                  ParseResult(
                    ok: false,
                    happenAt: DateTime.fromMillisecondsSinceEpoch(
                      notification.whenMs,
                      isUtc: false,
                    ),
                    currency: 'CNY',
                  ),
              fromAi: true,
              exclude: true,
              mustHint: llm.mustHint,
            );
          }
          if (llm.parse != null) {
            return (
              parse: llm.parse!,
              fromAi: true,
              exclude: false,
              mustHint: llm.mustHint,
            );
          }
        }
      }
    } catch (_) {
      // Fall through to local templates.
    }
    final local = parseNotification(notification, templates);
    return (
      parse: local,
      fromAi: false,
      exclude: false,
      mustHint: null,
    );
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
