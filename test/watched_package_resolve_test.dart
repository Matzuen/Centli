import 'package:centli/platform/notifications/watched_package_resolve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid package name passes through', () {
    expect(
      resolvePackageInput('com.android.bankabc'),
      ['com.android.bankabc'],
    );
    expect(packageInputError('com.android.bankabc'), isNull);
  });

  test('Chinese ABC bank aliases expand', () {
    final pkgs = resolvePackageInput('中国农业银行');
    expect(pkgs, contains('com.android.bankabc'));
    expect(packageInputError('中国农业银行'), isNull);
  });

  test('garbage Chinese without alias fails', () {
    expect(resolvePackageInput('随便一个软件'), isEmpty);
    expect(packageInputError('随便一个软件'), isNotNull);
  });

  test('looksLikeAndroidPackageName', () {
    expect(looksLikeAndroidPackageName('com.foo.bar'), isTrue);
    expect(looksLikeAndroidPackageName('中国农业银行'), isFalse);
  });
}
