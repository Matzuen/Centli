import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'notification_listener_stub.dart';
import 'notification_parse.dart';

/// Hot-reloadable notification templates.
///
/// Official (builtin / assets / documents override) stay read-only in UI.
/// User rules live in a separate documents file and are merged at load:
/// `user ∪ (official − disabled)`.
///
/// Native kill-path ([CentliNotificationListener] / [NativeCaptureIngest]) still
/// uses hardcoded WeChat/Alipay filters; full user-rule bodies are **not**
/// synced to native. Extra package names are written to SharedPreferences
/// (`watched_packages`) so the listener can widen its package filter.
abstract final class NotiTemplateStore {
  static List<NotiTemplate>? _merged;
  static List<NotiTemplate> _official = const [];
  static List<NotiTemplate> _user = const [];
  static Set<String> _disabledOfficialIds = {};
  static int _version = kNotiTemplateFallbackVersion;
  static String _source = 'builtin';
  static String? _updatedAt;
  static bool _loaded = false;
  static int _lastSkippedCount = 0;
  static String? _lastLoadError;

  static int get version => _version;
  static String get source => _source;
  static String? get updatedAt => _updatedAt;
  static bool get isLoaded => _loaded;

  /// Skipped user-template entries from the most recent [_loadUserFile] call.
  /// Reset each load (not cumulative). First-install / missing file → 0.
  static int get lastSkippedCount => _lastSkippedCount;

  /// Structural / I/O error from the most recent [_loadUserFile], if any.
  /// Null when the file is missing (first install) or parse succeeded.
  static String? get lastLoadError => _lastLoadError;

  /// Official templates currently loaded (assets/documents/builtin), including
  /// ones the user disabled locally.
  static List<NotiTemplate> peekOfficial() =>
      List<NotiTemplate>.unmodifiable(_official);

  static List<NotiTemplate> peekUser() =>
      List<NotiTemplate>.unmodifiable(_user);

  static Set<String> peekDisabledOfficialIds() =>
      Set<String>.unmodifiable(_disabledOfficialIds);

  /// Active templates for the parser (user first, then enabled official).
  static List<NotiTemplate> peek() =>
      _merged ?? _merge(_user, _official, _disabledOfficialIds);

  static Future<List<NotiTemplate>> load({bool force = false}) async {
    if (_loaded && !force && _merged != null) {
      return _merged!;
    }

    await _loadOfficial();
    await _loadUserFile();
    _rebuildMerged();
    _loaded = true;
    // Best-effort: widen native package watch list for custom user packages.
    await syncWatchedPackagesToNative();
    return _merged!;
  }

  static Future<void> _loadOfficial() async {
    // 1) Documents override of official bundle
    try {
      final doc = await _officialDocumentsFile();
      if (await doc.exists()) {
        final raw = await doc.readAsString();
        final parsed = _parseOfficialJson(raw);
        if (parsed != null) {
          _official = parsed.templates;
          _version = parsed.version;
          _updatedAt = parsed.updatedAt;
          _source = 'documents';
          return;
        }
      }
    } catch (_) {
      // Fall through.
    }

    // 2) Bundled assets
    try {
      final raw = await rootBundle.loadString('assets/noti_templates.json');
      final parsed = _parseOfficialJson(raw);
      if (parsed != null) {
        _official = parsed.templates;
        _version = parsed.version;
        _updatedAt = parsed.updatedAt;
        _source = 'assets';
        return;
      }
    } catch (_) {
      // Fall through.
    }

    // 3) Builtin
    _official = builtinNotiTemplates();
    _version = kNotiTemplateFallbackVersion;
    _source = 'builtin';
    _updatedAt = null;
  }

