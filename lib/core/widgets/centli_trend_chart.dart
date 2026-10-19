import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/money.dart';
import '../../app/theme.dart';

/// Pick bottom X-axis label indices for [CentliTrendChart].
///
/// Always keeps first and last when [n] >= 2, spaces the rest evenly, then
/// drops interior ticks that would sit closer than ~55% of the ideal step so
/// the last two dates never stack (e.g. 10/29 on top of 10/31).
@visibleForTesting
List<int> pickTrendChartXLabelIndices(int n, {int maxLabels = 5}) {
  if (n <= 0) return const [];
  if (n == 1) return const [0];
  final capped = maxLabels.clamp(2, n);
  if (n <= capped) return List<int>.generate(n, (i) => i);

  final raw = <int>[];
  for (var s = 0; s < capped; s++) {
    raw.add(((n - 1) * s / (capped - 1)).round());
  }
  final unique = <int>[];
  for (final i in raw) {
    if (unique.isEmpty || unique.last != i) unique.add(i);
  }

  final minGap = ((n - 1) / (capped - 1) * 0.55).ceil().clamp(1, n - 1);
  final result = <int>[unique.first];
  for (var k = 1; k < unique.length - 1; k++) {
    if (unique[k] - result.last >= minGap) {
      result.add(unique[k]);
    }
  }
  final last = unique.last;
  if (last - result.last < minGap && result.length > 1) {
    result.removeLast();
  }
  if (result.last != last) result.add(last);
  return result;
}


/// Nice Y-axis step: smallest 1/2/5×10^n that is >= [raw].
@visibleForTesting
double niceTrendYInterval(double raw) {
  if (raw <= 0 || raw.isNaN || raw.isInfinite) return 1;
  final exp = (math.log(raw) / math.ln10).floor();
  final pow10 = math.pow(10, exp).toDouble();
  final frac = raw / pow10;
  final niceFrac = frac <= 1
      ? 1.0
      : frac <= 2
          ? 2.0
          : frac <= 5
              ? 5.0
              : 10.0;
  return niceFrac * pow10;
}

/// The [ticks] labels shown on the chart's Y axis.
///
/// The user reads the axis as fixed even stops (e.g. `6000 / 4000 / 2000 / 0 /
/// -2000 / -4000`), so the interval is derived from (max − min) / (ticks − 1)
/// rather than "as few grid lines as possible".
class TrendYAxis {
  const TrendYAxis({
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.ticks,
  });

  final double minY;
  final double maxY;
  final double interval;
  final List<double> ticks;
}

/// Axis for [ys]. Default is 6 labels, and the result stays in 4–6.
@visibleForTesting
TrendYAxis trendYAxis(Iterable<double> ys, {int tickCount = 6}) {
  final list = ys.toList();
  final maxTicks = tickCount < 2 ? 2 : tickCount;
  if (list.isEmpty) {
    return TrendYAxis(minY: 0, maxY: 1, interval: 1, ticks: const [0, 1]);
  }
  final yMinRaw = list.reduce((a, b) => a < b ? a : b);
  final yMaxRaw = list.reduce((a, b) => a > b ? a : b);
  final span = (yMaxRaw - yMinRaw).abs();

  // 4~6 条：先试上限，步长把轴拉得过宽时再减少。
  TrendYAxis? best;
  var bestScore = double.infinity;
  final lowest = maxTicks >= 6 ? 4 : 2;
  for (var want = maxTicks; want >= lowest; want--) {
    final axis = _axisFor(list, yMinRaw, yMaxRaw, span, want);
    if (axis == null) continue;
    final axisSpan = axis.maxY - axis.minY;
    // 轴比数据宽出的比例：超过 ~2.5 倍说明刻度选得太粗。
    final padding = span < 1e-9 ? 1.0 : axisSpan / span;
    final score = padding + (maxTicks - want) * 0.35;
    if (score < bestScore) {
      bestScore = score;
      best = axis;
    }
  }
  return best ?? _axisFor(list, yMinRaw, yMaxRaw, span, 2)!;
}

