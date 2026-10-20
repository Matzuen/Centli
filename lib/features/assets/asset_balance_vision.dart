/// LLM vision: screenshot → structured asset balances (confirm before write).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/currencies.dart';
import '../../data/db/centli_database.dart';
import '../ledger/llm_text_fill.dart';

class AssetBalanceVisionHit {
  const AssetBalanceVisionHit({
    required this.name,
    required this.balance,
    required this.currency,
    required this.typeHint,
    required this.isLiability,
  });

  final String name;
  final double balance;
  final String currency;
  final String typeHint;
  final bool isLiability;
}

class AssetBalanceVisionResult {
  const AssetBalanceVisionResult({
    required this.accounts,
    this.warnings = const [],
    this.screenKind = 'unknown',
  });

  final List<AssetBalanceVisionHit> accounts;
  final List<String> warnings;
  final String screenKind;
}

/// Parse a wallet / bank / assets screenshot into account balances.
Future<AssetBalanceVisionResult> parseAssetBalancesImageWithLlm(
  Uint8List jpegBytes, {
  required SmartFillLlmConfig config,
  List<String> accountNames = const [],
  List<String> typeNames = const [],
  String baseCurrency = 'CNY',
  http.Client? client,
  Duration timeout = const Duration(seconds: 45),
  CentliDatabase? settingsDb,
}) async {
  if (!config.isReady) {
    throw LlmVisionException(
      config.enabled
          ? '请先在「我的 · 智能填单」填写 API Key'
          : '请先在「我的 · 智能填单」启用大模型',
    );
  }
  final accList = accountNames.take(40).join('、');
  final typeList = typeNames.take(20).join('、');
  final system = '''
你是资产盘点助手。从截图中识别各个资产账户/钱包/银行卡的名称与余额，只输出一个 JSON 对象，不要 markdown。
字段：
- screenKind: "asset_overview"|"single_wallet"|"unknown"
- accounts: 数组，每项：
  - name: string 资产账户显示名（尽量短，如「支付宝」「招商银行」）
  - balance: number 余额（负债/欠款用负数）
  - currency: string ISO 币种，默认 "$baseCurrency"
  - typeHint: string 从用户资产分类中选一个最接近的：$typeList
  - isLiability: boolean 是否负债资产账户
- warnings: string[] 可选，识别不确定时的提示
用户已有资产账户：$accList
规则：忽略合计/净资产/总资产等汇总行；信用卡欠款写负余额；同一资产账户只出现一次。
''';

  final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
  final uri = Uri.parse('${config.normalizedBaseUrl}/chat/completions');

  Map<String, dynamic> buildBody({required bool includeDetail}) {
    final imageUrl = <String, dynamic>{'url': dataUrl};
    if (includeDetail) imageUrl['detail'] = 'original';
    return <String, dynamic>{
      'model': config.model,
      'temperature': 0,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': '请识别这张资产/钱包/银行卡截图中的资产账户与余额，返回 JSON。',
            },
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
      final lower = resp.body.toLowerCase();
      if (resp.statusCode == 400 &&
          (lower.contains('detail') || lower.contains('image_url'))) {
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
    if (strippedDetail && settingsDb != null) {
      await settingsDb.setSetting(kLlmDetailCompatKey, 'true');
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
    final jsonStr = _extractJsonObject(content);
    if (jsonStr == null) {
      throw LlmVisionException('图片识别未返回有效 JSON');
    }
    final map = jsonDecode(jsonStr);
    if (map is! Map) {
      throw LlmVisionException('图片识别 JSON 无效');
    }
    return parseAssetBalanceVisionMap(
      Map<String, dynamic>.from(map),
      fallbackCurrency: baseCurrency,
      typeNames: typeNames,
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

/// Pure JSON → result (unit-tested).
AssetBalanceVisionResult parseAssetBalanceVisionMap(
  Map<String, dynamic> map, {
  String fallbackCurrency = 'CNY',
  List<String> typeNames = const [],
}) {
  final screenKind = map['screenKind']?.toString() ?? 'unknown';
  final warnings = <String>[];
  final rawWarnings = map['warnings'];
  if (rawWarnings is List) {
    for (final w in rawWarnings) {
      final s = w?.toString().trim();
      if (s != null && s.isNotEmpty) warnings.add(s);
    }
  }
  final accounts = <AssetBalanceVisionHit>[];
  final rawAccounts = map['accounts'];
  if (rawAccounts is List) {
    for (final item in rawAccounts) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final balanceRaw = item['balance'];
      double? balance;
      if (balanceRaw is num) {
        balance = balanceRaw.toDouble();
      } else if (balanceRaw is String) {
        balance = double.tryParse(balanceRaw.replaceAll(',', ''));
      }
      if (balance == null) continue;
      var currency = (item['currency']?.toString() ?? fallbackCurrency)
          .trim()
          .toUpperCase();
      if (!supportedCurrencies.contains(currency)) {
        currency = fallbackCurrency;
      }
      var typeHint = item['typeHint']?.toString().trim() ?? '';
      if (typeHint.isEmpty ||
          (typeNames.isNotEmpty && !typeNames.contains(typeHint))) {
        typeHint = _guessTypeHint(name, item['isLiability'] == true, typeNames);
      }
      final isLiability = item['isLiability'] == true || balance < 0;
      accounts.add(
        AssetBalanceVisionHit(
          name: name,
          balance: balance,
          currency: currency,
          typeHint: typeHint,
          isLiability: isLiability,
        ),
      );
    }
  }
  if (accounts.isEmpty) {
    throw LlmVisionException('没有识别到资产账户余额，请换一张更清晰的截图');
  }
  return AssetBalanceVisionResult(
    accounts: accounts,
    warnings: warnings,
    screenKind: screenKind,
  );
}

/// Fuzzy-match a recognized name to an existing account.
Account? matchAccountByName(String name, List<Account> accounts) {
  final hint = name.trim();
  if (hint.isEmpty) return null;
  for (final a in accounts) {
    if (a.name == hint) return a;
  }
  for (final a in accounts) {
    if (a.name.contains(hint) || hint.contains(a.name)) return a;
  }
  return null;
}

String _guessTypeHint(String name, bool liability, List<String> typeNames) {
  if (liability) {
    if (typeNames.contains('信用卡')) return '信用卡';
  }
  final n = name.toLowerCase();
  if (n.contains('支付宝') ||
      n.contains('微信') ||
      n.contains('零钱') ||
      n.contains('钱包')) {
    if (typeNames.contains('电子钱包')) return '电子钱包';
  }
  if (n.contains('银行') || n.contains('储蓄') || n.contains('卡')) {
    if (typeNames.contains('银行卡')) return '银行卡';
  }
  if (n.contains('现金')) {
    if (typeNames.contains('现金')) return '现金';
  }
  if (typeNames.contains('其他')) return '其他';
  return typeNames.isNotEmpty ? typeNames.first : '其他';
}

String? _extractJsonObject(String content) {
  final t = content.trim();
  if (t.startsWith('{') && t.endsWith('}')) return t;
  final start = t.indexOf('{');
  final end = t.lastIndexOf('}');
  if (start >= 0 && end > start) return t.substring(start, end + 1);
  return null;
}
