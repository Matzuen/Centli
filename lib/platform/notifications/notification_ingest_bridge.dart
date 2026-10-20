import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../features/ledger/llm_text_fill.dart';
import 'ai_noti_trace.dart';
import 'notification_listener_stub.dart';
import 'notification_llm_parse.dart';
import 'notification_noise.dart';
import 'notification_parse.dart';
import 'noti_template_store.dart';
import 'recognition_rule_distill.dart';

/// Wires native notification payloads → parse → [CentliDatabase.ingestParsedNotification]
/// → local push 「待确认 ¥xx」.
///
/// Flutter-alive path: **包名已由 native 过滤** →
/// ① AI 反写的排除规则 → 命中即丢弃（本地支付模板可兜底）；
/// ② AI 反写的捕获规则 → 命中即入账（不再问模型）；
/// ③ 本地模板已能取出金额 → 立刻入账，并在后台问 AI 反写规则；
/// ④ 否则问 AI；AI 不可用/超限/失败 → 本地模板；AI 误判排除 → 本地支付兜底。
abstract final class NotificationIngestBridge {
  static bool _started = false;

  /// Idempotent. Call once after DB is available (e.g. from [CentliApp]).
  static Future<void> start(CentliDatabase db) async {
    if (_started) return;
    _started = true;

    await NotificationCaptureStub.bind(
      onCapture: (raw) => ingestRaw(db, raw),
    );

    final enabled = await db.getSetting('auto_capture_enabled');
    await NotificationCaptureStub.setAutoCaptureEnabled(enabled == 'true');
  }

  static Future<void> stop() async {
    NotificationCaptureStub.unbind();
    _started = false;
  }

  /// Parse + ingest one raw notification map from MethodChannel / samples.
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

    final excl = matchDistillExcludeRule(notification, templates);
    if (excl != null) {
      final localCapture = parseNotification(notification, templates);
      final realPayment = localCapture.templateId != null &&
          localCapture.amountMinor != null;
      if (!realPayment) {
        _touchHitSafely(excl.id);
        unawaited(
          AiNotiTrace.record(
            pkg: notification.pkg,
            title: notification.title,
            kind: AiNotiTraceKinds.reuseExclude,
            ruleName: excl.displayName,
            detail: excl.mustContainRegex,
          ),
        );
        await NotificationCaptureStub.recordDroppedNotification(
          pkg: notification.pkg,
          title: notification.title,
          reason: 'exclude_rule',
        );
        return null;
      }
    }

    final reused = matchDistilledCaptureRule(notification, templates);
    if (reused != null) {
      unawaited(
        AiNotiTrace.record(
          pkg: notification.pkg,
          title: notification.title,
          kind: AiNotiTraceKinds.reuseCapture,
          ruleName: reused.templateId,
          detail: '金额 ${reused.amountMinor}',
        ),
      );
      return _ingestResolved(
        db,
        notification,
        (
          parse: reused,
          fromAi: false,
          exclude: false,
          mustHint: null,
        ),
      );
    }

    final resolved = await _resolveParse(db, notification, templates);

    if (resolved.exclude) {
      final localCapture = parseNotification(notification, templates);
      final realPayment = localCapture.templateId != null &&
          localCapture.amountMinor != null;
      if (realPayment) {
        unawaited(
          AiNotiTrace.record(
            pkg: notification.pkg,
            title: notification.title,
            kind: AiNotiTraceKinds.localOverrideAi,
            detail: '本地模板 ${localCapture.templateId}',
          ),
        );
        return _ingestResolved(
          db,
          notification,
          (
            parse: localCapture,
            fromAi: false,
            exclude: false,
            mustHint: null,
          ),
        );
      }
      if (resolved.fromAi) {
        _distillSafely(
          () => _distillExcludeTraced(
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

    return _ingestResolved(db, notification, resolved);
  }

  static Future<String?> _ingestResolved(
    CentliDatabase db,
    RawNotification notification,
    ({
      ParseResult parse,
      bool fromAi,
      bool exclude,
      String? mustHint,
    }) resolved,
  ) async {
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null || ledgerId.isEmpty) return null;

    final parsed = resolved.parse;
    final matched = parsed.templateId != null;

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
        _distillSafely(
          () => _distillCaptureTraced(
            raw: notification,
            parsed: parsed,
            mustHint: resolved.mustHint,
          ),
        );
      } else if (isDistillCaptureRuleId(parsed.templateId)) {
        _touchHitSafely(parsed.templateId!);
      }
    }
    return id;
  }

  static void _touchHitSafely(String id) {
    unawaited(
      NotiTemplateStore.touchDistillHit(id).catchError((Object e) {
        debugPrint('distill hit touch failed: $e');
      }),
    );
  }

  static void _distillSafely(Future<String?> Function() task) {
    unawaited(
      task().catchError((Object e) {
        debugPrint('noti distill failed: $e');
        return null;
      }),
    );
  }

  static Future<String?> _distillCaptureTraced({
    required RawNotification raw,
    required ParseResult parsed,
    String? mustHint,
  }) async {
    final id = await distillRecognitionRuleFromAi(
      raw: raw,
      parsed: parsed,
      mustHint: mustHint,
    );
    if (id == null) {
      await AiNotiTrace.record(
        pkg: raw.pkg,
        title: raw.title,
        kind: AiNotiTraceKinds.distillSkipped,
        detail: '捕获规则未写入（校验失败或无 mustHint）',
      );
      return null;
    }
    final name = distilledRuleDisplayName(
      raw.pkg,
      parsed.direction,
      mustHint ?? '支付',
    );
    await AiNotiTrace.record(
      pkg: raw.pkg,
      title: raw.title,
      kind: AiNotiTraceKinds.distillCapture,
      ruleName: name,
      detail: id,
    );
    return id;
  }

