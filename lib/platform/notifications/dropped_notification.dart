import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A notification skipped by native package/enable gates (G28).
class DroppedNotification {
  const DroppedNotification({
    required this.pkg,
    required this.title,
    required this.whenMs,
    required this.reason,
  });

  final String pkg;
  final String title;
  final int whenMs;

  /// `not_watched` | `disabled` | `blank` | `weak`
  final String reason;

  factory DroppedNotification.fromMap(Map<Object?, Object?> map) {
    final title = (map['title']?.toString() ?? '').trim();
    return DroppedNotification(
      pkg: map['pkg']?.toString() ?? '',
      title: title.length > 80 ? title.substring(0, 80) : title,
      whenMs: (map['when'] is int)
          ? map['when'] as int
          : int.tryParse('${map['when']}') ?? 0,
      reason: map['reason']?.toString() ?? '',
    );
  }
}

/// Mirrors native ring-buffer rules for unit tests (G28.5).
@visibleForTesting
List<DroppedNotification> parseDroppedNotificationsJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final byKey = <String, DroppedNotification>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final d = DroppedNotification.fromMap(Map<Object?, Object?>.from(item));
      if (d.pkg.isEmpty) continue;
      byKey['${d.pkg}::${d.title}'] = d; // last-wins = newest if appended
    }
    final list = byKey.values.toList()
      ..sort((a, b) => b.whenMs.compareTo(a.whenMs));
    if (list.length <= 20) return list;
    return list.sublist(0, 20);
  } catch (_) {
    return const [];
  }
}
