import 'package:flutter/material.dart';

import '../core/widgets/glass.dart';


/// Centli 绿紫渐变主题（薄荷绿 → 淡紫 → 丁香紫）+ 统一圆角 / 卡片。
/// Shared layout density tokens — prefer these over one-off magic numbers.
abstract final class CentliSpacing {
  /// Horizontal page inset (ListView / column).
  static const double pageH = 16;

  /// Top inset under app bar / safe area.
  static const double pageTop = 8;

  /// Bottom inset on settings-style pages (no bottom nav).
  static const double pageBottom = 32;

  /// Bottom inset on tab roots (clears bottom nav).
  static const double pageBottomNav = 120;

  /// Unified page padding for every scrolling root: 16 / 12 / 16 / bottom.
  /// (Home / stats / settings pages all use this via [pagePadding] /
  /// [pagePaddingNav].)
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    pageH,
    pageTop,
    pageH,
    pageBottom,
  );

  /// Same as [pagePadding] but leaves room for the bottom navigation bar.
  static const EdgeInsets pagePaddingNav = EdgeInsets.fromLTRB(
    pageH,
    pageTop,
    pageH,
    pageBottomNav,
  );

  /// Gap between soft cards / major blocks.
  static const double section = 12;

  /// Gap before a section title or looser break.
  static const double sectionLoose = 16;

  /// Gap between related items inside a section.
  static const double item = 8;

  /// Tight gap (labels under titles, chip runs).
  static const double dense = 4;

  /// Default inner padding for [CentliSoftCard] content.
  static const double cardPad = 16;

  /// Bookkeeping: note field → keypad.
  static const double sheetGap = 12;
}

abstract final class CentliTheme {
  /// Brand purple — primary chrome / CTAs（偏淡、低饱和）。
  static const seed = Color(0xFF8B84D6);
  static const brandPrimary = Color(0xFF8B84D6);
  /// Soft mint accent (pairs with purple in the gradient).
  static const brandGreen = Color(0xFF6BB89A);

  // 背景渐变更淡：近白的薄荷绿 → 淡紫 → 丁香紫。
  static const gradientTop = Color(0xFFF4FAF7);
  static const gradientMid = Color(0xFFF7F4FB);
  static const gradientBottom = Color(0xFFFAF5FC);

  static const cardRadius = 22.0;
  static const pillRadius = 28.0;

  static const expenseRed = Color(0xFFE53935);
  static const incomeGreen = Color(0xFF43A047);
  /// Legacy name kept for call sites; value is [brandPrimary].
  static const softBlue = brandPrimary;
  static const coral = Color(0xFFFF8A80);
  // Light keypad — muted green / purple chrome.
  static const keypadNumBgLight = Color(0xFFF1F3F5);
  static const keypadOpBgLight = Color(0xFFE5F3EC);
  static const keypadAcBgLight = Color(0xFFFEDBD7);
  static const keypadConfirmLight = Color(0xFF8B84D6);
  static const keypadOpFgLight = Color(0xFF4A9A7A);
  static const keypadAcFgLight = Color(0xFFA45D61);
  static const keypadNumFgLight = Color(0xFF1F2229);
  static const chipBorderLight = Color(0xFFE5E7EB);

  // Dark keypad — deep tones coordinated with dark ColorScheme surfaces.
  static const keypadNumBgDark = Color(0xFF2A2F3A);
  static const keypadOpBgDark = Color(0xFF2A3A34);
  static const keypadAcBgDark = Color(0xFF432E2E);
  static const keypadConfirmDark = Color(0xFF9B94E0);

  /// Brightness-aware keypad backgrounds (prefer these over Light/Dark consts).
  static Color keypadNumBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? keypadNumBgDark
          : keypadNumBgLight;

  static Color keypadOpBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? keypadOpBgDark
          : keypadOpBgLight;

  static Color keypadAcBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? keypadAcBgDark
          : keypadAcBgLight;

