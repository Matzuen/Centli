import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/currencies.dart';
import '../../core/utils/fx.dart';
import '../db/centli_database.dart';

/// Result of one remote FX pull into the local [fx_rates] cache.
class FxRemoteRefreshResult {
  const FxRemoteRefreshResult({
    required this.day,
    required this.baseCurrency,
    required this.upserted,
    required this.skipped,
    required this.source,
    required this.providerDayUtc,
  });

  /// Local calendar day used as quote [FxRate.day] (yyyy-MM-dd).
  final String day;
  final String baseCurrency;
  final int upserted;
  final List<String> skipped;
  final String source;

  /// Provider's last-update instant, formatted for UI.
  final String providerDayUtc;
}

/// Fetches daily FX from open.er-api.com (no API key) and upserts into Drift.
///
/// API semantics: 1 [base] = rates[C] [C].
/// Cache semantics (matches [FxBook]): 1 [fromCcy] = [rate] [toCcy],
/// so we store foreign → base as rate = 1 / rates[foreign].
class FxRemoteService {
  FxRemoteService({http.Client? client}) : _client = client ?? http.Client();

  static const sourceId = 'open.er-api.com';
  static const _endpoint = 'https://open.er-api.com/v6/latest';

  /// Setting: last successful local refresh day (yyyy-MM-dd).
  static const lastDayKey = 'fx_remote_last_day';

  /// Setting: `'false'` disables splash / page auto refresh. Default on.
  static const autoKey = 'fx_remote_auto';

  final http.Client _client;

  /// Pull rates for [baseCurrency] and upsert foreign→base quotes.
  Future<FxRemoteRefreshResult> refreshToBase({
    required CentliDatabase db,
    required String baseCurrency,
  }) async {
    final base = baseCurrency.toUpperCase();
    if (!supportedCurrencies.contains(base)) {
      throw ArgumentError('不支持的本位币: $base');
    }

    final uri = Uri.parse('$_endpoint/$base');
    final res = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('汇率请求失败（HTTP ${res.statusCode}）');
    }

    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('汇率响应不是有效的 JSON');
    }
    if (body['result'] != 'success') {
      throw FormatException('汇率服务返回异常: ${body['result']}');
    }
    final ratesRaw = body['rates'];
    if (ratesRaw is! Map) {
      throw const FormatException('汇率数据缺失');
    }
    final rates = <String, double>{};
    ratesRaw.forEach((k, v) {
      if (k is! String) return;
      final n = v is num ? v.toDouble() : double.tryParse('$v');
      if (n != null && n > 0) rates[k.toUpperCase()] = n;
    });

    final unix = body['time_last_update_unix'];
    final DateTime asOfLocal;
    if (unix is num) {
      asOfLocal = DateTime.fromMillisecondsSinceEpoch(
        (unix.toInt()) * 1000,
        isUtc: true,
      ).toLocal();
    } else {
      asOfLocal = DateTime.now();
    }
    final day = FxBook.formatDay(asOfLocal);
    final providerUtc = body['time_last_update_utc']?.toString() ?? day;

    final skipped = <String>[];
    var upserted = 0;

    await db.transaction(() async {
      for (final ccy in supportedCurrencies) {
        if (ccy == base) continue;
        final apiRate = rates[ccy];
        if (apiRate == null || apiRate <= 0) {
          skipped.add(ccy);
          continue;
        }
        // 1 base = apiRate ccy  ⇒  1 ccy = 1/apiRate base
        final foreignToBase = 1.0 / apiRate;
        await db.upsertFxRate(
          day: day,
          fromCcy: ccy,
          toCcy: base,
          rate: foreignToBase,
          source: sourceId,
        );
        upserted++;
      }
    });

    await db.setSetting(lastDayKey, FxBook.todayLocal());
    await db.setSetting('fx_remote_last_source', sourceId);
    await db.setSetting('fx_remote_last_provider_utc', providerUtc);

    return FxRemoteRefreshResult(
      day: day,
      baseCurrency: base,
      upserted: upserted,
      skipped: skipped,
      source: sourceId,
      providerDayUtc: providerUtc,
    );
  }

  /// Once-per-local-day remote pull when auto is enabled.
  /// Returns the result when a refresh ran; null when skipped.
  Future<FxRemoteRefreshResult?> maybeAutoRefresh({
    required CentliDatabase db,
    required String baseCurrency,
  }) async {
    final auto = await db.getSetting(autoKey);
    if (auto == 'false') return null;
    final last = await db.getSetting(lastDayKey);
    final today = FxBook.todayLocal();
    if (last == today) return null;
    return refreshToBase(db: db, baseCurrency: baseCurrency);
  }
}

/// Fire-and-forget daily FX pull (splash / home). Errors are swallowed.
void scheduleFxAutoRefresh(CentliDatabase db, String? baseCurrency) {
  final base = baseCurrency ?? 'CNY';
  unawaited(() async {
    try {
      await FxRemoteService().maybeAutoRefresh(db: db, baseCurrency: base);
    } catch (_) {
      // Offline / provider down — keep manual cache; user can retry on FX page.
    }
  }());

}
