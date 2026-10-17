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

const String kLlmEnabledSettingKey = 'smart_fill_llm_enabled';
const String kLlmBaseUrlSettingKey = 'smart_fill_llm_base_url';
const String kLlmModelSettingKey = 'smart_fill_llm_model';
const String kLlmApiKeyStorageKey = 'centli_smart_fill_llm_api_key';

const String kDefaultLlmBaseUrl = 'https://api.deepseek.com';
const String kDefaultLlmModel = 'deepseek-flash';

class SmartFillLlmConfig {
  const SmartFillLlmConfig({
    required this.enabled,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final bool enabled;
  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isReady =>
      enabled && baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

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

  Future<SmartFillLlmConfig> load(CentliDatabase db) async {
    final enabled = (await db.getSetting(kLlmEnabledSettingKey)) == 'true';
    final base = (await db.getSetting(kLlmBaseUrlSettingKey))?.trim();
    final model = (await db.getSetting(kLlmModelSettingKey))?.trim();
    final key = (await _storage.read(key: kLlmApiKeyStorageKey)) ?? '';
    return SmartFillLlmConfig(
      enabled: enabled,
      baseUrl: (base == null || base.isEmpty) ? kDefaultLlmBaseUrl : base,
      model: (model == null || model.isEmpty) ? kDefaultLlmModel : model,
      apiKey: key,
    );
  }

  Future<void> save({
    required CentliDatabase db,
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
    bool clearApiKey = false,
  }) async {
    await db.setSetting(kLlmEnabledSettingKey, enabled ? 'true' : 'false');
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
- note: string|null 去掉金额/分类/商家/账户后的剩余备注；没有则 null
- accountHint: string|null 付款账户
- toAccountHint: string|null 转入账户（仅转账）
用户分类：$catList
用户账户：$accList
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
    if (accountName != null) hits.add('账户:$accountName');
    if (toAccountName != null) hits.add('账户→$toAccountName');
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
  String userText =
      '请识别这张账单截图，返回与文本填单相同字段的 JSON。',
}) async {
  if (!config.isReady) {
    throw LlmVisionException('请先在智能填单里启用大模型并填写 API Key');
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
用户账户：$accList
''';

  final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
  final uri = Uri.parse('${config.normalizedBaseUrl}/chat/completions');
  final body = <String, dynamic>{
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
            'image_url': {'url': dataUrl, 'detail': 'original'},
          },
        ],
      },
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
      final errBody = resp.body.toLowerCase();
      if (resp.statusCode == 400 && errBody.contains('image')) {
        throw LlmVisionException(
          '当前模型可能不支持图片识别，请换用支持视觉的模型（如 deepseek-flash）',
        );
      }
      throw LlmVisionException('图片识别请求失败（HTTP ${resp.statusCode}）');
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
