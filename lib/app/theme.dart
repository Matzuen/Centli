import 'package:flutter/material.dart';


/// Soft pastel theme: Centli chrome + Finch polish (cards/gradient/radii).
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
  static const seed = Color(0xFF5B8DEF);

  static const gradientTop = Color(0xFFE8F1FF);
  static const gradientMid = Color(0xFFF3ECFF);
  static const gradientBottom = Color(0xFFFFF0F5);

  static const cardRadius = 22.0;
  static const pillRadius = 28.0;

  static const expenseRed = Color(0xFFE53935);
  static const incomeGreen = Color(0xFF43A047);
  static const softBlue = Color(0xFF5B8DEF);
  static const coral = Color(0xFFFF8A80);
  // Light keypad — B3/T6 contract measured hex.
  static const keypadNumBgLight = Color(0xFFEAEDF4);
  static const keypadOpBgLight = Color(0xFFD4E5F5);
  static const keypadAcBgLight = Color(0xFFFEDBD7);
  static const keypadConfirmLight = Color(0xFF1F98F5);
  static const keypadOpFgLight = Color(0xFF2A7BD4);
  static const keypadAcFgLight = Color(0xFFA45D61);
  static const keypadNumFgLight = Color(0xFF1F2229);
  static const chipBorderLight = Color(0xFFE5E7EB);

  // Dark keypad — deep tones coordinated with dark ColorScheme surfaces.
  static const keypadNumBgDark = Color(0xFF2A2F3A);
  static const keypadOpBgDark = Color(0xFF2E3A52);
  static const keypadAcBgDark = Color(0xFF432E2E);
  static const keypadConfirmDark = Color(0xFF4C7DFF);

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
      return const [Color(0xFF1A1F2E), Color(0xFF221F2E), Color(0xFF2A1F28)];
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
      color: const Color(0xFF6B7A99).withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: softBlue,
      error: expenseRed,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      scaffoldBackgroundColor: gradientTop,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        // Match gradient top so transparent routes never show a black AppBar strip.
        backgroundColor: gradientTop,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
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
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        indicatorColor: softBlue.withValues(alpha: 0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? softBlue : const Color(0xFF6B7280),
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
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: const Color(0xFF1A1F2E),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
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
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
  }
}

/// Soft pastel gradient behind page content.
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
    return Scaffold(
      extendBody: extendBody,
      // Fill AppBar strip; body DecoratedBox still paints the full gradient.
      backgroundColor:
          dark ? const Color(0xFF1A1F2E) : CentliTheme.gradientTop,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: DecoratedBox(
        decoration: CentliTheme.scaffoldGradient(dark: dark),
        child: body,
      ),
    );
  }
}

/// White rounded card with soft shadow.
class CentliSoftCard extends StatelessWidget {
  const CentliSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CentliSpacing.cardPad),
    this.margin,
    this.onTap,
    this.color,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  /// When null, uses white / dark surfaceContainerHighest.
  final Color? color;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ??
        (dark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.white);
    return Container(
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CentliTheme.cardRadius),
        boxShadow: (dark || color != null) ? null : CentliTheme.softCardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CentliTheme.cardRadius),
          // 统一的内边距：所有卡片默认 16，避免 12/14/18/20/24 混用。
          child: Padding(
            padding: padding ?? const EdgeInsets.all(CentliSpacing.cardPad),
            child: child,
          ),
        ),
      ),
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

