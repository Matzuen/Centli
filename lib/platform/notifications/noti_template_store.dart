import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
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

  static int get version => _version;
  static String get source => _source;
  static String? get updatedAt => _updatedAt;
  static bool get isLoaded => _loaded;

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
    _user = [];
    _disabledOfficialIds = {};
    try {
      final doc = await _userDocumentsFile();
      if (!await doc.exists()) return;
      final raw = await doc.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final disabled = map['disabled_official_ids'];
      if (disabled is List) {
        _disabledOfficialIds = {
          for (final e in disabled)
            if (e is String && e.isNotEmpty) e,
        };
      }
      final list = map['templates'];
      if (list is! List) return;
      final templates = <NotiTemplate>[];
      for (final item in list) {
        if (item is Map) {
          templates.add(
            NotiTemplate.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
      _user = templates;
    } catch (_) {
      _user = [];
      _disabledOfficialIds = {};
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
      if (item is Map) {
        imported.add(NotiTemplate.fromJson(Map<String, dynamic>.from(item)));
      }
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

  static Future<void> _persistUserFile() async {
    final doc = await _userDocumentsFile();
    await doc.parent.create(recursive: true);
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
      if (item is Map) {
        templates.add(
          NotiTemplate.fromJson(Map<String, dynamic>.from(item)),
        );
      }
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
const int kNotiTemplateFallbackVersion = 3;
