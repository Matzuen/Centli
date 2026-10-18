/// 单一来源：仅在 PackageInfo 不可用（测试 / 首帧）时使用。
/// 必须与 pubspec.yaml 的 version 保持一致 —— 由 test/app_version_test.dart 守卫。
const String kAppVersionFallback = '1.10.5+36';