/// 生成恰好 [want] 条等距刻度的轴；无法构造时返回 null。
TrendYAxis? _axisFor(
  List<double> ys,
  double yMinRaw,
  double yMaxRaw,
  double span,
  int want,
) {
  final rawStep = span < 1e-9 ? 0.0 : span / (want - 1);
  var interval = rawStep > 0 ? _niceStep(rawStep) : 1.0;
  if (interval <= 0) interval = 1.0;

  // 数据全部相同（水平线）时，围绕它上下各开一格，否则线会贴在轴线上。
  if (span < 1e-9) {
    var t = (yMinRaw / interval).floor() * interval;
    if (t >= yMinRaw) t -= interval;
    return TrendYAxis(
      minY: t,
      maxY: t + interval * (want - 1),
      interval: interval,
      ticks: [for (var i = 0; i < want; i++) t + interval * i],
    );
  }
  // 以 0 为锚点铺格，让 0 尽量落在刻度上。
  var minY = (yMinRaw / interval).floor() * interval;
  // 刻度必须正好 [want] 条且覆盖数据。
  var ticks = [for (var i = 0; i < want; i++) minY + interval * i];
  if (ticks.last < yMaxRaw - 1e-9) {
    // 上界不够：整体上移，或加粗步长。
    minY = (yMaxRaw / interval).floor() * interval - interval * (want - 1);
    ticks = [
      for (var i = 0; i < want; i++)
        minY + interval * i,
    ];
    if (ticks.first > yMinRaw + 1e-9) {
      // 仍然装不下：加粗一档步长再试一次。
      interval = _niceStep(interval * 1.01);
      minY = (yMinRaw / interval).floor() * interval;
      ticks = [for (var i = 0; i < want; i++) minY + interval * i];
      if (ticks.last < yMaxRaw - 1e-9) {
        minY = (yMaxRaw / interval).floor() * interval - interval * (want - 1);
        ticks = [for (var i = 0; i < want; i++) minY + interval * i];
        if (ticks.first > yMinRaw + 1e-9) return null;
      }
    }
  }
  // 抹平浮点尾差（0.6000000000000001 → 0.6），标签才不会出现长小数。
  double clean(double v) => (v * 1e6).roundToDouble() / 1e6;
  final cleaned = [for (final t in ticks) clean(t)];
  return TrendYAxis(
    minY: cleaned.first,
    maxY: cleaned.last,
    interval: clean(interval),
    ticks: cleaned,
  );
}

/// 向上取整到 1 / 2 / 2.5 / 5 x 10^n 的「好看步长」。
double _niceStep(double raw) {
  if (raw <= 0) return 0;
  final e = (math.log(raw) / math.ln10).floor();
  for (var k = e - 1; k <= e + 2; k++) {
    final scale = math.pow(10, k).toDouble();
    for (final frac in const [1.0, 2.0, 2.5, 5.0]) {
      final step = frac * scale;
      if (step >= raw - 1e-9) return step;
    }
  }
  return raw;
}

/// Daily net major units: income − expense (locks the calendar trend polarity).
double dailyNetMajor(String base, int incomeMinor, int expenseMinor) {
  return fromMinor(base, incomeMinor - expenseMinor);
}

/// Running total of [dailyNet] from day 0 to day i, in major units.
///
/// One calendar day without activity repeats the previous value (flat step)
/// instead of collapsing to 0, which is what made the old chart look like a
/// second "zero line" between days with a bill.
List<double> cumulativeNetMajor(List<double> dailyNet) {
  final out = <double>[];
  var running = 0.0;
  for (final d in dailyNet) {
    running += d;
    out.add(running);
  }
  return out;
}

double _signOf(double y) => y > 1e-9 ? 1 : (y < -1e-9 ? -1 : 0);

/// Indices (inclusive) of maximal runs that share a sign.
///
/// Start from every non-zero point, then absorb the zero points around it:
/// a zero run flips to the sign the value takes *after* it, and a run that
/// ends on zeros keeps the sign it came from. So a month that goes
/// 0, 0, −71 is ONE negative run, never a "zero line" plus a "negative line".
@visibleForTesting
List<({int start, int end, bool positive})> trendSignRuns(
  List<double> ys,
) {
  final n = ys.length;
  if (n == 0) return const [];
  final out = <({int start, int end, bool positive})>[];
  var i = 0;
  while (i < n) {
    final sign = _signOf(ys[i]);
    if (sign == 0) {
      i++;
      continue;
    }
    var end = i;
    while (end + 1 < n && _signOf(ys[end + 1]) == sign) {
      end++;
    }
    out.add((start: i, end: end, positive: sign > 0));
    i = end + 1;
  }
  final runs = (out.isEmpty ? <({int start, int end, bool positive})>[] : out);
  if (runs.isEmpty) {
    return [(start: 0, end: n - 1, positive: true)];
  }
  final first = runs.first;
  if (first.start > 0) {
    runs[0] = (start: 0, end: first.end, positive: first.positive);
  }
  final last = runs.last;
  if (last.end < n - 1) {
    runs[runs.length - 1] =
        (start: last.start, end: n - 1, positive: last.positive);
  }
  // Zero gap between two runs joins the later run: extend each run to the
  // start of the next one.
  for (var k = 0; k + 1 < runs.length; k++) {
    final cur = runs[k];
    final next = runs[k + 1];
    if (cur.end + 1 < next.start) {
      runs[k + 1] = (start: cur.end + 1, end: next.end, positive: next.positive);
    }
  }
  return runs;
}

