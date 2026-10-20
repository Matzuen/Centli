/// Ring buffer of recent AI notification decisions — for settings UI debug.
///
/// Persisted in SharedPreferences via [NotificationCaptureStub] prefs is awkward
/// from Dart; we keep a documents-side JSON next to user rules instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int kAiNotiTraceMax = 30;

/// One decision/event while processing a captured notification.
class AiNotiTraceEvent {
  const AiNotiTraceEvent({
    required this.atMs,
    required this.pkg,
    required this.title,
    required this.kind,
    this.detail,
    this.ruleName,
  });

  final int atMs;
  final String pkg;
  final String title;

  /// Stable machine kind — see [AiNotiTraceKinds].
  final String kind;
  final String? detail;
  final String? ruleName;

  String get titleShort {
    final t = title.trim();
    if (t.isEmpty) return '（无标题）';
    return t.length > 40 ? '${t.substring(0, 40)}…' : t;
  }

  Map<String, dynamic> toJson() => {
        'atMs': atMs,
        'pkg': pkg,
        'title': title,
        'kind': kind,
        if (detail != null) 'detail': detail,
        if (ruleName != null) 'ruleName': ruleName,
      };

  factory AiNotiTraceEvent.fromJson(Map<String, dynamic> j) {
    return AiNotiTraceEvent(
      atMs: (j['atMs'] as num?)?.toInt() ?? 0,
      pkg: j['pkg']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      kind: j['kind']?.toString() ?? '',
      detail: j['detail']?.toString(),
      ruleName: j['ruleName']?.toString(),
    );
  }

  /// Short Chinese label for list UI.
  String get kindLabel {
    switch (kind) {
      case AiNotiTraceKinds.localFastPath:
        return '本地模板已识别（入账，后台再问 AI）';
      case AiNotiTraceKinds.aiOff:
        return '未开「AI 识别通知」· 仅本地';
      case AiNotiTraceKinds.aiCalledPayment:
        return 'AI 判为收付款';
      case AiNotiTraceKinds.aiCalledExclude:
        return 'AI 判为非收付款';
      case AiNotiTraceKinds.aiFailed:
        return 'AI 调用失败/超时 · 回落本地';
      case AiNotiTraceKinds.aiRateLimited:
        return 'AI 限频 · 回落本地';
      case AiNotiTraceKinds.distillCapture:
        return '已反写捕获规则';
      case AiNotiTraceKinds.distillExclude:
        return '已反写排除规则';
      case AiNotiTraceKinds.distillSkipped:
        return '未反写规则';
      case AiNotiTraceKinds.reuseCapture:
        return '命中已有 AI 捕获规则';
      case AiNotiTraceKinds.reuseExclude:
        return '命中已有 AI 排除规则';
      case AiNotiTraceKinds.localOverrideAi:
        return 'AI 判排除但本地支付模板兜底';
      default:
        return kind;
    }
  }
}

abstract final class AiNotiTraceKinds {
  static const localFastPath = 'local_fast_path';
  static const aiOff = 'ai_off';
  static const aiCalledPayment = 'ai_payment';
  static const aiCalledExclude = 'ai_exclude';
  static const aiFailed = 'ai_failed';
  static const aiRateLimited = 'ai_rate_limited';
  static const distillCapture = 'distill_capture';
  static const distillExclude = 'distill_exclude';
  static const distillSkipped = 'distill_skipped';
  static const reuseCapture = 'reuse_capture';
  static const reuseExclude = 'reuse_exclude';
  static const localOverrideAi = 'local_override_ai';
}

abstract final class AiNotiTrace {
  static List<AiNotiTraceEvent> _events = [];
  static bool _loaded = false;
  static Future<void>? _loadFuture;

  static List<AiNotiTraceEvent> peek() =>
      List<AiNotiTraceEvent>.unmodifiable(_events);

  static Future<List<AiNotiTraceEvent>> load({bool force = false}) async {
    if (_loaded && (!force || _dirty)) return peek();
    _loadFuture ??= _loadFromDisk();
    await _loadFuture;
    _loadFuture = null;
    return peek();
  }

  /// 落盘节流：调试轨迹不需要逐条落盘。
  ///
  /// 每条通知都会记 1~3 个事件，若每次都写 documents JSON，通知密集时就是
  /// 纯 IO 浪费（与 `touchDistillHit` 同一类问题）。这里内存实时更新、磁盘
  /// 最多每 [kTracePersistMs] 一次；[flush] 用于测试和页面打开前兜底。
  static const int kTracePersistMs = 2000;
  static bool _dirty = false;
  static int _lastPersistMs = 0;

  static Future<void> record({
    required String pkg,
    required String title,
    required String kind,
    String? detail,
    String? ruleName,
  }) async {
    await load();
    final ev = AiNotiTraceEvent(
      atMs: DateTime.now().millisecondsSinceEpoch,
      pkg: pkg,
      title: title.length > 80 ? title.substring(0, 80) : title,
      kind: kind,
      detail: detail,
      ruleName: ruleName,
    );
    _events = [ev, ..._events];
    if (_events.length > kAiNotiTraceMax) {
      _events = _events.sublist(0, kAiNotiTraceMax);
    }
    _dirty = true;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPersistMs < kTracePersistMs) return;
    await flush();
  }

  /// 把节流中的事件立即写盘（测试 / 页面打开前调用）。
  static Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    _lastPersistMs = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  static Future<void> clear() async {
    _events = [];
    _loaded = true;
    _dirty = false;
    _lastPersistMs = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  static Future<void> _loadFromDisk() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        _events = [];
        _loaded = true;
        return;
      }
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) {
        _events = [];
        _loaded = true;
        return;
      }
      final list = <AiNotiTraceEvent>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        list.add(AiNotiTraceEvent.fromJson(Map<String, dynamic>.from(item)));
      }
      _events = list;
    } catch (_) {
      _events = [];
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          [for (final e in _events) e.toJson()],
        ),
      );
    } catch (_) {
      // Best-effort; UI can still show in-memory.
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'ai_noti_trace.json'));
  }

  @visibleForTesting
  static void resetForTest() {
    _events = [];
    _loaded = true;
    _loadFuture = null;
    _dirty = false;
    _lastPersistMs = 0;
  }
}
