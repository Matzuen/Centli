import 'package:centli/core/utils/money.dart';
import 'package:centli/core/widgets/centli_trend_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickTrendChartXLabelIndices', () {
    test('empty and single', () {
      expect(pickTrendChartXLabelIndices(0), isEmpty);
      expect(pickTrendChartXLabelIndices(1), [0]);
    });

    test('small n shows all', () {
      expect(pickTrendChartXLabelIndices(5, maxLabels: 5), [0, 1, 2, 3, 4]);
    });

    test('31-day month keeps ends and avoids stacking last two', () {
      final indices = pickTrendChartXLabelIndices(31, maxLabels: 5);
      expect(indices.first, 0);
      expect(indices.last, 30);
      // Old bug: 28 (10/29) and 30 (10/31) both labeled — gap must be enough.
      for (var k = 1; k < indices.length; k++) {
        expect(
          indices[k] - indices[k - 1],
          greaterThanOrEqualTo(4),
          reason: 'adjacent labels ${indices[k - 1]} and ${indices[k]} too close',
        );
      }
      expect(indices.contains(28) && indices.contains(30), isFalse);
    });

    test('narrow maxLabels still includes first and last', () {
      final indices = pickTrendChartXLabelIndices(31, maxLabels: 2);
      expect(indices, [0, 30]);
    });

    test('14 days with default density', () {
      final indices = pickTrendChartXLabelIndices(14, maxLabels: 5);
      expect(indices.first, 0);
      expect(indices.last, 13);
      expect(indices.length, lessThanOrEqualTo(5));
    });
  });

  group('dailyNetMajor polarity', () {
    test('no activity → 0', () {
      expect(dailyNetMajor('CNY', 0, 0), 0);
    });

    test('income 100 expense 30 → +70', () {
      // CNY minor is fen: 100.00 yuan = 10000 minor
      expect(dailyNetMajor('CNY', 10000, 3000), 70);
    });

    test('income 30 expense 100 → -70', () {
      expect(dailyNetMajor('CNY', 3000, 10000), -70);
    });

    test('self-proof: swapped formula must disagree', () {
      final correct = dailyNetMajor('CNY', 10000, 3000);
      final swapped = fromMinor('CNY', 3000 - 10000); // out - in (wrong)
      expect(correct, isNot(swapped));
      expect(correct, 70);
      expect(swapped, -70);
    });
  });

  group('niceTrendYInterval', () {
    test('snaps to 1/2/5×10^n', () {
      expect(niceTrendYInterval(3), 5);
      expect(niceTrendYInterval(0.3), 0.5);
      expect(niceTrendYInterval(12), 20);
    });
  });

}