/// Sign segments for two-colour rendering, built from **real data points only**.
///
/// Synthetic zero-crossing points are deliberately NOT inserted here:
/// fl_chart builds one tooltip entry per touched spot, so those extra points
/// showed up as additional lines in the popup (e.g. 「15 0.00」 above
/// 「16 +633」). Every real point belongs to exactly one bar, so the tooltip
/// always shows exactly one day.
@visibleForTesting
List<({bool positive, List<FlSpot> spots})> splitTrendBySign(
  List<FlSpot> spots,
) {
  if (spots.isEmpty) return const [];
  final segments = <({bool positive, List<FlSpot> spots})>[];
  for (final run in trendSignRuns([for (final s in spots) s.y])) {
    segments.add((
      positive: run.positive,
      spots: [for (var i = run.start; i <= run.end; i++) spots[i]],
    ));
  }
  return segments;
}

/// Shared readable area line chart (home overview + calendar daily trend).
class CentliTrendChart extends StatefulWidget {
  const CentliTrendChart({
    super.key,
    required this.title,
    required this.spots,
    required this.dayLabels,
    required this.base,
    required this.hide,
    this.height = 120,
    this.lineColor,
    this.sparseMessage,
    this.signColored = false,
    this.trailing,
  });

  final String title;
  final List<FlSpot> spots;
  final List<DateTime> dayLabels;
  final String base;
  final bool hide;
  final double height;
  final Color? lineColor;
  final String? sparseMessage;

  /// When true the single line is split visually by sign: segments above zero
  /// are drawn in incomeGreen, segments below zero in expenseRed. Days at
  /// exactly 0 join the neighbouring run (real data points only, so the touch
  /// tooltip never reports more than one day).
  final bool signColored;

  /// Optional header action widgets (e.g. 「列表 / 饼图」 buttons).
  final Widget? trailing;

  @override
  State<CentliTrendChart> createState() => _CentliTrendChartState();
}

String _fmtMajorOf(String base, bool hide, double major) {
  if (hide) return '****';
  return formatMinor(base, (major * 100).round(), hide: false);
}

/// Tooltip text for one day: 「MM-DD\n金额」.
@visibleForTesting
String trendTooltipText(List<DateTime> dayLabels, double x, String amount) {
  final i = x.round();
  final d = i >= 0 && i < dayLabels.length
      ? dayLabels[i]
      : DateTime.fromMillisecondsSinceEpoch(0);
  if (d.millisecondsSinceEpoch == 0) return amount;
  return '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}\n$amount';
}

/// Width reserved for the Y axis (kept in sync with [SideTitles.reservedSize]).
const double leftAxisWidth = 40;

/// Index (into [touched]) of the day to label in a touch tooltip: the day
/// whose pixel column (via [dayPixelX]) is nearest [touchX], or the first
/// spot when the pointer position is unknown.
@visibleForTesting
int nearestDayIndex(
  List<FlSpot> touched,
  double? touchX,
  double? Function(int dayIndex) dayPixelX,
) {
  if (touched.isEmpty) return -1;
  if (touchX == null) return 0;
  var nearest = 0;
  var best = double.infinity;
  for (var k = 0; k < touched.length; k++) {
    final px = dayPixelX(touched[k].x.round());
    if (px == null) continue;
    final d = (px - touchX).abs();
    if (d < best) {
      best = d;
      nearest = k;
    }
  }
  return nearest;
}

class _CentliTrendChartState extends State<CentliTrendChart> {
  double get minX => 0;

  /// Pointer x (chart-local CSS px) of the last hover/drag, used to pick the
  /// day nearest the cursor when several colour segments are under it.
  double? touchX;

  /// Day index under the pointer while hovering (null when not hovering).
  int? hoveredDay;

  /// Plot area (scrollable-axis start and daily step) recorded while building,
  /// so a touched spot index can be turned into a pixel column.
  double? _plotStartX;
  double? _dayStepX;

  /// Day index whose column is nearest pixel [px] (null before first layout).
  int? _dayAtPixels(double px) {
    final spots = widget.spots;
    if (spots.isEmpty) return null;
    final k = nearestDayIndex(spots, px, dayPixelX);
    return k < 0 ? null : spots[k].x.round();
  }

