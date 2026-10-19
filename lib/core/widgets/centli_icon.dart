import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons/centli_icon_catalog.dart';
import 'category_visuals.dart';

/// Soft circle/rounded chip showing a downloaded SVG, hanzi fallback, or auto.
///
/// Storage conventions for [iconKey]:
/// - catalog key (e.g. `wechat`, `restaurant`) → SVG under assets/icons/
/// - `hanzi:餐` / `hanzi:餐饮` → 1–2 Chinese characters
/// - null / empty → heuristics from [name] / [kind]
class CentliIconChip extends StatelessWidget {
  const CentliIconChip({
    super.key,
    required this.name,
    this.kind,
    this.iconKey,
    this.size = 44,
    this.roundedSquare = false,
  });

  final String name;
  final String? kind;
  final String? iconKey;
  final double size;
  final bool roundedSquare;

  @override
  Widget build(BuildContext context) {
    final visual = resolveCentliVisual(
      name: name,
      kind: kind,
      iconKey: iconKey,
    );
    final radius =
        roundedSquare ? BorderRadius.circular(size * 0.28) : null;

    Widget child;
    if (visual.hanzi != null) {
      child = Text(
        visual.hanzi!,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: visual.fg,
          fontWeight: FontWeight.w700,
          fontSize: size * (visual.hanzi!.runes.length >= 2 ? 0.32 : 0.42),
          height: 1.05,
        ),
      );
    } else if (visual.asset != null) {
      child = SvgPicture.asset(
        visual.asset!,
        width: visual.keepColors ? size * 0.72 : size * 0.52,
        height: visual.keepColors ? size * 0.72 : size * 0.52,
        colorFilter: visual.keepColors
            ? null
            : ColorFilter.mode(visual.fg, BlendMode.srcIn),
        fit: BoxFit.contain,
      );
    } else {
      child = Icon(visual.icon, size: size * 0.48, color: visual.fg);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: visual.bg,
        shape: roundedSquare ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Resolved paint data for a category / account chip.
class CentliVisual {
  const CentliVisual({
    required this.bg,
    required this.fg,
    this.icon = Icons.category_rounded,
    this.hanzi,
    this.asset,
    this.keepColors = false,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
  final String? hanzi;
  final String? asset;

  /// Brand marks (bank logos) keep their own fills instead of a single tint.
  final bool keepColors;
}

/// Resolve SVG / hanzi / colors for any entity with [iconKey].
///
/// Priority:
/// 1. Free-text `hanzi:…`
/// 2. Catalog SVG asset
/// 3. Name / kind heuristics (Material fallback)
CentliVisual resolveCentliVisual({
  required String name,
  String? kind,
  String? iconKey,
}) {
  final key = (iconKey ?? '').trim();

  // 1) Explicit free-text hanzi icon.
  final hanzi = parseCentliHanzi(key);
  if (hanzi != null) {
    final colors = colorsForName(hanzi.isNotEmpty ? hanzi : name);
    return CentliVisual(bg: colors.$1, fg: colors.$2, hanzi: hanzi);
  }

  if (key.isNotEmpty) {
    final resolved = resolveCentliIconKey(key);
    final entry = centliIconByKey[resolved];
    final asset = entry?.asset ?? assetPathForIconKey(resolved);
    if (asset != null) {
      // Multicolor SVGs from iconfont keep fills; chip uses a soft neutral pad.
      const keepColors = true;
      final tint = brandColorsForKey(resolved);
      if (tint != null) {
        return CentliVisual(
          asset: asset,
          bg: const Color(0xFFF4F6F8),
          fg: tint.fg,
          keepColors: keepColors,
        );
      }
      final colors = colorsForName(name.isNotEmpty ? name : resolved);
      return CentliVisual(
        asset: asset,
        bg: const Color(0xFFF4F6F8),
        fg: entry?.fg ?? colors.$2,
        keepColors: keepColors,
      );
    }
  }

  // 3) Auto heuristics.
  final legacy = categoryVisual(name: name, kind: kind, iconKey: null);
  return CentliVisual(icon: legacy.icon, bg: legacy.bg, fg: legacy.fg);
}

/// 1–2 character initials from [name] (for “用名称首字” in the picker).
String initialsFromName(String name, {int max = 2}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final chars = trimmed.runes.map(String.fromCharCode).toList();
  if (chars.length <= max) return chars.join();
  return chars.take(max).join();
}
