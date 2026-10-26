import 'package:centli/core/utils/budget_progress_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FED));

  group('BudgetProgressStyle.barColor', () {
    test('below warnStart uses primary', () {
      expect(
        BudgetProgressStyle.barColor(scheme, 0.69),
        scheme.primary,
      );
    });

    test('at warnStart starts yellow side of lerp', () {
      expect(
        BudgetProgressStyle.barColor(scheme, BudgetProgressStyle.warnStart),
        BudgetProgressStyle.yellow,
      );
    });

    test('mid warn range is between yellow and orangeRed', () {
      final c = BudgetProgressStyle.barColor(scheme, 0.85);
      expect(c, isNot(BudgetProgressStyle.yellow));
      expect(c, isNot(BudgetProgressStyle.orangeRed));
      expect(c, isNot(scheme.primary));
      expect(c, isNot(scheme.error));
    });

    test('at 1.0 and above uses error', () {
      expect(BudgetProgressStyle.barColor(scheme, 1.0), scheme.error);
      expect(BudgetProgressStyle.barColor(scheme, 1.2), scheme.error);
    });
  });

  group('BudgetProgressStyle.labelColor', () {
    test('over forces error', () {
      expect(
        BudgetProgressStyle.labelColor(scheme, 0.5, over: true),
        scheme.error,
      );
    });

    test('calm range uses onSurface', () {
      expect(
        BudgetProgressStyle.labelColor(scheme, 0.4, over: false),
        scheme.onSurface,
      );
    });
  });

  test('notifyAt is 0.80', () {
    expect(BudgetProgressStyle.notifyAt, 0.80);
    expect(BudgetProgressStyle.warnStart, 0.70);
  });
}