  static Color keypadConfirm(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? keypadConfirmDark
          : keypadConfirmLight;

  /// AC / backspace foreground.
  static Color keypadAcFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.error
          : keypadAcFgLight;

  static Color keypadOpFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? softBlue
          : keypadOpFgLight;

  static Color keypadNumFg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.onSurface
          : keypadNumFgLight;

  static Color chipBorder(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.outlineVariant
          : chipBorderLight;

  static List<Color> scaffoldGradientColors({bool dark = false}) {
    if (dark) {
      // 深色同样压低饱和，避免绿/紫发闷。
      return const [Color(0xFF161C1A), Color(0xFF1A1822), Color(0xFF1E1A24)];
    }
    return const [gradientTop, gradientMid, gradientBottom];
  }

  static BoxDecoration scaffoldGradient({bool dark = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: scaffoldGradientColors(dark: dark),
      ),
    );
  }

  static List<BoxShadow> get softCardShadow => [
    BoxShadow(
      color: const Color(0xFF5A6B7A).withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  // ---------------------------------------------------------------------------
  // 毛玻璃（glassmorphism）
  //
  // 只新增半透明的「玻璃」色，**渐变本身一个字节都不改**：页面底色仍然是
  // gradientTop / gradientMid / gradientBottom 与 scaffoldGradient。
  // 玻璃层叠在渐变之上，所以视觉主色不变，只多了一层磨砂质感。
  // ---------------------------------------------------------------------------

  /// 模糊半径：卡片 / 弹层表面。
  static const double glassSigma = 18;

  /// 模糊半径：弹窗背后那面整屏磨砂。
  static const double glassBackdropSigma = 26;

  /// 玻璃填充色（半透明）：浅色是透白的雾面，深色是透炭灰的雾面。
  static Color glassTint(BuildContext context, {bool? dark}) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return d
        ? const Color(0xFF1B1F24).withValues(alpha: 0.66)
        : Colors.white.withValues(alpha: 0.70);
  }

  /// 弹窗 / 弹层表面：比卡片实一点，保证正文可读。
  static Color glassSurface(BuildContext context, {bool? dark}) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return d
        ? const Color(0xFF1B1F24).withValues(alpha: 0.84)
        : Colors.white.withValues(alpha: 0.88);
  }

  /// 磨砂底的色纱：很薄，只把对比度抬一点，避免纯模糊发灰。
  static Color glassVeil(BuildContext context, {bool? dark}) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return d
        ? const Color(0xFF0E1114).withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.16);
  }

  /// 玻璃边缘的高光描边。
  static Color glassBorder(BuildContext context, {bool? dark}) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return d
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.60);
  }

  /// 玻璃卡片的投影：比纯白卡片略深，玻璃才「浮」得起来。
  static List<BoxShadow> glassShadow(BuildContext context, {bool? dark}) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return d
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ]
        : [
            BoxShadow(
              color: const Color(0xFF5A6B7A).withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ];
  }

  static ThemeData _chrome(ThemeData theme, {required bool dark}) {
    // 毛玻璃：弹窗 / 弹层 / 菜单的表面都换成半透明，背后的模糊层才透得出来。
    final surface = dark
        ? const Color(0xFF1B1F24).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.86);
    final menuSurface = dark
        ? const Color(0xFF1B1F24).withValues(alpha: 0.88)
        : Colors.white.withValues(alpha: 0.88);
    final hairline = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.65);
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: hairline),
    );
    return theme.copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: menuSurface,
        elevation: 2,
        surfaceTintColor: Colors.transparent,
        shape: menuShape,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(menuShape),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(menuShape),
        ),
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: softBlue,
      error: expenseRed,
    );
    final data = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      scaffoldBackgroundColor: gradientTop,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // 玻璃顶栏：极淡的雾面 + 细高光边，绿紫渐变仍然从下面透上来。
        backgroundColor: Colors.white.withValues(alpha: 0.35),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onSecondaryContainer;
            }
            return scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.secondaryContainer;
            }
            return null;
          }),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // 与卡片同色纯白，贴在粉紫渐变底上，避免发灰发闷。
        backgroundColor: Colors.white,
        indicatorColor: softBlue.withValues(alpha: 0.10),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? softBlue : const Color(0xFF9AA3B5),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? softBlue : const Color(0xFF9AA3B5),
          );
        }),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shadowColor: const Color(0xFF6B7A99).withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: const DividerThemeData(
        space: 1,
        thickness: 0.5,
        color: Color(0xFFEEEEEE),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE6E8EC)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        backgroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8EC)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: Colors.white,
        foregroundColor: softBlue,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
    return _chrome(data, dark: false);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final data = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onSecondaryContainer;
            }
            return scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.secondaryContainer;
            }
            return null;
          }),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerHighest,
        indicatorColor: softBlue.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? softBlue : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? softBlue : scheme.onSurfaceVariant,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minVerticalPadding: 10,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 2,
        shape: CircleBorder(),
      ),
    );
    return _chrome(data, dark: true);
  }
}

/// 绿紫渐变底，铺在页面内容后方。
class CentliGradientScaffold extends StatelessWidget {
  const CentliGradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBody = false,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: CentliTheme.scaffoldGradient(dark: dark),
      child: Scaffold(
        extendBody: extendBody,
        backgroundColor: Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        body: body,
      ),
    );
  }
}

/// 毛玻璃圆角卡片。
///
/// 表面是一层半透明雾面 + 1px 高光描边，背后经过模糊，所以卡片会「透出」
/// 下层渐变的颜色 —— 渐变本身没有被修改，只是被磨砂了一层。
class CentliSoftCard extends StatelessWidget {
  const CentliSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CentliSpacing.cardPad),
    this.margin,
    this.onTap,
    this.color,
    this.clipBehavior = Clip.antiAlias,
    this.glass = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// 玻璃底色覆盖；为 null 时用 [CentliTheme.glassTint]。
  /// 传入不透明颜色即恢复成实色卡片。
  final Color? color;
  final Clip clipBehavior;

  /// 关掉毛玻璃（例如需要完全实色、或嵌在另一个玻璃层里避免重复模糊）。
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ?? CentliTheme.glassTint(context, dark: dark);
    final radius = BorderRadius.circular(CentliTheme.cardRadius);
    // 点了才有 InkWell 的波纹层；Material 自身保持透明，避免盖住玻璃。
    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        // 统一的内边距：所有卡片默认 16，避免 12/14/18/20/24 混用。
        child: Padding(
          padding: padding ?? const EdgeInsets.all(CentliSpacing.cardPad),
          child: child,
        ),
      ),
    );
    if (!glass) {
      return Container(
        margin: margin,
        clipBehavior: clipBehavior,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          boxShadow:
              (dark || color != null) ? null : CentliTheme.softCardShadow,
        ),
        child: content,
      );
    }
    return CentliGlass(
      margin: margin,
      borderRadius: radius,
      clipBehavior: clipBehavior,
      tint: color,
      child: content,
    );
  }
}

/// Friendly empty / placeholder block used across list pages.
class CentliEmptyState extends StatelessWidget {
  const CentliEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.padding = const EdgeInsets.all(28),
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.outline),
          const SizedBox(height: CentliSpacing.item + 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: CentliSpacing.item),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: CentliSpacing.sectionLoose),
            action!,
          ],
        ],
      ),
    );
  }
}

