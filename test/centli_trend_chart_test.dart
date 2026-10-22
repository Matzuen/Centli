import 'package:centli/core/utils/money.dart';
import 'package:centli/core/widgets/centli_trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
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

  group('cumulativeNetMajor (月份累计收支单线)', () {
    test('idle days keep the running total (no drop to 0)', () {
      // 18 号: 收入 633 / 支出 71 → +562；19~31 号无流水。
      final daily = <double>[-71, 0, 0, 0, 0, 0, 633, 0, 0];
      final cum = cumulativeNetMajor(daily);
      expect(cum.sublist(7), everyElement(562.0));
      expect(cum.last, 562.0);
    });

    test('负数累计只跨过一次零点', () {
      final cum = cumulativeNetMajor(<double>[-10, -5, 20, 0]);
      expect(cum, [-10.0, -15.0, 5.0, 5.0]);
    });
  });

  group('splitTrendBySign (一条线、正负分段着色)', () {
    List<FlSpot> netSpots(List<double> ys) => [
          for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i]),
        ];

    test('只用真实数据点：不会凭空多出"15 号 0.00"这样的点', () {
      // 截图里的 bug：插入的过零点被当成额外数据点→悬浮时多出一行。
      final ys = [0.0, 0.0, 0.0, -1.0, -71.0, 0.0, 633.0, 0.0, 0.0];
      final segs = splitTrendBySign(netSpots(ys));
      final xs = [for (final seg in segs) ...seg.spots.map((p) => p.x)];
      // 每个真实日期恰好出现一次，没有任何小数 x。
      expect(xs.toSet(), {for (var i = 0; i < ys.length; i++) i.toDouble()});
      expect(xs.length, ys.length);
    });

    test('零值并入相邻符号：0,0,-71 只是一条负线', () {
      final ys = [0.0, 0.0, -71.0, -71.0];
      final runs = trendSignRuns(ys);
      expect(runs.length, 1);
      expect(runs.single.positive, isFalse);
      expect(runs.single.start, 0);
      expect(runs.single.end, 3);
      final segs = splitTrendBySign(netSpots(ys));
      expect(segs.length, 1);
      expect(segs.single.spots.map((p) => p.y), ys);
    });

    test('过零在交叉当天换色，13/14 红、16 绿、15 与 0 同段', () {
      final ys = [-1.0, -71.0, 0.0, 633.0];
      final segs = splitTrendBySign(netSpots(ys));
      expect(segs.length, 2);
      // 负数段：13 号、14 号（15 号的 0 归入后面的正段，即从 0 涨到 633 的那段）。
      expect(segs[0].positive, isFalse);
      expect(segs[0].spots.map((p) => p.x), [0, 1]);
      // 正数段：15 号的 0 → 16 号 633（15 号落在轴上，涨起来的是绿线）。
      expect(segs[1].positive, isTrue);
      expect(segs[1].spots.map((p) => p.x), [2, 3]);
      expect(segs[1].spots.first.y, 0);
      expect(segs[1].spots.last.y, 633);
    });

    test('单点正段也能画出来（至少两个点才渲染成线的情况）', () {
      final segs = splitTrendBySign(netSpots(<double>[-5, 8, -5]));
      // 8 号单独一天为正：该段只有一个点，但仍是真实数据点。
      expect(segs.map((s) => s.positive), [false, true, false]);
      expect(segs[1].spots.length, 1);
    });

    test('收尾的零值保留原符号（不会凭空多出一条零线）', () {
      final segs = splitTrendBySign(netSpots(<double>[5, 3, 0, 0]));
      expect(segs.length, 1);
      expect(segs.single.positive, isTrue);
      expect(segs.single.spots.length, 4);
    });

    test('全为 0 / 单一符号只有一个色段', () {
      expect(splitTrendBySign(netSpots(<double>[0, 0, 0])).length, 1);
      expect(splitTrendBySign(netSpots(<double>[5, 8, 3])).single.positive,
          isTrue);
    });
  });

  group('trendTooltipText（悬浮只显示一条）', () {
    final labels = <DateTime>[
      for (var d = 1; d <= 31; d++) DateTime(2026, 10, d),
    ];

    test('日期 + 金额两行', () {
      expect(trendTooltipText(labels, 15, '¥633.00'), '10-16\n¥633.00');
      expect(trendTooltipText(labels, 14, '¥0.00'), '10-15\n¥0.00');
      expect(trendTooltipText(labels, 12, '-¥1.00'), '10-13\n-¥1.00');
    });
  });

  group('niceTrendYInterval', () {
    test('snaps to 1/2/5×10^n', () {
      expect(niceTrendYInterval(3), 5);
      expect(niceTrendYInterval(0.3), 0.5);
      expect(niceTrendYInterval(12), 20);
    });
  });

  group('formatTrendYAxisLabel', () {
    test('below 1000: hundreds integers; k/m: at most 1 decimal', () {
      expect(
        formatTrendYAxisLabel(500, interval: 100, axisMaxAbs: 500),
        '500',
      );
      expect(
        formatTrendYAxisLabel(800, interval: 100, axisMaxAbs: 800),
        '800',
      );
      expect(
        formatTrendYAxisLabel(5000, interval: 1000, axisMaxAbs: 5000),
        '5k',
      );
      expect(
        formatTrendYAxisLabel(10100, interval: 100, axisMaxAbs: 10200),
        '10.1k',
      );
      expect(
        formatTrendYAxisLabel(20000, interval: 10000, axisMaxAbs: 20000),
        '20k',
      );
      expect(
        formatTrendYAxisLabel(1500000, interval: 500000, axisMaxAbs: 1500000),
        '1.5m',
      );
      expect(
        formatTrendYAxisLabel(2000000, interval: 1000000, axisMaxAbs: 2000000),
        '2m',
      );
      expect(
        formatTrendYAxisLabel(1200000, interval: 100000, axisMaxAbs: 1500000),
        '1.2m',
      );
    });

    test('narrow swing around 10k keeps unique ≤1-decimal k labels', () {
      final axis = trendYAxis([10000.0, 10000.0, 9973.67, 9973.67]);
      expect(axis.interval, greaterThanOrEqualTo(100));
      final maxAbs = axis.ticks
          .map((t) => t.abs())
          .fold<double>(0, (a, b) => a > b ? a : b);
      final labels = [
        for (final t in axis.ticks)
          formatTrendYAxisLabel(
            t,
            interval: axis.interval,
            axisMaxAbs: maxAbs,
          ),
      ];
      expect(labels.toSet().length, labels.length, reason: labels.join(','));
      expect(
        labels.every((s) => s == '0' || s.endsWith('k')),
        isTrue,
        reason: labels.join(','),
      );
      for (final s in labels) {
        if (!s.endsWith('k')) continue;
        final body = s.substring(0, s.length - 1);
        final dot = body.indexOf('.');
        if (dot >= 0) {
          expect(body.length - dot - 1, 1, reason: s);
        }
      }
    });

    test('straddle 10k with min interval keeps unique 1-decimal k', () {
      // interval < 100 会在一位小数下撞号；轴侧保证 ≥100。
      const interval = 100.0;
      const ticks = [9900.0, 10000.0, 10100.0, 10200.0, 10300.0, 10400.0];
      const maxAbs = 10400.0;
      final labels = [
        for (final t in ticks)
          formatTrendYAxisLabel(t, interval: interval, axisMaxAbs: maxAbs),
      ];
      expect(labels.every((s) => s.endsWith('k')), isTrue, reason: labels.join(','));
      expect(labels.toSet().length, labels.length, reason: labels.join(','));
      expect(labels.first, '9.9k');
      expect(labels[1], '10k');
      expect(labels.last, '10.4k');
    });

    test('minTrendYInterval matches scale', () {
      expect(minTrendYInterval(500), 100);
      expect(minTrendYInterval(5000), 100);
      expect(minTrendYInterval(1500000), 100000);
    });
  });



  group('trendYAxis (4 to 6 tick marks)', () {
    test('covers the data with at most 6 labels', () {
      // 10/01…10/16 net-worth path from the reference screenshot.
      final ys = [1000.0, 1200.0, 900.0, 1500.0, 2300.0, 1900.0, 2600.0];
      final axis = trendYAxis(ys);
      expect(axis.ticks.length, lessThanOrEqualTo(6));
      expect(axis.ticks.length, greaterThanOrEqualTo(4));
      expect(axis.minY, lessThanOrEqualTo(ys.reduce((a, b) => a < b ? a : b)));
      expect(axis.maxY, greaterThanOrEqualTo(ys.reduce((a, b) => a > b ? a : b)));
      // Evenly spaced.
      for (var i = 1; i < axis.ticks.length; i++) {
        expect(
          axis.ticks[i] - axis.ticks[i - 1],
          closeTo(axis.interval, 1e-6),
        );
      }
    });

    test('a negative range keeps a signed zero-crossing stop', () {
      final axis = trendYAxis([6000, 2000, -1500, -4000]);
      expect(axis.minY, lessThanOrEqualTo(-4000));
      expect(axis.maxY, greaterThanOrEqualTo(6000));
      expect(axis.ticks.length, lessThanOrEqualTo(6));
      expect(axis.ticks.length, greaterThanOrEqualTo(4));
    });

    test('reference screenshot: 6000…-4000 stays within 6 stops', () {
      // 10/01…10/16 net-worth path, roughly 6000 down to -4000.
      final axis = trendYAxis([6000, 4200, 2500, 800, -900, -2400, -4000]);
      expect(axis.ticks.length, inInclusiveRange(4, 6));
      // Ticks run bottom → top and must cover the data.
      expect(axis.ticks.first, lessThanOrEqualTo(-4000));
      expect(axis.ticks.last, greaterThanOrEqualTo(6000));
      // Even stops.
      for (var i = 1; i < axis.ticks.length; i++) {
        expect(axis.ticks[i] - axis.ticks[i - 1], closeTo(axis.interval, 1e-6));
      }
    });

    test('flat / single values still produce a usable axis', () {
      expect(trendYAxis(const []).ticks.length, greaterThanOrEqualTo(2));
      final flat = trendYAxis([42, 42, 42]);
      expect(flat.minY, lessThan(42));
      expect(flat.maxY, greaterThan(42));
    });

    test('default axis stays within 4 to 6 stops', () {
      final axis = trendYAxis([1000, 500, 0, -500]);
      expect(axis.ticks.length, inInclusiveRange(4, 6));
    });

    test('produces 4 to 6 evenly spaced stops covering the data', () {
      final datasets = <String, List<double>>{
        'screenshot': [
          -71.89, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 591.11,
        ],
        'wide': [6000, 4200, 2500, 800, -900, -2400, -4000],
        'edge500': [1000, 500, 0, -500],
        'flat': [42, 42, 42],
        'positive': [100, 200, 300],
      };
      for (final e in datasets.entries) {
        final a = trendYAxis(e.value);
        expect(a.ticks.length, inInclusiveRange(4, 6), reason: e.key);
        // Evenly spaced.
        for (var i = 1; i < a.ticks.length; i++) {
          expect(a.ticks[i] - a.ticks[i - 1], closeTo(a.interval, 1e-6),
              reason: e.key);
        }
        // Covers the data.
        expect(a.ticks.first,
            lessThanOrEqualTo(e.value.reduce((x, y) => x < y ? x : y)),
            reason: e.key);
        expect(a.ticks.last,
            greaterThanOrEqualTo(e.value.reduce((x, y) => x > y ? x : y)),
            reason: e.key);
      }
    });

    test('tickCount is honoured', () {
      final axis = trendYAxis([0, 100], tickCount: 3);
      expect(axis.ticks.length, lessThanOrEqualTo(3));
    });
  });
}
