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
}
