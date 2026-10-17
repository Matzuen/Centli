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

/// Daily net major units: income − expense (locks the calendar trend polarity).
double dailyNetMajor(String base, int incomeMinor, int expenseMinor) {
  return fromMinor(base, incomeMinor - expenseMinor);
}

/// Shared readable area line chart (home overview + calendar daily trend).
class CentliTrendChart extends StatelessWidget {
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
    this.colorBySign = false,
  });

  final String title;
  final List<FlSpot> spots;
  final List<DateTime> dayLabels;
  final String base;
  final bool hide;
  final double height;
  final Color? lineColor;
  final String? sparseMessage;

  /// When true, positive segments use incomeGreen and negative expenseRed.
  final bool colorBySign;

  String _fmtMajor(double major) {
    if (hide) return '****';
    return formatMinor(base, (major * 100).round(), hide: false);
  }

  String _axisLabel(double value) {
    if (hide) return '****';
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
    final color = lineColor ?? CentliTheme.incomeGreen;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget body;
    String? caption;
    final n = spots.length;
    if (n < 2) {
      body = Center(child: Text('\u6682\u65e0\u8d8b\u52bf\u6570\u636e', style: muted));
    } else {
      final ys = spots.map((s) => s.y);
      final yMinRaw = ys.reduce((a, b) => a < b ? a : b);
      final yMaxRaw = ys.reduce((a, b) => a > b ? a : b);
      final end = spots.last.y;
      caption =
          '\u672b\u503c ${_fmtMajor(end)} \u00b7 \u6700\u5927 ${_fmtMajor(yMaxRaw)} \u00b7 \u6700\u5c0f ${_fmtMajor(yMinRaw)}';

      var changeDays = 0;
      for (var i = 1; i < n; i++) {
        if ((spots[i].y - spots[i - 1].y).abs() > 0.001) changeDays++;
      }

      if (changeDays < 2) {
        body = Center(
          child: Text(
            sparseMessage ??
                '\u533a\u95f4\u53d8\u52a8\u8f83\u5c11\uff0c\u7d2f\u8ba1 ${_fmtMajor(end)}',
            style: muted,
            textAlign: TextAlign.center,
          ),
        );
      } else {
        final span = (yMaxRaw - yMinRaw).abs();
        final rawInterval = span < 1e-9 ? 1.0 : span / 2;
        final yInterval = niceTrendYInterval(rawInterval);
        var minY = (yMinRaw / yInterval).floor() * yInterval;
        var maxY = (yMaxRaw / yInterval).ceil() * yInterval;
        if (yMinRaw >= 0) minY = 0;
        if (yMaxRaw <= 0) maxY = 0;
        if ((maxY - minY).abs() < yInterval) {
          minY -= yInterval;
          maxY += yInterval;
        }
        if (minY > 0) minY = 0;
        if (maxY < 0) maxY = 0;
        final useCurve = changeDays >= 4;
        final compactTicks = height < 140;

        body = LayoutBuilder(
          builder: (context, constraints) {
            // Left axis reserves ~40px; estimate how many "M/D" labels fit.
            const leftAxis = 40.0;
            const approxLabelW = 34.0;
            final plotW =
                (constraints.maxWidth - leftAxis).clamp(0.0, 9999.0);
            final maxLabels = (plotW / approxLabelW).floor().clamp(2, 6);
            final labelIndices =
                pickTrendChartXLabelIndices(n, maxLabels: maxLabels).toSet();

            return LineChart(
              LineChartData(
                minX: 0,
                maxX: (n - 1).clamp(0, 9999).toDouble(),
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
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
                        final nearTop =
                            (value - maxY).abs() <= yInterval * 0.15;
                        final nearBot =
                            (value - minY).abs() <= yInterval * 0.15;
                        final nearZero = value.abs() <= yInterval * 0.15;
                        if (compactTicks) {
                          if (!nearTop && !nearBot && !nearZero) {
                            return const SizedBox.shrink();
                          }
                        } else if (!nearTop && !nearBot && !nearZero) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _axisLabel(value),
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
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
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) {
                      return touched.map((t) {
                        final i = t.x.round().clamp(0, n - 1);
                        final d = i < dayLabels.length
                            ? dayLabels[i]
                            : DateTime.fromMillisecondsSinceEpoch(0);
                        final dayLabel = d.millisecondsSinceEpoch == 0
                            ? ''
                            : '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                        final amt = _fmtMajor(t.y);
                        return LineTooltipItem(
                          dayLabel.isEmpty ? amt : '$dayLabel\n$amt',
                          TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  if (!colorBySign)
                    LineChartBarData(
                      spots: spots,
                      isCurved: useCurve,
                      curveSmoothness: 0.2,
                      color: color,
                      barWidth: 2.2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, bar) {
                          if (spot.x == spots.last.x) return true;
                          final i = spot.x.round();
                          if (i <= 0) return spot.y != 0;
                          return (spot.y - spots[i - 1].y).abs() > 0.001;
                        },
                        getDotPainter: (spot, pct, bar, index) =>
                            FlDotCirclePainter(
                          radius: spot.x == spots.last.x ? 3.5 : 2.5,
                          color: color,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.12),
                      ),
                    ),
                  if (colorBySign) ...[
                    LineChartBarData(
                      spots: [
                        for (final s in spots)
                          s.y > 0 || s.y.abs() < 1e-9 ? s : FlSpot.nullSpot,
                      ],
                      isCurved: useCurve,
                      curveSmoothness: 0.2,
                      color: CentliTheme.incomeGreen,
                      barWidth: 2.2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, bar) {
                          if (spot.isNull()) return false;
                          if (spot.x == spots.last.x) return true;
                          final i = spot.x.round();
                          if (i <= 0) return spot.y != 0;
                          return (spot.y - spots[i - 1].y).abs() > 0.001;
                        },
                        getDotPainter: (spot, pct, bar, index) =>
                            FlDotCirclePainter(
                          radius: spot.x == spots.last.x ? 3.5 : 2.5,
                          color: CentliTheme.incomeGreen,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: CentliTheme.incomeGreen.withValues(alpha: 0.12),
                      ),
                    ),
                    LineChartBarData(
                      spots: [
                        for (final s in spots)
                          s.y < 0 || s.y.abs() < 1e-9 ? s : FlSpot.nullSpot,
                      ],
                      isCurved: useCurve,
                      curveSmoothness: 0.2,
                      color: CentliTheme.expenseRed,
                      barWidth: 2.2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, bar) {
                          if (spot.isNull()) return false;
                          if (spot.x == spots.last.x) return true;
                          final i = spot.x.round();
                          if (i <= 0) return spot.y != 0;
                          return (spot.y - spots[i - 1].y).abs() > 0.001;
                        },
                        getDotPainter: (spot, pct, bar, index) =>
                            FlDotCirclePainter(
                          radius: spot.x == spots.last.x ? 3.5 : 2.5,
                          color: CentliTheme.expenseRed,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: CentliTheme.expenseRed.withValues(alpha: 0.12),
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
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption, style: muted),
          ],
          const SizedBox(height: CentliSpacing.item),
          SizedBox(height: height, child: body),
        ],
      ),
    );
  }
}
