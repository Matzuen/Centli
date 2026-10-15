import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'notification_parse.dart';

/// Hot-reloadable notification templates.
/// Load order: documents override → bundled assets → builtin const.
abstract final class NotiTemplateStore {
  static List<NotiTemplate>? _templates;
  static int _version = kNotiTemplateFallbackVersion;
  static String _source = 'builtin';
  static String? _updatedAt;
  static bool _loaded = false;

  static int get version => _version;
  static String get source => _source;
  static String? get updatedAt => _updatedAt;
  static bool get isLoaded => _loaded;

  static List<NotiTemplate> peek() =>
      _templates ?? builtinNotiTemplates();

  static Future<List<NotiTemplate>> load({bool force = false}) async {
    if (_loaded && !force && _templates != null) {
      return _templates!;
    }

    // 1) Documents override
    try {
      final doc = await _documentsFile();
      if (await doc.exists()) {
        final raw = await doc.readAsString();
        final parsed = _parseJson(raw);
        if (parsed != null) {
          _apply(parsed, source: 'documents');
          _loaded = true;
          return _templates!;
        }
      }
    } catch (_) {
      // Fall through.
    }

    // 2) Bundled assets
    try {
      final raw = await rootBundle.loadString('assets/noti_templates.json');
      final parsed = _parseJson(raw);
      if (parsed != null) {
        _apply(parsed, source: 'assets');
        _loaded = true;
        return _templates!;
      }
    } catch (_) {
      // Fall through.
    }

    // 3) Builtin
    _templates = builtinNotiTemplates();
    _version = kNotiTemplateFallbackVersion;
    _source = 'builtin';
    _updatedAt = null;
    _loaded = true;
    return _templates!;
  }

  /// Compare bundled assets version with active (documents/assets).
  /// If assets is newer (or documents missing), copy assets → documents.
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
    final hadDocuments = await (await _documentsFile()).exists();

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

    final doc = await _documentsFile();
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
      final doc = await _documentsFile();
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

  static Future<File> _documentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'noti_templates.json'));
  }

  static _ParsedTemplates? _parseJson(String raw) {
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

  static void _apply(_ParsedTemplates parsed, {required String source}) {
    _templates = parsed.templates;
    _version = parsed.version;
    _updatedAt = parsed.updatedAt;
    _source = source;
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
