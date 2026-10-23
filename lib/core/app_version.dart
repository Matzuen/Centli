import 'package:package_info_plus/package_info_plus.dart';

/// 单一来源：仅在 PackageInfo 不可用（测试 / 首帧）时使用。
/// 必须与 pubspec.yaml 的 `version:` 整段（含构建号）保持一致 ——
/// 由 test/app_version_test.dart 守卫。
const String kAppVersionFallback = '2.1.2+45';

/// 给用户看的版本名（不含构建号）。`2.1.2+45` → `2.1.2`。
String displayAppVersion(String full) {
  final t = full.trim();
  if (t.isEmpty) return t;
  final i = t.indexOf('+');
  if (i <= 0) return t;
  return t.substring(0, i);
}

/// UI 用：只返回版本名；构建号仍在 pubspec / 商店侧，不展示。
Future<String> loadDisplayAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final name = info.version.trim();
    if (name.isNotEmpty) return name;
  } catch (_) {}
  return displayAppVersion(kAppVersionFallback);
}