  static Future<void> _loadUserFile() async {
    // Do not clear in-memory rules up front — a parse failure must not wipe
    // good state (audit §3.2). Only replace after a successful parse.
    // Reset per-load diagnostics (not cumulative across loads).
    _lastSkippedCount = 0;
    _lastLoadError = null;
    try {
      final doc = await _userDocumentsFile();
      if (!await doc.exists()) {
        // First run / no file yet: empty is correct; no warning / no error.
        if (!_loaded) {
          _user = [];
          _disabledOfficialIds = {};
        }
        return;
      }
      final raw = await doc.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        // Keep previous in-memory; do not wipe.
        _lastLoadError = '规则文件格式有误（根节点不是对象）';
        return;
      }
      final map = Map<String, dynamic>.from(decoded);
      final nextDisabled = <String>{};
      final disabled = map['disabled_official_ids'];
      if (disabled is List) {
        for (final e in disabled) {
          if (e is String && e.isNotEmpty) nextDisabled.add(e);
        }
      }
      // disabled_official_ids parse failure is not counted as skipped rules.
      final list = map['templates'];
      if (list is! List) {
        _lastLoadError = '规则文件格式有误（templates 不是数组）';
        return;
      }
      final templates = <NotiTemplate>[];
      var skipped = 0;
      for (final item in list) {
        if (item is! Map) {
          skipped++;
          continue;
        }
        final parsed = NotiTemplate.tryParse(Map<String, dynamic>.from(item));
        if (parsed != null) {
          templates.add(parsed);
        } else {
          skipped++;
        }
      }
      _lastSkippedCount = skipped;
      _user = templates;
      _disabledOfficialIds = nextDisabled;
    } catch (e) {
      // Keep previous _user / _disabledOfficialIds — never silently clear.
      _lastLoadError = '读取规则文件失败: $e';
    }
  }

  static void _rebuildMerged() {
    _merged = _merge(_user, _official, _disabledOfficialIds);
  }

  static List<NotiTemplate> _merge(
    List<NotiTemplate> user,
    List<NotiTemplate> official,
    Set<String> disabled,
  ) {
    final out = <NotiTemplate>[...user];
    for (final t in official) {
      if (!disabled.contains(t.id)) out.add(t);
    }
    return out;
  }

  /// Compare bundled assets version with active official (documents/assets).
  /// If assets is newer (or documents missing), copy assets → documents.
  /// Does **not** touch user rules.
  static Future<TemplateUpdateResult> checkAndApplyUpdate() async {
    Map<String, dynamic>? assetsJson;
    try {
      final raw = await rootBundle.loadString('assets/noti_templates.json');
      assetsJson = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {
      assetsJson = null;
    }

    final assetsVersion = _readVersion(assetsJson);
    await load(force: true);
    final activeVersion = _version;
    final hadDocuments = await (await _officialDocumentsFile()).exists();

    if (assetsJson == null) {
      return TemplateUpdateResult(
        updated: false,
        activeVersion: activeVersion,
        assetsVersion: assetsVersion,
        message: '无法读取内置模板',
        source: _source,
      );
    }

    final shouldInstall = !hadDocuments || assetsVersion > activeVersion;
    if (!shouldInstall) {
      return TemplateUpdateResult(
        updated: false,
        activeVersion: activeVersion,
        assetsVersion: assetsVersion,
        message: '已是最新（v$activeVersion）',
        source: _source,
      );
    }

    final doc = await _officialDocumentsFile();
    await doc.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await doc.writeAsString(encoder.convert(assetsJson));
    await load(force: true);

    return TemplateUpdateResult(
      updated: true,
      activeVersion: _version,
      assetsVersion: assetsVersion,
      message: hadDocuments
          ? '已更新到 v$_version'
          : '已写入本地覆盖 v$_version',
      source: _source,
    );
  }

  /// Force-install bundled assets into documents (user-triggered refresh).
  static Future<TemplateUpdateResult> installBundledOverride() async {
    try {
      final raw = await rootBundle.loadString('assets/noti_templates.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final doc = await _officialDocumentsFile();
      await doc.parent.create(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      await doc.writeAsString(encoder.convert(json));
      await load(force: true);
      return TemplateUpdateResult(
        updated: true,
        activeVersion: _version,
        assetsVersion: _version,
        message: '已覆盖为内置 v$_version',
        source: _source,
      );
    } catch (e) {
      return TemplateUpdateResult(
        updated: false,
        activeVersion: _version,
        assetsVersion: _version,
        message: '写入失败: $e',
        source: _source,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // User rules CRUD + disable official
  // ---------------------------------------------------------------------------

  static Future<void> setOfficialDisabled(String id, bool disabled) async {
    await load();
    if (disabled) {
      _disabledOfficialIds = {..._disabledOfficialIds, id};
    } else {
      _disabledOfficialIds = {..._disabledOfficialIds}..remove(id);
    }
    await _persistUserFile();
    _rebuildMerged();
    await syncWatchedPackagesToNative();
  }

  static Future<void> upsertUserTemplate(NotiTemplate template) async {
    await load();
    final id = template.id;
    final next = <NotiTemplate>[
      for (final t in _user)
        if (t.id != id) t,
      template,
    ];
    _user = next;
    await _persistUserFile();
    _rebuildMerged();
    await syncWatchedPackagesToNative();
  }

  static Future<void> deleteUserTemplate(String id) async {
    await load();
    _user = [for (final t in _user) if (t.id != id) t];
    await _persistUserFile();
    _rebuildMerged();
    await syncWatchedPackagesToNative();
  }

  /// Replace all user templates (import). Keeps current disabled-official set
  /// unless [disabledOfficialIds] is provided.
  static Future<void> replaceUserTemplates(
    List<NotiTemplate> templates, {
    Set<String>? disabledOfficialIds,
  }) async {
    await load();
    _user = List<NotiTemplate>.from(templates);
    if (disabledOfficialIds != null) {
      _disabledOfficialIds = Set<String>.from(disabledOfficialIds);
    }
    await _persistUserFile();
    _rebuildMerged();
    await syncWatchedPackagesToNative();
  }

  static Future<String> exportUserRulesJson() async {
    await load();
    return _encodeUserFile();
  }

  /// Import user rules JSON. Returns count of templates imported.
  static Future<int> importUserRulesJson(String raw, {bool merge = true}) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('根节点必须是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    final list = map['templates'];
    if (list is! List) {
      throw const FormatException('缺少 templates 数组');
    }
    final imported = <NotiTemplate>[];
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      final parsed = NotiTemplate.tryParse(Map<String, dynamic>.from(item));
      if (parsed == null) {
        continue;
      }
      imported.add(parsed);
    }
    if (imported.isEmpty && list.isNotEmpty) {
      throw FormatException(
        '导入失败：全部 ${list.length} 条规则校验未通过（schema/正则）',
      );
    }
    Set<String>? disabled;
    final d = map['disabled_official_ids'];
    if (d is List) {
      disabled = {
        for (final e in d)
          if (e is String && e.isNotEmpty) e,
      };
    }

    await load();
    if (merge) {
      final byId = <String, NotiTemplate>{
        for (final t in _user) t.id: t,
        for (final t in imported) t.id: t,
      };
      await replaceUserTemplates(
        byId.values.toList(),
        disabledOfficialIds: disabled ?? _disabledOfficialIds,
      );
    } else {
      await replaceUserTemplates(
        imported,
        disabledOfficialIds: disabled ?? _disabledOfficialIds,
      );
    }
    return imported.length;
  }

  /// Fetch user-rules JSON from an HTTPS URL, then [importUserRulesJson].
  /// Does **not** run on startup — only when the user triggers it.
  /// Throws [FormatException] / [TimeoutException] / [HttpException]-style
  /// messages with Chinese-friendly text for the UI.
  static Future<int> importUserRulesFromUrl(
    String url, {
    bool merge = true,
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('请填写规则 JSON 的 HTTPS 地址');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('URL 无效');
    }
    if (uri.scheme.toLowerCase() != 'https') {
      throw const FormatException('仅支持 HTTPS 地址');
    }

    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient.get(uri).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw FormatException('下载失败（HTTP ${res.statusCode}）');
      }
      final body = res.body;
      if (body.trim().isEmpty) {
        throw const FormatException('响应内容为空');
      }
      return await importUserRulesJson(body, merge: merge);
    } on TimeoutException {
      throw const FormatException('下载超时，请检查网络后重试');
    } on FormatException {
      rethrow;
    } on http.ClientException catch (e) {
      throw FormatException('网络错误: ${e.message}');
    } on SocketException catch (e) {
      throw FormatException('无法连接: ${e.message}');
    } catch (e) {
      if (e is FormatException) rethrow;
      // jsonDecode / schema errors propagate as FormatException from import
      if (e.toString().contains('FormatException')) rethrow;
      throw FormatException('导入失败: $e');
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static Future<void> _persistUserFile() async {
    final doc = await _userDocumentsFile();
    await doc.parent.create(recursive: true);
    // Backup previous file before overwrite (audit §3.2).
    if (await doc.exists()) {
      try {
        final bakFile = File('${doc.path}.bak');
        await doc.copy(bakFile.path);
      } catch (_) {
        // Best-effort backup; still proceed to write.
      }
    }
    await doc.writeAsString(_encodeUserFile());
  }

  static String _encodeUserFile() {
    final map = <String, dynamic>{
      'version': 1,
      'updated_at': DateTime.now().toIso8601String().split('T').first,
      'disabled_official_ids': _disabledOfficialIds.toList()..sort(),
      'templates': [for (final t in _user) t.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Push union of official + user package names to native SharedPreferences.
  /// Safe no-op on non-Android / missing plugin.
  static Future<void> syncWatchedPackagesToNative() async {
    final pkgs = <String>{};
    for (final t in peek()) {
      pkgs.addAll(t.packages);
    }
    if (pkgs.isEmpty) {
      pkgs.addAll(const [
        'com.eg.android.AlipayGphone',
        'com.tencent.mm',
      ]);
    }
    await NotificationCaptureStub.setWatchedPackages(pkgs.toList()..sort());
  }

  static Future<File> _officialDocumentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'noti_templates.json'));
  }

  static Future<File> _userDocumentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'user_noti_templates.json'));
  }

  static _ParsedTemplates? _parseOfficialJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final list = map['templates'];
    if (list is! List) return null;
    final templates = <NotiTemplate>[];
    for (final item in list) {
      if (item is! Map) continue;
      final parsed = NotiTemplate.tryParse(Map<String, dynamic>.from(item));
      if (parsed != null) templates.add(parsed);
    }
    if (templates.isEmpty) return null;
    return _ParsedTemplates(
      version: _readVersion(map),
      updatedAt: map['updated_at'] as String?,
      templates: templates,
    );
  }

  static int _readVersion(Map<String, dynamic>? map) {
    if (map == null) return kNotiTemplateFallbackVersion;
    final v = map['version'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return kNotiTemplateFallbackVersion;
  }
}

class _ParsedTemplates {
  const _ParsedTemplates({
    required this.version,
    required this.updatedAt,
    required this.templates,
  });
  final int version;
  final String? updatedAt;
  final List<NotiTemplate> templates;
}

class TemplateUpdateResult {
  const TemplateUpdateResult({
    required this.updated,
    required this.activeVersion,
    required this.assetsVersion,
    required this.message,
    required this.source,
  });
  final bool updated;
  final int activeVersion;
  final int assetsVersion;
  final String message;
  final String source;
}

/// Keep in sync with assets/noti_templates.json `version`.
const int kNotiTemplateFallbackVersion = 5;
