import 'package:flutter/material.dart';

import '../icons/centli_icon_catalog.dart';

/// Circular category chip: Material icon + soft fill by category name.
({IconData icon, Color bg, Color fg}) categoryVisual({
  required String name,
  String? kind,
  String? iconKey,
}) {
  final key = (iconKey ?? '').trim();

  if (isCentliHanziIcon(key)) {
    final colors = colorsForName(name.isNotEmpty ? name : key);
    return (icon: Icons.text_fields_rounded, bg: colors.$1, fg: colors.$2);
  }

  if (key.isNotEmpty) {
    // Brand glyph keys (wechat/alipay/…) — soft colored placeholder for IconData API.
    final brand = brandGlyphForKey(key);
    if (brand != null) {
      return (icon: Icons.text_fields_rounded, bg: brand.bg, fg: brand.fg);
    }

    final mapped = iconDataForKey(key) ?? _iconFromKeyLegacy(key);
    if (mapped != null) {
      final tint = brandColorsForKey(key);
      if (tint != null) {
        return (icon: mapped, bg: tint.bg, fg: tint.fg);
      }
      final colors = colorsForName(name.isNotEmpty ? name : key);
      return (icon: mapped, bg: colors.$1, fg: colors.$2);
    }
  }

  final n = name.trim();
  if (n.isEmpty) {
    if (kind == 'transfer') {
      return (
        icon: Icons.swap_horiz_rounded,
        bg: const Color(0xFFE8EAF6),
        fg: const Color(0xFF3949AB),
      );
    }
    if (kind == 'in') {
      return (
        icon: Icons.south_west_rounded,
        bg: const Color(0xFFE8F5E9),
        fg: const Color(0xFF2E7D32),
      );
    }
    return (
      icon: Icons.receipt_long_outlined,
      bg: const Color(0xFFF5F5F5),
      fg: const Color(0xFF616161),
    );
  }

  final hit = _byName(n);
  if (hit != null) return hit;
  final colors = colorsForName(n);
  return (icon: _iconFallback(n), bg: colors.$1, fg: colors.$2);
}

({IconData icon, Color bg, Color fg})? _byName(String n) {
  bool has(String s) => n.contains(s);

  if (has('订阅') || has('会员') || has('音乐') || has('影视')) {
    return (
      icon: Icons.album_rounded,
      bg: const Color(0xFFE3F2FD),
      fg: const Color(0xFF1565C0),
    );
  }
  if (has('早餐') ||
      has('午餐') ||
      has('晚餐') ||
      has('餐饮') ||
      has('吃饭') ||
      has('外卖') ||
      has('美食') ||
      has('咖啡')) {
    return (
      icon: Icons.restaurant_rounded,
      bg: const Color(0xFFFFF3E0),
      fg: const Color(0xFFE65100),
    );
  }
  if (has('红包') || has('人为') || has('人情') || has('礼金')) {
    return (
      icon: Icons.card_giftcard_rounded,
      bg: const Color(0xFFFFEBEE),
      fg: const Color(0xFFC62828),
    );
  }
  if (has('交通') || has('打车') || has('地铁') || has('公交') || has('加油')) {
    return (
      icon: Icons.directions_car_filled_rounded,
      bg: const Color(0xFFE0F7FA),
      fg: const Color(0xFF00838F),
    );
  }
  if (has('日用') || has('购物') || has('超市') || has('日杂')) {
    return (
      icon: Icons.shopping_bag_rounded,
      bg: const Color(0xFFF3E5F5),
      fg: const Color(0xFF6A1B9A),
    );
  }
  if (has('居住') || has('房租') || has('水电') || has('物业')) {
    return (
      icon: Icons.home_rounded,
      bg: const Color(0xFFE8EAF6),
      fg: const Color(0xFF3949AB),
    );
  }
  if (has('娱乐') || has('游戏') || has('电影')) {
    return (
      icon: Icons.sports_esports_rounded,
      bg: const Color(0xFFFCE4EC),
      fg: const Color(0xFFAD1457),
    );
  }
  if (has('医疗') || has('医院') || has('药')) {
    return (
      icon: Icons.local_hospital_rounded,
      bg: const Color(0xFFE0F2F1),
      fg: const Color(0xFF00695C),
    );
  }
  if (has('教育') || has('学费') || has('书')) {
    return (
      icon: Icons.menu_book_rounded,
      bg: const Color(0xFFFFF8E1),
      fg: const Color(0xFFF9A825),
    );
  }
  if (has('工资') || has('薪')) {
    return (
      icon: Icons.payments_rounded,
      bg: const Color(0xFFE8F5E9),
      fg: const Color(0xFF2E7D32),
    );
  }
  if (has('理财') || has('投资') || has('基金') || has('股票')) {
    return (
      icon: Icons.trending_up_rounded,
      bg: const Color(0xFFE3F2FD),
      fg: const Color(0xFF0277BD),
    );
  }
  if (has('转账')) {
    return (
      icon: Icons.swap_horiz_rounded,
      bg: const Color(0xFFE8EAF6),
      fg: const Color(0xFF3949AB),
    );
  }
  if (has('其他')) {
    return (
      icon: Icons.more_horiz_rounded,
      bg: const Color(0xFFF5F5F5),
      fg: const Color(0xFF757575),
    );
  }
  return null;
}

