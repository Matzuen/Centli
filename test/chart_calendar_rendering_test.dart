import 'package:centli/app/theme.dart';
import 'package:centli/core/widgets/centli_trend_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Calendar trend regression suite for the touch popup: hovering used to show
/// TWO days (e.g. 「15 0.00」 above 「16 +633」) because the chart inserted a
/// synthetic zero-crossing point per colour change. The chart now draws only
/// real data points and labels exactly one day.
void main() {
  List<FlSpot> spotsOf(List<double> ys) =>
      [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])];

  List<DateTime> labelsOf(int n) =>
      [for (var i = 0; i < n; i++) DateTime(2026, 10, i + 1)];

  // 10 月：13 号 −1、14 号 −71、16 号 +633、18 号 +700，其余 0。
  final monthYs = <double>[
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 1–12
    -1, -71, 0, 633, 0, 700, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // 13–31
  ];

  Future<void> pumpChart(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: CentliTrendChart(
              title: '每日收支',
              spots: spotsOf(monthYs),
              dayLabels: labelsOf(monthYs.length),
              base: 'CNY',
              hide: false,
              signColored: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('nearestDayIndex picks the column under the pointer',
      (tester) async {
    // bar column k = 40 + k * 10 px (k = index inside the bar).
    double? col(int k) => 40 + k * 10.0;
    final touched = spotsOf([0, -71, 0, 633]);

    expect(nearestDayIndex(touched, null, col), 0, reason: 'unknown pointer');
    expect(nearestDayIndex(touched, 70, col), 3, reason: 'k = 3 (633)');
    expect(nearestDayIndex(touched, 66, col), 3, reason: 'just right of it');
    expect(nearestDayIndex(touched, 64, col), 2, reason: 'just left of it');
    expect(nearestDayIndex(touched, 40, col), 0, reason: 'first column');
    expect(nearestDayIndex(const [], 40, col), -1);
  });

  testWidgets('tooltip labels exactly one day (13th / 14th / 16th)',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpChart(tester);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    final tooltipData = data.lineTouchData.touchTooltipData;
    final state = tester.state<State<CentliTrendChart>>(
      find.byType(CentliTrendChart),
    );
    // ignore: invalid_use_of_protected_member
    final chartState = state as dynamic;

    LineTooltipItem? label(int day) {
      final bar = data.lineBarsData.firstWhere(
        (b) => b.spots.any((s) => s.x == day),
      );
      final touched = <LineBarSpot>[
        LineBarSpot(bar, data.lineBarsData.indexOf(bar), FlSpot(day - 1, 0)),
        LineBarSpot(
          bar,
          data.lineBarsData.indexOf(bar),
          FlSpot(day.toDouble(), monthYs[day]),
        ),
        LineBarSpot(bar, data.lineBarsData.indexOf(bar), FlSpot(day + 1, 0)),
      ];
      chartState.touchX = chartState.dayPixelX(day);
      final items = tooltipData.getTooltipItems(touched);
      expect(items.where((i) => i != null).length, 1);
      return items[1];
    }

    expect(label(12)?.text, '10-13\n¥-1.00');
    expect(label(13)?.text, '10-14\n¥-71.00');
    expect(label(15)?.text, '10-16\n¥633.00');
  });

  testWidgets('every bar holds real days only (no synthetic points)',
      (tester) async {
    await pumpChart(tester);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    final all = [for (final bar in data.lineBarsData) ...bar.spots];
    expect(all.every((s) => s.x == s.x.roundToDouble()), isTrue);
    expect(all.map((s) => s.x).toSet().length, all.length);
    expect(all.map((s) => s.x).toSet().length, monthYs.length);
    final shown = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .lineTouchData
        .getTouchedSpotIndicator(data.lineBarsData.first, const [0]);
    expect(shown.single, isNull, reason: 'no extra touch dots');
  });

  testWidgets('short card still labels every Y stop (not just 2 baselines)',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 120 dp is the net-worth card height: it used to drop every inner tick.
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: SizedBox(
            // Card chrome (title + padding) needs headroom above the plot,
            // otherwise the fixed-height plot overflows the column.
            height: 240,
            child: CentliTrendChart(
              title: '净资产变化',
              height: 120,
              spots: spotsOf(monthYs),
              dayLabels: labelsOf(monthYs.length),
              base: 'CNY',
              hide: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    final axis = trendYAxis([for (final s in data.lineBarsData.first.spots) s.y]);
    // The axis really does offer several stops...
    expect(axis.ticks.length, greaterThanOrEqualTo(3));
    // ...and every one of them renders a label.
    for (final t in axis.ticks) {
      final widget = data.titlesData.leftTitles.sideTitles
          .getTitlesWidget(t, TitleMeta(
            min: axis.minY,
            max: axis.maxY,
            parentAxisSize: 120,
            axisPosition: 0,
            appliedInterval: axis.interval,
            sideTitles: data.titlesData.leftTitles.sideTitles,
            axisSide: AxisSide.left,
            formattedValue: '$t',
            rotationQuarterTurns: 0,
          ));
      expect(widget, isNot(isA<SizedBox>()), reason: 'tick $t has no label');
    }
  });

  testWidgets('tooltip is clamped inside the chart (last day not clipped)',
      (tester) async {
    await pumpChart(tester);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final tip = chart.data.lineTouchData.touchTooltipData;
    // Without these the 「10-18 ¥591.11」 bubble runs past the card edge.
    expect(tip.fitInsideHorizontally, isTrue);
    expect(tip.fitInsideVertically, isTrue);
    expect(tip.tooltipMargin, greaterThan(0));
  });

  testWidgets('line is smooth and draws no vertex dots', (tester) async {
    await pumpChart(tester);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bars = chart.data.lineBarsData;
    expect(bars, isNotEmpty);
    for (final bar in bars) {
      // Curved, with over-shooting disabled so the curve stays in range.
      expect(bar.isCurved, isTrue);
      expect(bar.preventCurveOverShooting, isTrue);
      expect(bar.curveSmoothness, greaterThanOrEqualTo(0.3));
      // No dots at the data points.
      expect(bar.dotData.show, isFalse);
    }
  });

  testWidgets('chart card hugs its content (no dead band)', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Put the chart in a scrolling column, like the home page does: the card
    // must size to its content instead of filling the viewport.
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CentliTrendChart(
              title: '净资产变化',
              spots: spotsOf(monthYs),
              dayLabels: labelsOf(monthYs.length),
              base: 'CNY',
              hide: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final card = tester.getRect(find.byType(CentliSoftCard).first);
    final plot = tester.getRect(find.byType(LineChart));
    // 16 pad + title + caption + 8 gap + plotHeight + 16 pad ≈ 216 for 120dp.
    expect(card.height, lessThan(260), reason: 'card should hug content');
    expect(card.bottom - plot.bottom, lessThanOrEqualTo(20),
        reason: 'blank band under the plot');
  });

  testWidgets('renders without layout exceptions', (tester) async {
    await pumpChart(tester);
    expect(find.text('每日收支'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
