/// Optional OpenAI-compatible LLM enhancement for smart text fill.
///
/// Uses chat completions JSON extraction. Never blocks save: callers must
/// fall back to [parseBookkeepingText] on any failure / offline / missing key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../data/db/centli_database.dart';
import 'ai_text_fill.dart';
import '../settings/model_name_validation.dart';

const String kLlmEnabledSettingKey = 'smart_fill_llm_enabled';
/// Independent gate for AI notification parse (default off).
const String kLlmNotifyAiEnabledSettingKey = 'smart_fill_llm_notify_ai_enabled';
/// Independent gate for asset-balance screenshot vision (default off).
const String kLlmAssetAiEnabledSettingKey = 'smart_fill_llm_asset_ai_enabled';
const String kLlmBaseUrlSettingKey = 'smart_fill_llm_base_url';
const String kLlmModelSettingKey = 'smart_fill_llm_model';
const String kLlmApiKeyStorageKey = 'centli_smart_fill_llm_api_key';

const String kDefaultLlmBaseUrl = 'https://api.deepseek.com';
const String kDefaultLlmModel = 'deepseek-flash';

/// One-shot marker: stale OpenAI default model migrated to deepseek-flash.
const String kLlmModelMigratedV1Key = 'smart_fill_llm_model_migrated_v1';

/// Persisted when vision retry without `detail` succeeded.
const String kLlmDetailCompatKey = 'smart_fill_llm_detail_compat';

const Set<String> kStaleOpenAiDefaultModels = {
  'gpt-4o-mini',
  'gpt-4o',
  'gpt-4-turbo',
  'gpt-3.5-turbo',
  'gpt-4',
};