  static Future<String?> _distillExcludeTraced({
    required RawNotification raw,
    String? mustHint,
  }) async {
    final id = await distillExcludeRecognitionRuleFromAi(
      raw: raw,
      mustHint: mustHint,
    );
    if (id == null) {
      await AiNotiTrace.record(
        pkg: raw.pkg,
        title: raw.title,
        kind: AiNotiTraceKinds.distillSkipped,
        detail: '排除规则未写入（片段不安全或为空）',
      );
      return null;
    }
    await AiNotiTrace.record(
      pkg: raw.pkg,
      title: raw.title,
      kind: AiNotiTraceKinds.distillExclude,
      ruleName: distilledExcludeRuleDisplayName(raw.pkg),
      detail: id,
    );
    return id;
  }

  /// After local fast-path ingest: ask AI in background so 微信/支付宝 payments
  /// still produce distill rules the user can see.
  static void _backgroundDistillFromLocal({
    required CentliDatabase db,
    required RawNotification raw,
    required ParseResult local,
  }) {
    _distillSafely(() async {
      final cfg = await SmartFillLlmSettings().load(db);
      if (!cfg.isNotifyAiReady) {
        // local_fast_path 已说明；勿再刷一条 ai_off。
        return null;
      }
      if (isLlmParseRateLimited()) {
        await AiNotiTrace.record(
          pkg: raw.pkg,
          title: raw.title,
          kind: AiNotiTraceKinds.aiRateLimited,
          detail: '本地已入账；后台蒸馏跳过',
        );
        return null;
      }
      final llm = await parseNotificationWithLlm(raw, config: cfg);
      if (llm == null) {
        await AiNotiTrace.record(
          pkg: raw.pkg,
          title: raw.title,
          kind: AiNotiTraceKinds.aiFailed,
          detail: '本地已入账；后台 AI 无结果',
        );
        return null;
      }
      if (!llm.isPayment) {
        await AiNotiTrace.record(
          pkg: raw.pkg,
          title: raw.title,
          kind: AiNotiTraceKinds.aiCalledExclude,
          detail: '本地已按支付入账，不学排除（避免误伤）',
          ruleName: llm.mustHint,
        );
        return null;
      }
      await AiNotiTrace.record(
        pkg: raw.pkg,
        title: raw.title,
        kind: AiNotiTraceKinds.aiCalledPayment,
        detail: '后台确认收付款 · 准备反写',
        ruleName: llm.mustHint,
      );
      return _distillCaptureTraced(
        raw: raw,
        parsed: llm.parse ?? local,
        mustHint: llm.mustHint,
      );
    });
  }

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
    final local = parseNotification(notification, templates);
    if (local.templateId != null && local.amountMinor != null) {
      unawaited(
        AiNotiTrace.record(
          pkg: notification.pkg,
          title: notification.title,
          kind: AiNotiTraceKinds.localFastPath,
          detail: '模板 ${local.templateId}',
        ),
      );
      // Ingest uses local; AI distill runs after caller finishes ingest.
      // Flag via mustHint sentinel? Better: return and let ingest hook.
      // We attach a side-channel by scheduling here after a microtask that
      // ingest will also schedule — schedule distill here is fine (parallel).
      _backgroundDistillFromLocal(
        db: db,
        raw: notification,
        local: local,
      );
      return (
        parse: local,
        fromAi: false,
        exclude: false,
        mustHint: null,
      );
    }

    try {
      final cfg = await SmartFillLlmSettings().load(db);
      if (!cfg.isNotifyAiReady) {
        unawaited(
          AiNotiTrace.record(
            pkg: notification.pkg,
            title: notification.title,
            kind: AiNotiTraceKinds.aiOff,
            detail: '无本地金额匹配 · 仅本地规则',
          ),
        );
      } else if (isLlmParseRateLimited()) {
        unawaited(
          AiNotiTrace.record(
            pkg: notification.pkg,
            title: notification.title,
            kind: AiNotiTraceKinds.aiRateLimited,
          ),
        );
      } else {
        final llm = await parseNotificationWithLlm(notification, config: cfg);
        if (llm == null) {
          unawaited(
            AiNotiTrace.record(
              pkg: notification.pkg,
              title: notification.title,
              kind: AiNotiTraceKinds.aiFailed,
            ),
          );
        } else if (!llm.isPayment) {
          unawaited(
            AiNotiTrace.record(
              pkg: notification.pkg,
              title: notification.title,
              kind: AiNotiTraceKinds.aiCalledExclude,
              ruleName: llm.mustHint,
            ),
          );
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
        } else if (llm.parse != null) {
          unawaited(
            AiNotiTrace.record(
              pkg: notification.pkg,
              title: notification.title,
              kind: AiNotiTraceKinds.aiCalledPayment,
              ruleName: llm.mustHint,
              detail: llm.parse!.amountMinor != null
                  ? '金额 ${llm.parse!.amountMinor}'
                  : '无金额',
            ),
          );
          return (
            parse: llm.parse!,
            fromAi: true,
            exclude: false,
            mustHint: llm.mustHint,
          );
        }
      }
    } catch (_) {
      unawaited(
        AiNotiTrace.record(
          pkg: notification.pkg,
          title: notification.title,
          kind: AiNotiTraceKinds.aiFailed,
          detail: '异常',
        ),
      );
    }
    return (
      parse: local,
      fromAi: false,
      exclude: false,
      mustHint: null,
    );
  }

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
