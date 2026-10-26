import 'package:flutter/material.dart';

/// 预算进度色阶：小于 70% 冷静色；70% 到 100% 黄到红渐变；大于等于 100% 超支红。
abstract final class BudgetProgressStyle {
  /// 开始偏黄的阈值。
  static const double warnStart = 0.70;

  /// 发本地通知的阈值（与色阶独立，避免一黄就推送）。
  static const double notifyAt = 0.80;

  /// 黄档起点（约 70%）。
  static const Color yellow = Color(0xFFF9A825);

  /// 接近用尽时的橙红（约 100% 前）。
  static const Color orangeRed = Color(0xFFE64A19);

  static Color barColor(ColorScheme scheme, double ratio) {
    if (ratio >= 1.0) return scheme.error;
    if (ratio < warnStart) return scheme.primary;
    final t = ((ratio - warnStart) / (1.0 - warnStart)).clamp(0.0, 1.0);
    return Color.lerp(yellow, orangeRed, t)!;
  }

  /// 剩余/超支文案色：与进度条同语义。
  static Color labelColor(
    ColorScheme scheme,
    double ratio, {
    required bool over,
  }) {
    if (over || ratio >= 1.0) return scheme.error;
    if (ratio < warnStart) return scheme.onSurface;
    return barColor(scheme, ratio);
  }
}