class SmartFillLlmConfig {
  const SmartFillLlmConfig({
    required this.enabled,
    this.notifyAiEnabled = false,
    this.assetAiEnabled = false,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  /// 文字填单 / 记账截图识别总开关。
  final bool enabled;
  /// 通知 AI 解析（默认关；与 [enabled] 独立）。
  final bool notifyAiEnabled;
  /// 资产页余额截图识别（默认关；与 [enabled] 独立）。
  final bool assetAiEnabled;
  final String baseUrl;
  final String model;
  final String apiKey;

  /// 只看凭证是否齐全（服务地址 + API Key），不看各功能开关。
  bool get hasCredentials =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// 文字填单 / 记账截图可用 = [enabled] + 凭证齐全。
  bool get isReady => enabled && hasCredentials;

  /// 通知 AI 解析可用 = [notifyAiEnabled] + 凭证齐全。
  bool get isNotifyAiReady => notifyAiEnabled && hasCredentials;

  /// 资产截图识别可用 = [assetAiEnabled] + 凭证齐全。
  bool get isAssetAiReady => assetAiEnabled && hasCredentials;

  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

class SmartFillLlmSettings {
  SmartFillLlmSettings({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Set by [load] when a one-shot stale-model migration ran.
  String? lastMigrationNotice;

  /// Set by [load] when baseUrl is deepseek and model is unknown / typo.
  String? lastModelWarning;

  Future<SmartFillLlmConfig> load(CentliDatabase db) async {
    lastMigrationNotice = null;
    lastModelWarning = null;
    final enabled = (await db.getSetting(kLlmEnabledSettingKey)) == 'true';
    final notifyAi =
        (await db.getSetting(kLlmNotifyAiEnabledSettingKey)) == 'true';
    final assetAi =
        (await db.getSetting(kLlmAssetAiEnabledSettingKey)) == 'true';
    final base = (await db.getSetting(kLlmBaseUrlSettingKey))?.trim();
    var model = (await db.getSetting(kLlmModelSettingKey))?.trim();
    final key = (await _storage.read(key: kLlmApiKeyStorageKey)) ?? '';
    final baseUrl = (base == null || base.isEmpty) ? kDefaultLlmBaseUrl : base;
    if (model == null || model.isEmpty) {
      model = kDefaultLlmModel;
    }

    final baseLower = baseUrl.toLowerCase();
    if (baseLower.contains('deepseek')) {
      final migrated = (await db.getSetting(kLlmModelMigratedV1Key)) == 'true';
      if (!migrated && kStaleOpenAiDefaultModels.contains(model)) {
        final before = model;
        model = kDefaultLlmModel;
        await db.setSetting(kLlmModelSettingKey, model);
        await db.setSetting(kLlmModelMigratedV1Key, 'true');
        lastMigrationNotice = '检测到旧的模型配置（$before），已改为 $kDefaultLlmModel';
      } else {
        final hint = evaluateDeepSeekModelHint(model, baseUrl: baseUrl);
        lastModelWarning = hint.message;
      }
    }

    return SmartFillLlmConfig(
      enabled: enabled,
      notifyAiEnabled: notifyAi,
      assetAiEnabled: assetAi,
      baseUrl: baseUrl,
      model: model,
      apiKey: key,
    );
  }

  Future<void> save({
    required CentliDatabase db,
    required bool enabled,
    bool? notifyAiEnabled,
    bool? assetAiEnabled,
    required String baseUrl,
    required String model,
    String? apiKey,
    bool clearApiKey = false,
  }) async {
    await db.setSetting(kLlmEnabledSettingKey, enabled ? 'true' : 'false');
    if (notifyAiEnabled != null) {
      await db.setSetting(
        kLlmNotifyAiEnabledSettingKey,
        notifyAiEnabled ? 'true' : 'false',
      );
    }
    if (assetAiEnabled != null) {
      await db.setSetting(
        kLlmAssetAiEnabledSettingKey,
        assetAiEnabled ? 'true' : 'false',
      );
    }
    await db.setSetting(kLlmBaseUrlSettingKey, baseUrl.trim());
    await db.setSetting(kLlmModelSettingKey, model.trim());
    if (clearApiKey) {
      await _storage.delete(key: kLlmApiKeyStorageKey);
    } else if (apiKey != null) {
      final t = apiKey.trim();
      if (t.isEmpty) {
        await _storage.delete(key: kLlmApiKeyStorageKey);
      } else {
        await _storage.write(key: kLlmApiKeyStorageKey, value: t);
      }
    }
  }

  Future<bool> hasApiKey() async {
    final v = await _storage.read(key: kLlmApiKeyStorageKey);
    return v != null && v.trim().isNotEmpty;
  }
}

/// Call OpenAI-compatible `/chat/completions` and map into [AiTextFillResult].
///
/// Returns `null` on any failure (timeout, HTTP error, bad JSON).
Future<AiTextFillResult?> parseBookkeepingTextWithLlm(
  String raw, {
  required SmartFillLlmConfig config,
  List<String> categoryNames = const [],
  List<CategoryRef> categories = const [],
  List<String> accountNames = const [],
  http.Client? client,
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (!config.isReady) return null;
  final input = raw.trim();
  if (input.isEmpty) return null;

  final names = categories.isNotEmpty
      ? categories.map((c) => c.name).toList()
      : categoryNames;

  final catList = names.take(80).join('、');
  final accList = accountNames.take(40).join('、');

  final system = '''
你是记账助手。从用户中文/英文记账话术中抽取结构化字段，只输出一个 JSON 对象，不要 markdown。
字段：
- amount: number|null 金额（正数）
- type: "out"|"in"|"transfer"|null
- categoryHint: string|null 分类名（尽量使用用户分类列表中的名称）
- merchant: string|null 商家/收款方
- note: string|null 去掉金额/分类/商家/资产账户后的剩余备注；没有则 null
- accountHint: string|null 付款资产账户
- toAccountHint: string|null 转入资产账户（仅转账）
用户分类：$catList
用户资产账户：$accList
规则：不要把整句原文放进 note；不确定的 categoryHint 置 null。
''';

  final uri = Uri.parse('${config.normalizedBaseUrl}/chat/completions');
  final body = <String, dynamic>{
    'model': config.model,
    'temperature': 0,
    'messages': [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': input},
    ],
    'response_format': {'type': 'json_object'},
  };

  final httpClient = client ?? http.Client();
  final owned = client == null;
  try {
    final resp = await httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final msg = choices.first is Map ? choices.first['message'] : null;
    final content = msg is Map ? msg['content'] : null;
    if (content is! String || content.trim().isEmpty) return null;

    final jsonStr = _extractJsonObject(content);
    if (jsonStr == null) return null;
    final map = jsonDecode(jsonStr);
    if (map is! Map) return null;

    final amountRaw = map['amount'];
    double? amount;
    if (amountRaw is num) {
      amount = amountRaw.toDouble();
    } else if (amountRaw is String) {
      amount = double.tryParse(amountRaw);
    }
    if (amount != null && amount <= 0) amount = null;

    String? type;
    final typeRaw = map['type']?.toString();
    if (typeRaw == 'out' || typeRaw == 'in' || typeRaw == 'transfer') {
      type = typeRaw;
    }

    final categoryHint = map['categoryHint']?.toString();
    final mappedCat = mapCategoryHintToLocal(
      categoryHint,
      categoryNames: names,
      categories: categories,
      preferKind: type == 'in'
          ? 'in'
          : type == 'out'
              ? 'out'
              : null,
    );

    final merchant = _nullIfBlank(map['merchant']?.toString());
    final note = _nullIfBlank(map['note']?.toString());
    // Guard: never accept full input as note.
    final safeNote = (note != null && note.trim() == input.trim()) ? null : note;

    final accountHint = _nullIfBlank(map['accountHint']?.toString());
    final toAccountHint = _nullIfBlank(map['toAccountHint']?.toString());
    String? accountName;
    String? toAccountName;
    if (accountHint != null) {
      accountName = _fuzzyName(accountHint, accountNames);
    }
    if (toAccountHint != null) {
      toAccountName = _fuzzyName(toAccountHint, accountNames);
    }

    final hits = <String>['来源:大模型'];
    if (type != null) {
      hits.add(
        '类型:${type == 'in' ? '收入' : type == 'transfer' ? '转账' : '支出'}',
      );
    }
    if (amount != null) hits.add('金额:$amount');
    if (mappedCat != null) hits.add('分类:$mappedCat');
    if (accountName != null) hits.add('资产账户:$accountName');
    if (toAccountName != null) hits.add('资产账户→$toAccountName');
    if (merchant != null) hits.add('商家:$merchant');
    if (safeNote != null) hits.add('备注:$safeNote');

    final result = AiTextFillResult(
      type: type ?? 'out',
      amount: amount,
      categoryName: mappedCat,
      categoryConfidence: mappedCat != null ? 0.9 : null,
      accountName: accountName,
      toAccountName: toAccountName,
      merchant: merchant,
      note: safeNote,
      hits: hits,
      source: 'llm',
    );
    return result.hasUsefulFill ? result : null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (owned) httpClient.close();
  }
}



/// Parse HTTP error body into a short user-facing status+detail string.
/// Never includes API keys. Public so unit tests can assert / self-prove.
String describeLlmHttpError(int code, String rawBody) {
  var detail = '';
  try {
    final j = jsonDecode(rawBody);
    if (j is Map) {
      final e = j['error'];
      if (e is Map && e['message'] is String) {
        detail = (e['message'] as String).trim();
      } else if (e is String) {
        detail = e.trim();
      } else if (j['message'] is String) {
        detail = (j['message'] as String).trim();
      }
    }
  } catch (_) {}
  if (detail.length > 160) detail = '${detail.substring(0, 160)}…';
  return detail.isEmpty ? 'HTTP $code' : 'HTTP $code · $detail';
}

bool _shouldRetryWithoutDetail(int code, String rawBody) {
  if (code != 400) return false;
  final lower = rawBody.toLowerCase();
  return lower.contains('detail') ||
      lower.contains('unknown') ||
      lower.contains('unsupported');
}

/// Result of [testLlmConnection] (minimal text ping, no image).
class LlmConnectionTestResult {
  const LlmConnectionTestResult({
    required this.ok,
    required this.message,
    this.statusCode,
    this.elapsedMs,
  });

  final bool ok;
  final String message;
  final int? statusCode;
  final int? elapsedMs;
}

/// Minimal text-only ping against the configured OpenAI-compatible endpoint.
Future<LlmConnectionTestResult> testLlmConnection({
  required SmartFillLlmConfig config,
  http.Client? client,
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (config.apiKey.trim().isEmpty) {
    return const LlmConnectionTestResult(
      ok: false,
      message: '请先配置 API Key',
    );
  }
  final base = config.baseUrl.trim().isEmpty
      ? kDefaultLlmBaseUrl
      : config.normalizedBaseUrl;
  final model =
      config.model.trim().isEmpty ? kDefaultLlmModel : config.model.trim();
  final uri = Uri.parse('$base/chat/completions');
  final body = <String, dynamic>{
    'model': model,
    'temperature': 0,
    'max_tokens': 8,
    'messages': [
      {'role': 'user', 'content': 'ping'},
    ],
  };
  final httpClient = client ?? http.Client();
  final owned = client == null;
  final sw = Stopwatch()..start();
  try {
    final resp = await httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey.trim()}',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    sw.stop();
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return LlmConnectionTestResult(
        ok: true,
        message: '✅ 连接正常（模型 $model，耗时 ${sw.elapsedMilliseconds}ms）',
        statusCode: resp.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
    final desc = describeLlmHttpError(resp.statusCode, resp.body);
    return LlmConnectionTestResult(
      ok: false,
      message: '❌ $desc',
      statusCode: resp.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
    );
  } on TimeoutException {
    sw.stop();
    return LlmConnectionTestResult(
      ok: false,
      message: '❌ 网络失败：请求超时',
      elapsedMs: sw.elapsedMilliseconds,
    );
  } catch (e) {
    sw.stop();
    final summary = e.toString();
    final short =
        summary.length > 120 ? '${summary.substring(0, 120)}…' : summary;
    return LlmConnectionTestResult(
      ok: false,
      message: '❌ 网络失败：$short',
      elapsedMs: sw.elapsedMilliseconds,
    );
  } finally {
    if (owned) httpClient.close();
  }
}

/// Thrown when a vision (image) LLM request fails with a user-facing reason.
class LlmVisionException implements Exception {
  LlmVisionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Vision path: image must be in the **user** message; [detail] is `original`.
Future<AiTextFillResult?> parseBookkeepingImageWithLlm(
  Uint8List jpegBytes, {
  required SmartFillLlmConfig config,
  List<String> categoryNames = const [],
  List<CategoryRef> categories = const [],
  List<String> accountNames = const [],
  http.Client? client,
  Duration timeout = const Duration(seconds: 45),
  CentliDatabase? settingsDb,
  void Function(String message)? onCompatHint,
  String userText =
      '请识别这张账单截图，返回与文本填单相同字段的 JSON。',
}) async {
  if (!config.isReady) {
    throw LlmVisionException(
      config.enabled
          ? '请先在「我的 · AI 增强」填写 API Key'
          : '请先在「我的 · AI 增强」启用大模型',
    );
  }
  final names = categories.isNotEmpty
      ? categories.map((c) => c.name).toList()
      : categoryNames;
  final catList = names.take(80).join('、');
  final accList = accountNames.take(40).join('、');
  final system = '''
你是记账助手。从账单截图中抽取结构化字段，只输出一个 JSON 对象，不要 markdown。
字段：
- amount: number|null
- type: "out"|"in"|"transfer"|null
- categoryHint: string|null
- merchant: string|null
- note: string|null
- accountHint: string|null
- toAccountHint: string|null
用户分类：$catList
用户资产账户：$accList
''';

  final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
  final uri = Uri.parse('${config.normalizedBaseUrl}/chat/completions');

  Map<String, dynamic> buildBody({required bool includeDetail}) {
    final imageUrl = <String, dynamic>{'url': dataUrl};
    if (includeDetail) {
      imageUrl['detail'] = 'original';
    }
    return <String, dynamic>{
      'model': config.model,
      'temperature': 0,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': userText},
            {
              'type': 'image_url',
              'image_url': imageUrl,
            },
          ],
        },
      ],
      'response_format': {'type': 'json_object'},
    };
  }

  final httpClient = client ?? http.Client();
  final owned = client == null;
  try {
    Future<http.Response> postOnce(bool includeDetail) {
      return httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: jsonEncode(buildBody(includeDetail: includeDetail)),
          )
          .timeout(timeout);
    }

    var resp = await postOnce(true);
    var strippedDetail = false;
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (_shouldRetryWithoutDetail(resp.statusCode, resp.body)) {
        resp = await postOnce(false);
        strippedDetail = true;
      }
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final desc = describeLlmHttpError(resp.statusCode, resp.body);
      final lower = resp.body.toLowerCase();
      if (resp.statusCode == 400 && lower.contains('image')) {
        throw LlmVisionException(
          '图片识别失败：$desc。当前模型可能不支持图片识别，请换用支持视觉的模型（如 deepseek-flash）',
        );
      }
      throw LlmVisionException('图片识别失败：$desc');
    }
    if (strippedDetail) {
      const hint = '已自动兼容：服务端不接受 detail 字段';
      onCompatHint?.call(hint);
      if (settingsDb != null) {
        await settingsDb.setSetting(kLlmDetailCompatKey, 'true');
      }
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw LlmVisionException('图片识别返回格式异常');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmVisionException('图片识别无结果');
    }
    final msg = choices.first is Map ? choices.first['message'] : null;
    final content = msg is Map ? msg['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw LlmVisionException('图片识别内容为空');
    }
    var jsonStr = _extractJsonObject(content);
    if (jsonStr == null) {
      throw LlmVisionException('图片识别未返回有效 JSON');
    }
    var map = jsonDecode(jsonStr);
    if (map is! Map) {
      throw LlmVisionException('图片识别 JSON 无效');
    }

    final amountRaw = map['amount'];
    double? amount;
    if (amountRaw is num) {
      amount = amountRaw.toDouble();
    } else if (amountRaw is String) {
      amount = double.tryParse(amountRaw);
    }
    if (amount != null && amount <= 0) amount = null;

    String? type;
    final typeRaw = map['type']?.toString();
    if (typeRaw == 'out' || typeRaw == 'in' || typeRaw == 'transfer') {
      type = typeRaw;
    }
    final categoryHint = map['categoryHint']?.toString();
    final mappedCat = mapCategoryHintToLocal(
      categoryHint,
      categoryNames: names,
      categories: categories,
      preferKind: type == 'in'
          ? 'in'
          : type == 'out'
              ? 'out'
              : null,
    );
    final merchant = _nullIfBlank(map['merchant']?.toString());
    final note = _nullIfBlank(map['note']?.toString());
    final accountHint = _nullIfBlank(map['accountHint']?.toString());
    final toAccountHint = _nullIfBlank(map['toAccountHint']?.toString());
    String? accountName;
    String? toAccountName;
    if (accountHint != null) {
      accountName = _fuzzyName(accountHint, accountNames);
    }
    if (toAccountHint != null) {
      toAccountName = _fuzzyName(toAccountHint, accountNames);
    }
    final hits = <String>['来源:视觉大模型'];
    if (amount != null) hits.add('金额:$amount');
    if (mappedCat != null) hits.add('分类:$mappedCat');
    if (merchant != null) hits.add('商家:$merchant');

    return AiTextFillResult(
      type: type,
      amount: amount,
      categoryName: mappedCat,
      categoryConfidence: mappedCat == null ? null : 0.9,
      accountName: accountName,
      toAccountName: toAccountName,
      merchant: merchant,
      note: note,
      hits: hits,
      source: 'llm-vision',
    );
  } on LlmVisionException {
    rethrow;
  } on TimeoutException {
    throw LlmVisionException('图片识别超时，请稍后重试');
  } catch (e) {
    throw LlmVisionException('图片识别失败: $e');
  } finally {
    if (owned) httpClient.close();
  }
}


String? _extractJsonObject(String content) {
  final t = content.trim();
  if (t.startsWith('{') && t.endsWith('}')) return t;
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) return t.substring(start, end + 1);
  return null;
}

String? _nullIfBlank(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty || t.toLowerCase() == 'null') return null;
  return t;
}

String? _fuzzyName(String hint, List<String> names) {
  for (final n in names) {
    if (n == hint) return n;
  }
  for (final n in names) {
    if (n.contains(hint) || hint.contains(n)) return n;
  }
  return null;
}
