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

    // 监听开关以 native prefs 为准（磁贴也写这里），再回写 DB，避免双源漂移。
    final nativeOn = await NotificationCaptureStub.isAutoCaptureEnabled();
    await db.setSetting('auto_capture_enabled', nativeOn ? 'true' : 'false');
    // App 冷启动后主动软重绑，尽量保持监听一直连着。
    if (nativeOn) {
      unawaited(NotificationCaptureStub.ensureListenerRebind());
    }
  }

  static Future<void> stop() async {
    NotificationCaptureStub.unbind();
    _started = false;
  }

  /// Parse + ingest one raw notification map from MethodChannel / samples.
  ///
  /// When [raw] carries `nativeIngested: true`, native already wrote pending +
  /// push (LiteNote / AutoBookKeeping style). Dart only runs AI distill / hit
  /// stats and must not insert again.
  static Future<String?> ingestRaw(
    CentliDatabase db,
    Map<String, dynamic> raw,
  ) async {
    // 与 native 监听同源：prefs 优先（磁贴即时生效），再对齐 DB。
    final nativeOn = await NotificationCaptureStub.isAutoCaptureEnabled();
    final dbOn = (await db.getSetting('auto_capture_enabled')) == 'true';
    if (nativeOn != dbOn) {
      await db.setSetting('auto_capture_enabled', nativeOn ? 'true' : 'false');
    }
    if (!nativeOn) return null;

    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null || ledgerId.isEmpty) return null;

    final nativeIngested = raw['nativeIngested'] == true;
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
          AiNotiTrace.recordForRaw(
            raw: notification,
            kind: AiNotiTraceKinds.reuseExclude,
            ruleName: excl.displayName,
            detail: excl.mustContainRegex,
            recognition: '命中排除规则 · ${excl.mustContainRegex ?? ''}',
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
      final id = await _ingestResolved(
        db,
        notification,
        (
          parse: reused,
          fromAi: false,
          exclude: false,
          mustHint: null,
        ),
        skipInsert: nativeIngested,
      );
      // 匹配 ≠ 新建待确认：同通知已在待确认 / 刚确认过会走去重。
      unawaited(
        AiNotiTrace.recordForRaw(
          raw: notification,
          kind: (id != null || nativeIngested)
              ? AiNotiTraceKinds.reuseCapture
              : AiNotiTraceKinds.ingestDeduped,
          ruleName: reused.templateId,
          detail: nativeIngested
              ? '金额 ${reused.amountMinor} · native 已入待确认'
              : (id != null
                  ? '金额 ${reused.amountMinor} · 已入待确认'
                  : '金额 ${reused.amountMinor} · 去重未新建'),
          recognition: formatLocalRecognition(
            reused,
            note: nativeIngested
                ? '命中 AI 捕获规则（native 已落库）'
                : (id != null
                    ? '命中 AI 捕获规则，已写入待确认'
                    : '命中 AI 捕获规则，但未新建待确认：'
                        '待确认列表里已有同通知，或该通知键刚被确认/忽略过（去重）'),
          ),
        ),
      );
      return id;
    }

    final resolved = await _resolveParse(db, notification, templates);

    if (resolved.exclude) {
      final localCapture = parseNotification(notification, templates);
      final realPayment = localCapture.templateId != null &&
          localCapture.amountMinor != null;
      if (realPayment) {
        unawaited(
          AiNotiTrace.recordForRaw(
            raw: notification,
            kind: AiNotiTraceKinds.localOverrideAi,
            detail: '本地模板 ${localCapture.templateId}',
            recognition: formatLocalRecognition(
              localCapture,
              note: 'AI 判排除，本地支付模板兜底',
            ),
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
          skipInsert: nativeIngested,
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
      if (!nativeIngested) {
        await NotificationCaptureStub.recordDroppedNotification(
          pkg: notification.pkg,
          title: notification.title,
          reason: 'ai_exclude',
        );
      }
      return null;
    }

    return _ingestResolved(
      db,
      notification,
      resolved,
      skipInsert: nativeIngested,
    );
  }

  static Future<String?> _ingestResolved(
    CentliDatabase db,
    RawNotification notification,
    ({
      ParseResult parse,
      bool fromAi,
      bool exclude,
      String? mustHint,
    }) resolved, {
    bool skipInsert = false,
  }) async {
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
      if (!skipInsert) {
        await NotificationCaptureStub.recordDroppedNotification(
          pkg: notification.pkg,
          title: notification.title,
          reason: 'weak',
        );
      }
      return null;
    }
    if (!matched) {
      if (!skipInsert) {
        await NotificationCaptureStub.recordDroppedNotification(
          pkg: notification.pkg,
          title: notification.title,
          reason: 'weak',
        );
      }
      return null;
    }
    final key = dedupeKey(notification, parsed);

    final currency = parsed.currency ?? 'CNY';
    String? id;
    if (!skipInsert) {
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
          happenAt:
              parsed.happenAt?.millisecondsSinceEpoch ?? notification.whenMs,
          parseOk: parsed.ok,
          accountHint: parsed.accountHint,
          direction: parsed.direction,
        );
      } catch (e) {
        return null;
      }
    }

    // 命中计数跟「规则是否匹配」走，不跟「是否新建待确认」走。
    // 去重跳过入库时轨迹已写「命中」，若这里不 touch 就会出现「命中了 / 尚未命中」。
    if (!resolved.fromAi && isDistillCaptureRuleId(parsed.templateId)) {
      _touchHitSafely(parsed.templateId!);
    }

    if (id != null) {
      await _showLocalPendingPush(
        db: db,
        pendingId: id,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
      );
    }
    // AI 反写：前台 Dart 路径；native 已入库时仍要学规则。
    if (resolved.fromAi && (id != null || skipInsert)) {
      _distillSafely(
        () => _distillCaptureTraced(
          raw: notification,
          parsed: parsed,
          mustHint: resolved.mustHint,
        ),
      );
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
      await AiNotiTrace.recordForRaw(
        raw: raw,
        kind: AiNotiTraceKinds.distillSkipped,
        detail: '捕获规则未写入（校验失败或无 mustHint）',
        recognition: formatLocalRecognition(
          parsed,
          note: '反写捕获规则失败',
        ),
      );
      return null;
    }
    final name = distilledRuleDisplayName(
      raw.pkg,
      parsed.direction,
      mustHint ?? '支付',
    );
    await AiNotiTrace.recordForRaw(
      raw: raw,
      kind: AiNotiTraceKinds.distillCapture,
      ruleName: name,
      detail: id,
      recognition: formatLocalRecognition(parsed, note: '已写入捕获规则 $name'),
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
      await AiNotiTrace.recordForRaw(
        raw: raw,
        kind: AiNotiTraceKinds.distillSkipped,
        detail: '排除规则未写入（片段不安全或为空）',
        recognition: '关键词: ${mustHint ?? '（空）'}\n反写排除规则失败',
      );
      return null;
    }
    await AiNotiTrace.recordForRaw(
      raw: raw,
      kind: AiNotiTraceKinds.distillExclude,
      ruleName: distilledExcludeRuleDisplayName(raw.pkg),
      detail: id,
      recognition: '关键词: ${mustHint ?? ''}\n已写入排除规则',
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
        await AiNotiTrace.recordForRaw(
          raw: raw,
          kind: AiNotiTraceKinds.aiRateLimited,
          detail: '本地已入账；后台蒸馏跳过',
          recognition: formatLocalRecognition(local, note: 'AI 限频，未再问模型'),
        );
        return null;
      }
      final llm = await parseNotificationWithLlm(raw, config: cfg);
      if (llm == null || llm.failed) {
        await AiNotiTrace.recordForRaw(
          raw: raw,
          kind: AiNotiTraceKinds.aiFailed,
          detail: '本地已入账；后台 AI 无结果',
          recognition: llm?.recognitionSummary() ??
              formatLocalRecognition(local, note: '后台 AI 无返回'),
        );
        return null;
      }
      if (!llm.isPayment) {
        await AiNotiTrace.recordForRaw(
          raw: raw,
          kind: AiNotiTraceKinds.aiCalledExclude,
          detail: '本地已按支付入账，不学排除（避免误伤）',
          ruleName: llm.mustHint,
          recognition: '${llm.recognitionSummary()}\n'
              '（本地已入账，不学排除）',
        );
        return null;
      }
      await AiNotiTrace.recordForRaw(
        raw: raw,
        kind: AiNotiTraceKinds.aiCalledPayment,
        detail: '后台确认收付款 · 准备反写',
        ruleName: llm.mustHint,
        recognition: llm.recognitionSummary(),
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
        AiNotiTrace.recordForRaw(
          raw: notification,
          kind: AiNotiTraceKinds.localFastPath,
          detail: '模板 ${local.templateId}',
          recognition: formatLocalRecognition(local),
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
          AiNotiTrace.recordForRaw(
            raw: notification,
            kind: AiNotiTraceKinds.aiOff,
            detail: '无本地金额匹配 · 仅本地规则',
            recognition: formatLocalRecognition(
              local,
              note: '未开 AI 识别通知',
            ),
          ),
        );
      } else if (isLlmParseRateLimited()) {
        unawaited(
          AiNotiTrace.recordForRaw(
            raw: notification,
            kind: AiNotiTraceKinds.aiRateLimited,
            recognition: formatLocalRecognition(local, note: 'AI 限频'),
          ),
        );
      } else {
        final llm = await parseNotificationWithLlm(notification, config: cfg);
        if (llm == null || llm.failed) {
          unawaited(
            AiNotiTrace.recordForRaw(
              raw: notification,
              kind: AiNotiTraceKinds.aiFailed,
              detail: llm?.error,
              recognition: llm?.recognitionSummary() ?? 'AI 无返回',
            ),
          );
        } else if (!llm.isPayment) {
          unawaited(
            AiNotiTrace.recordForRaw(
              raw: notification,
              kind: AiNotiTraceKinds.aiCalledExclude,
              ruleName: llm.mustHint,
              recognition: llm.recognitionSummary(),
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
            AiNotiTrace.recordForRaw(
              raw: notification,
              kind: AiNotiTraceKinds.aiCalledPayment,
              ruleName: llm.mustHint,
              detail: llm.parse!.amountMinor != null
                  ? '金额 ${llm.parse!.amountMinor}'
                  : '无金额',
              recognition: llm.recognitionSummary(),
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
    } catch (e) {
      unawaited(
        AiNotiTrace.recordForRaw(
          raw: notification,
          kind: AiNotiTraceKinds.aiFailed,
          detail: '异常',
          recognition: '异常: $e',
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
    required CentliDatabase db,
    required String pendingId,
    int? amountMinor,
    required String currency,
    String? merchant,
  }) async {
    final lockOn = (await db.getSetting('app_lock')) == 'true';
    final String title;
    final String? body;
    if (lockOn) {
      title = '待确认记账';
      body = null;
    } else if (amountMinor != null) {
      title = '待确认 ${formatMinor(currency, amountMinor)}';
      body = (merchant != null && merchant.trim().isNotEmpty)
          ? merchant.trim()
          : null;
    } else {
      title = '待确认';
      body = (merchant != null && merchant.trim().isNotEmpty)
          ? merchant.trim()
          : null;
    }
    await NotificationCaptureStub.showPendingConfirm(
      pendingId: pendingId,
      title: title,
      body: body,
    );
  }
}