IconData? _iconFromKeyLegacy(String key) {
  switch (key) {
    case 'restaurant':
    case 'food':
      return Icons.restaurant_rounded;
    case 'transport':
    case 'car':
      return Icons.directions_car_filled_rounded;
    case 'shopping':
      return Icons.shopping_bag_rounded;
    case 'home':
      return Icons.home_rounded;
    case 'fun':
    case 'game':
      return Icons.sports_esports_rounded;
    case 'medical':
      return Icons.local_hospital_rounded;
    case 'edu':
    case 'book':
      return Icons.menu_book_rounded;
    case 'salary':
    case 'pay':
      return Icons.payments_rounded;
    case 'gift':
    case 'redpacket':
      return Icons.card_giftcard_rounded;
    case 'invest':
      return Icons.trending_up_rounded;
    case 'music':
    case 'sub':
      return Icons.album_rounded;
    case 'transfer':
      return Icons.swap_horiz_rounded;
    default:
      return null;
  }
}

IconData _iconFallback(String n) {
  const icons = <IconData>[
    Icons.category_rounded,
    Icons.local_offer_rounded,
    Icons.pets_rounded,
    Icons.flight_rounded,
    Icons.fitness_center_rounded,
    Icons.phone_iphone_rounded,
    Icons.coffee_rounded,
    Icons.beach_access_rounded,
  ];
  return icons[n.hashCode.abs() % icons.length];
}

/// Soft chip colors (shared with CentliIconChip).
(Color, Color) colorsForName(String n) {
  const pairs = <(Color, Color)>[
    (Color(0xFFFFF3E0), Color(0xFFE65100)),
    (Color(0xFFE3F2FD), Color(0xFF1565C0)),
    (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    (Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
    (Color(0xFFFFEBEE), Color(0xFFC62828)),
    (Color(0xFFE0F7FA), Color(0xFF00838F)),
    (Color(0xFFFFF8E1), Color(0xFFF9A825)),
    (Color(0xFFFCE4EC), Color(0xFFAD1457)),
  ];
  return pairs[n.hashCode.abs() % pairs.length];
}

/// Soft circle with catalog icon or 1–2 hanzi characters.
class CategoryCircleIcon extends StatelessWidget {
  const CategoryCircleIcon({
    super.key,
    required this.name,
    this.kind,
    this.iconKey,
    this.size = 44,
  });

  final String name;
  final String? kind;
  final String? iconKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final key = (iconKey ?? '').trim();

    // Free-text hanzi:…
    final freeHanzi = parseCentliHanzi(key);
    if (freeHanzi != null) {
      final colors = colorsForName(freeHanzi);
      return _chip(
        bg: colors.$1,
        child: Text(
          freeHanzi,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.$2,
            fontWeight: FontWeight.w700,
            fontSize: size * (freeHanzi.runes.length >= 2 ? 0.32 : 0.42),
            height: 1.05,
          ),
        ),
      );
    }

    // Catalog brand glyph (微 / 支 / …).
    final brand = brandGlyphForKey(key);
    if (brand != null) {
      return _chip(
        bg: brand.bg,
        child: Text(
          brand.glyph,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: brand.fg,
            fontWeight: FontWeight.w700,
            fontSize:
                size * (brand.glyph.runes.length >= 2 ? 0.32 : 0.42),
            height: 1.05,
          ),
        ),
      );
    }

    final v = categoryVisual(name: name, kind: kind, iconKey: iconKey);
    return _chip(
      bg: v.bg,
      child: Icon(v.icon, size: size * 0.48, color: v.fg),
    );
  }

  Widget _chip({required Color bg, required Widget child}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