  /// Pixel x of [dayIndex] in chart space, or null before the first layout.
  @visibleForTesting
  double? dayPixelX(int dayIndex) {
    final start = _plotStartX;
    final step = _dayStepX;
    if (start == null || step == null) return null;
    return leftAxisWidth + (dayIndex - minX) * step;
  }

  String _fmtMajor(double major) => _fmtMajorOf(widget.base, widget.hide, major);

  String _axisLabel(double value) {
    if (widget.hide) return '****';
    final abs = value.abs();
    if (abs >= 10000) {
      return '${(value / 10000).toStringAsFixed(abs >= 100000 ? 0 : 1)}\u4e07';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}\u5343';
    }
    if (abs < 1e-9) return '0';
    if (abs >= 10) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.lineColor ?? CentliTheme.incomeGreen;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget body;
    final spots = widget.spots;
    final dayLabels = widget.dayLabels;
    final signColored = widget.signColored;
    final n = spots.length;
    if (n < 2) {
      body = Center(child: Text('\u6682\u65e0\u8d8b\u52bf\u6570\u636e', style: muted));
    } else {
      final ys = spots.map((s) => s.y);

      var changeDays = 0;
      for (var i = 1; i < n; i++) {
        if ((spots[i].y - spots[i - 1].y).abs() > 0.001) changeDays++;
      }

      // 只要区间里有过变动就画线。原先要至少两个转折才出图，
      // 同一天多笔记账会被收成一段，图上什么都没有。
      if (changeDays < 1) {
        // Cumulative chart: a flat final value means net in/out cancelled out.
        final fallback = signColored
            ? '\u672c\u671f\u6536\u652f\u5f52\u96f6'
            : '\u533a\u95f4\u53d8\u52a8\u8f83\u5c11\uff0c\u7d2f\u8ba1 ${_fmtMajor(spots.last.y)}';
        body = Center(
          child: Text(
            widget.sparseMessage ?? fallback,
            style: muted,
            textAlign: TextAlign.center,
          ),
        );
      } else {
        final axis = trendYAxis(ys);
        final yInterval = axis.interval;
        final minY = axis.minY;
        final maxY = axis.maxY;
        // 平滑曲线：只要有两个以上的点就画曲线（原来要点数够多才画，
        // 少量点会变成折线，看起来“有棱角”）。
        final useCurve = n >= 2;
        // 0.35 比 fl_chart 默认 0.2 更圆润；配合 preventCurveOverShooting，
        // 曲线不会冲到数据范围之外。
        const curveSmoothness = 0.35;

        body = LayoutBuilder(
          builder: (context, constraints) {
            // Left axis reserves ~40px; estimate how many "M/D" labels fit.
            const leftAxis = leftAxisWidth;
            const approxLabelW = 34.0;
            final plotW =
                (constraints.maxWidth - leftAxis).clamp(0.0, 9999.0);
            final maxLabels = (plotW / approxLabelW).floor().clamp(2, 6);
            final labelIndices =
                pickTrendChartXLabelIndices(n, maxLabels: maxLabels).toSet();

            final maxXValue = (n - 1).clamp(0, 9999).toDouble();
            _plotStartX = leftAxis;
            _dayStepX = maxXValue <= 0
                ? 0
                : (constraints.maxWidth - leftAxis - 0) / maxXValue;
            return LineChart(
              LineChartData(
                minX: 0,
                maxX: maxXValue,
                minY: minY,
                maxY: maxY,
                // 紧贴容器：fl_chart 默认会在绘图区外留白，看起来像空白卡片。
                clipData: const FlClipData.none(),

                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (v) {
                    final isZero = v.abs() < yInterval * 0.01;
                    return FlLine(
                      color: isZero
                          ? scheme.outline.withValues(alpha: 0.85)
                          : scheme.outlineVariant.withValues(alpha: 0.45),
                      strokeWidth: isZero ? 1.6 : 1,
                    );
                  },
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: scheme.outline.withValues(alpha: 0.9),
                      strokeWidth: 1.6,
                    ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        if (value < minY - 0.01 || value > maxY + 0.01) {
                          return const SizedBox.shrink();
                        }
                        // Every stop gets a label. Previously short cards
                        // dropped the inner stops, so the axis looked like it
                        // only had a top and a bottom baseline.
                        return Align(
                          alignment: (value - maxY).abs() <= yInterval * 0.01
                              ? Alignment.bottomRight
                              : ((value - minY).abs() <= yInterval * 0.01
                                  ? Alignment.topRight
                                  : Alignment.centerRight),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _axisLabel(value),
                              style: Theme.of(context).textTheme.labelSmall,
                              maxLines: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= n) return const SizedBox.shrink();
                        if (!labelIndices.contains(i)) {
                          return const SizedBox.shrink();
                        }
                        if (i >= dayLabels.length) {
                          return const SizedBox.shrink();
                        }
                        final d = dayLabels[i];
                        if (d.millisecondsSinceEpoch == 0) {
                          return const SizedBox.shrink();
                        }
                        final isFirst = i == 0;
                        final isLast = i == n - 1;
                        return SideTitleWidget(
                          meta: meta,
                          space: 4,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            distanceFromEdge: 0,
                          ),
                          child: Text(
                            '${d.month}/${d.day}',
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            textAlign: isFirst
                                ? TextAlign.left
                                : (isLast
                                    ? TextAlign.right
                                    : TextAlign.center),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  // Sign segments are separate bars, so fl_chart reports one
                  // touched spot per bar; show only the one nearest the cursor.
                  touchTooltipData: LineTouchTooltipData(
                    // 靠近图表边缘时把提示框拉回可视区（否则最后一天的
                    // 「10-18 ¥591.11」会被卡片右边缘裁掉一半）。
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipMargin: 6,
                    maxContentWidth: 160,
                    getTooltipItems: (touched) {
                      if (touched.isEmpty) return const [];
                      // Pick the day whose pixel column is nearest the
                      // pointer (a bar may not contain the touched x when the
                      // press drifts between colour segments).
                      final nearestIndex =
                          nearestDayIndex(touched, touchX, dayPixelX);
                      return [
                        for (var k = 0; k < touched.length; k++)
                          k == nearestIndex
                              ? LineTooltipItem(
                                  trendTooltipText(
                                    dayLabels,
                                    touched[k].x,
                                    _fmtMajor(touched[k].y),
                                  ),
                                  TextStyle(
                                    color: scheme.onInverseSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                      ];
                    },
                  ),
                  // No touch indicators: overlapping dots from neighbouring
                  // colour segments looked like a second data series.
                  getTouchedSpotIndicator: (bar, indexes) => [
                    // 只留竖直虚线，不画圆点。
                    for (final index in indexes)
                      index >= 0 &&
                              index < bar.spots.length &&
                              hoveredDay != null &&
                              bar.spots[index].x.round() == hoveredDay
                          ? TouchedSpotIndicatorData(
                              FlLine(
                                color: scheme.outline.withValues(alpha: 0.6),
                                strokeWidth: 1,
                                dashArray: [4, 3],
                              ),
                              const FlDotData(show: false),
                            )
                          : null,
                  ],
                  touchCallback: (event, response) {
                    if (event is FlPointerHoverEvent) {
                      // Hover only: the position is needed to pick the nearest
                      // day. Taps / drags skip setState so a touch does not
                      // rebuild (and reset tooltip flicker) mid-gesture.
                      if (mounted) {
                        final day = _dayAtPixels(event.localPosition.dx);
                        setState(() {
                          touchX = event.localPosition.dx;
                          hoveredDay = day;
                        });
                      }
                    }
                  },
                ),
                lineBarsData: [
                  if (!signColored)
                    LineChartBarData(
                      spots: spots,
                      isCurved: useCurve,
                      curveSmoothness: curveSmoothness,
                      preventCurveOverShooting: true,
                      color: color,
                      barWidth: 2.2,
                      isStrokeCapRound: true,
                      // 折线不打点：圆点会把曲线打断，看着碎。
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.12),
                      ),
                    ),
                  // One logical series, coloured by sign. Neighbouring same-sign
                  // points stay connected (no null gaps → no stray second
                  // line), and a crossing point is inserted at y = 0.
                  if (signColored) ...[
                    for (final seg in splitTrendBySign(spots))
                      LineChartBarData(
                        spots: seg.spots,
                        isCurved: useCurve,
                        curveSmoothness: curveSmoothness,
                        preventCurveOverShooting: true,
                        color: seg.positive
                            ? CentliTheme.incomeGreen
                            : CentliTheme.expenseRed,
                        barWidth: 2.2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: (seg.positive
                                  ? CentliTheme.incomeGreen
                                  : CentliTheme.expenseRed)
                              .withValues(alpha: 0.12),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      }
    }

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (widget.trailing != null) ...[
                const SizedBox(width: CentliSpacing.dense),
                widget.trailing!,
              ],
            ],
          ),
          const SizedBox(height: CentliSpacing.item),
          // 绘图区吃掉剩余高度，避免上下各留一块空白。
          SizedBox(height: widget.height, child: body),
        ],
      ),
    );
  }
}
