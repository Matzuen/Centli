import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('golden comparator is default (no tolerance wrapper) OR documented cap', () {
    final typeName = goldenFileComparator.runtimeType.toString();
    expect(typeName, contains('LocalFileComparator'));
    // If a Tolerant wrapper is installed by another suite, that is checked below via source.
  });

  test('kGoldenMaxDiffPercent in golden suite is at most 0.01 when present', () {
    final src = File('test/golden/bookkeeping_panel_golden_test.dart').readAsStringSync();
    if (src.contains('kGoldenMaxDiffPercent')) {
      final m = RegExp(r'kGoldenMaxDiffPercent\s*=\s*([0-9.]+)').firstMatch(src);
      expect(m, isNotNull);
      final v = double.parse(m!.group(1)!);
      expect(v, lessThanOrEqualTo(0.01));
    } else {
      // Strict default comparator path: no tolerance constant.
      expect(src.contains('_TolerantGoldenComparator'), isFalse);
    }
  });

  test('source must not reintroduce 0.05pct tolerance', () {
    final src = File('test/golden/bookkeeping_panel_golden_test.dart').readAsStringSync();
    expect(src.contains('0.05'), isFalse);
  });
}
