import 'dart:io';

import 'package:centli/core/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kAppVersionFallback matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(kAppVersionFallback, m!.group(1));
  });

  test('displayAppVersion hides build number', () {
    expect(displayAppVersion('2.1.2+44'), '2.1.2');
    expect(displayAppVersion('2.1.2'), '2.1.2');
    expect(displayAppVersion(kAppVersionFallback), '2.1.2');
  });
}
