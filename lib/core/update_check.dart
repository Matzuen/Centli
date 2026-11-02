import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';

/// GitHub 仓库（remote `github` → Matzuen/Centli）。
/// 优先读 Releases；若无 Release（常见于仅打 tag），回退到 tags。
const String kCentliGithubOwner = 'Matzuen';
const String kCentliGithubRepo = 'Centli';

Uri get kCentliGithubReleasesPage => Uri.parse(
      'https://github.com/$kCentliGithubOwner/$kCentliGithubRepo/releases',
    );

Uri get kCentliGithubTagsPage => Uri.parse(
      'https://github.com/$kCentliGithubOwner/$kCentliGithubRepo/tags',
    );

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.localVersion,
    required this.hasUpdate,
    required this.message,
    this.remoteVersion,
    this.openUrl,
  });

  final String localVersion;
  final bool hasUpdate;
  final String message;
  final String? remoteVersion;

  /// 浏览器打开的发布页 / tag 页。
  final Uri? openUrl;
}

/// 比较两个版本名（可带 `v` 前缀与 `+build`）。返回 >0 / 0 / <0。
int compareAppVersions(String a, String b) {
  List<int> parts(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final out = <int>[];
    for (final p in s.split('.')) {
      out.add(int.tryParse(p.replaceAll(RegExp(r'[^0-9].*$'), '')) ?? 0);
    }
    while (out.length < 3) {
      out.add(0);
    }
    return out;
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = pa[i] - pb[i];
    if (d != 0) return d;
  }
  return 0;
}

Future<String> _loadLocalVersionName() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final name = info.version.trim();
    if (name.isNotEmpty) return name;
  } catch (_) {}
  return displayAppVersion(kAppVersionFallback);
}

Future<AppUpdateCheckResult> checkForAppUpdate({
  http.Client? client,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final local = await _loadLocalVersionName();
  final c = client ?? http.Client();
  final owned = client == null;
  try {
    final headers = {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Centli-UpdateCheck',
    };

    // 1) Latest GitHub Release
    final releaseUri = Uri.parse(
      'https://api.github.com/repos/$kCentliGithubOwner/$kCentliGithubRepo/releases/latest',
    );
    final releaseResp =
        await c.get(releaseUri, headers: headers).timeout(timeout);
    if (releaseResp.statusCode == 200) {
      final map = jsonDecode(releaseResp.body);
      if (map is Map<String, dynamic>) {
        final tag = (map['tag_name'] as String?)?.trim() ?? '';
        final htmlUrl = (map['html_url'] as String?)?.trim();
        if (tag.isNotEmpty) {
          final tagName = tag.startsWith('v') || tag.startsWith('V')
              ? tag.substring(1)
              : tag;
          final remoteShown = displayAppVersion(tagName);
          final newer = compareAppVersions(tag, local) > 0;
          final open = (htmlUrl != null && htmlUrl.isNotEmpty)
              ? Uri.tryParse(htmlUrl)
              : kCentliGithubReleasesPage;
          return AppUpdateCheckResult(
            localVersion: local,
            remoteVersion: remoteShown,
            hasUpdate: newer,
            openUrl: open,
            message: newer
                ? '发现新版本 $remoteShown（当前 $local）'
                : '已是最新版本（$local）',
          );
        }
      }
    } else if (releaseResp.statusCode != 404) {
      return AppUpdateCheckResult(
        localVersion: local,
        hasUpdate: false,
        message: '检查更新失败（HTTP ${releaseResp.statusCode}）',
      );
    }

    // 2) Fallback: newest tag
    final tagsUri = Uri.parse(
      'https://api.github.com/repos/$kCentliGithubOwner/$kCentliGithubRepo/tags?per_page=20',
    );
    final tagsResp = await c.get(tagsUri, headers: headers).timeout(timeout);
    if (tagsResp.statusCode != 200) {
      return AppUpdateCheckResult(
        localVersion: local,
        hasUpdate: false,
        message: '检查更新失败（无法读取 GitHub tags，HTTP ${tagsResp.statusCode}）',
      );
    }
    final list = jsonDecode(tagsResp.body);
    if (list is! List || list.isEmpty) {
      return AppUpdateCheckResult(
        localVersion: local,
        hasUpdate: false,
        openUrl: kCentliGithubTagsPage,
        message: '远端暂无版本标签（当前 $local）',
      );
    }

    String? bestTag;
    for (final item in list) {
      if (item is! Map) continue;
      final name = (item['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      if (bestTag == null || compareAppVersions(name, bestTag) > 0) {
        bestTag = name;
      }
    }
    if (bestTag == null) {
      return AppUpdateCheckResult(
        localVersion: local,
        hasUpdate: false,
        openUrl: kCentliGithubTagsPage,
        message: '远端暂无有效版本标签（当前 $local）',
      );
    }

    final remoteName = displayAppVersion(
      bestTag.startsWith('v') || bestTag.startsWith('V')
          ? bestTag.substring(1)
          : bestTag,
    );
    final newer = compareAppVersions(bestTag, local) > 0;
    return AppUpdateCheckResult(
      localVersion: local,
      remoteVersion: remoteName,
      hasUpdate: newer,
      openUrl: kCentliGithubTagsPage,
      message: newer
          ? '发现新版本 $remoteName（当前 $local）'
          : '已是最新版本（$local）',
    );
  } on Exception catch (_) {
    return AppUpdateCheckResult(
      localVersion: local,
      hasUpdate: false,
      message: '检查更新失败：网络异常，请稍后重试',
    );
  } finally {
    if (owned) c.close();
  }
}

Future<bool> openAppUpdatePage(Uri? url) async {
  final target = url ?? kCentliGithubReleasesPage;
  return launchUrl(target, mode: LaunchMode.externalApplication);
}
