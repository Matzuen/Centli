import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 毛玻璃基础组件。
///
/// 只新增半透明的玻璃色，**不改任何渐变色**（`CentliTheme.gradientTop/Mid/
/// Bottom` 与 `scaffoldGradient` 保持原样）。
///
/// 结构（顺序很重要）：
/// 1. 外层承担阴影（阴影要被圆角裁掉就看不见了）
/// 2. `ClipRRect` 限制模糊的作用范围
/// 3. `BackdropFilter` 采样下方像素并模糊
/// 4. 最内层是半透明填充 + 1px 高光描边
///
/// [blur] 为 false 时只保留半透明 + 描边：卡片这类「背后只有一层平滑渐变」
/// 的表面用不着模糊（视觉上没有差别，却要付出真实的 GPU 开销），弹窗这类
/// 「背后是页面内容」的表面才需要真模糊。
class CentliGlass extends StatelessWidget {
  const CentliGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.sigma = CentliTheme.glassSigma,
    this.blur = true,
    this.tint,
    this.borderColor,
    this.shadow = true,
    this.padding,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// 全局模糊开关：`BackdropFilter` 是实打实的 GPU 开销。
  /// 置 false 后所有玻璃表面退化成「半透明 + 高光边」，观感仍统一。
  static bool blurEnabled = true;

  /// 默认按卡片圆角；底部弹层可传只圆上面的角。
  final BorderRadius? borderRadius;

  /// 模糊半径。
  final double sigma;

  /// 是否真的模糊；false 时只有半透明 + 描边。
  final bool blur;

  /// 玻璃底色；默认浅色白 / 深色炭灰的半透明版本。
  final Color? tint;

  /// 1px 描边；默认浅色白 / 深色白低透明度，用来勾边。
  final Color? borderColor;

  final bool shadow;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(CentliTheme.cardRadius);
    final fill = tint ?? CentliTheme.glassTint(context, dark: dark);
    final hairline = borderColor ?? CentliTheme.glassBorder(context, dark: dark);
    final doBlur = blur && sigma > 0 && CentliGlass.blurEnabled;

    // 半透明填充 + 高光描边；画在模糊层之上。
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: hairline),
      ),
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child),
    );

    if (doBlur) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
        child: surface,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ? CentliTheme.glassShadow(context, dark: dark) : null,
      ),
      child: ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: radius,
        child: surface,
      ),
    );
  }
}

/// `showDialog` 的毛玻璃版本：调用点只需换函数名，其余参数逐一透传。
///
/// 玻璃感来自**弹窗自身的半透明表面**（见 [CentliGlassDialog] 里的那层
/// `BackdropFilter`）：它模糊的是自己身后的页面内容，而不是给整页再加一层
/// 模糊。系统遮罩只做轻微压暗，避免与玻璃叠加成一片灰。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.18),
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
    builder: builder,
  );
}

/// `showModalBottomSheet` 的毛玻璃版本：同样只换函数名。
///
/// 底部弹层只占屏幕下方一块，不需要整屏处理；玻璃表面就是弹层自己，模糊的
/// 是它正下方那块页面内容。
///
/// 调用点传进来的 `backgroundColor` 会被当作玻璃底色（不传则用默认雾面），
/// 这样原本传白色的弹层不会突然变成透明白。
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? barrierLabel,
  Color? barrierColor,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio =
      _kDefaultScrollControlDisabledMaxHeightRatio,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierLabel: barrierLabel,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.24),
    constraints: constraints,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: sheetAnimationStyle,
    requestFocus: requestFocus,
    elevation: elevation,
    clipBehavior: clipBehavior,
    // 让 route 的材质透明，玻璃表面由 builder 里的 CentliGlass 自己画。
    backgroundColor: Colors.transparent,
    shape:
        shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
    builder: (ctx) => CentliGlass(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      tint: backgroundColor,
      child: Builder(builder: builder),
    ),
  );
}

/// 毛玻璃弹窗面板：`AlertDialog` 的等价替代。
///
/// 只覆盖项目里实际用到的 `title` / `content` / `actions` / `insetPadding`
/// 四个参数，内部布局与 `AlertDialog` 对齐（24 边距、按钮右对齐），但表面是
/// 一层真正模糊身后内容的玻璃，而不是给整页加模糊。
class CentliGlassDialog extends StatelessWidget {
  const CentliGlassDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.insetPadding,
  });

  final Widget title;
  final Widget content;
  final List<Widget>? actions;

  /// 与 `AlertDialog` 同义；不传时沿用 M3 默认（左右 40 / 上下 24）。
  final EdgeInsets? insetPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Dialog(
      // 表面全部由 CentliGlass 负责，route 自己的材质保持全透明。
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          insetPadding ??
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        child: CentliGlass(
          borderRadius: BorderRadius.circular(CentliTheme.cardRadius),
          tint: CentliTheme.glassSurface(context, dark: dark),
          sigma: CentliTheme.glassDialogSigma,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: DefaultTextStyle(
                  // 与 AlertDialog 的标题样式保持一致（主题里的 headlineSmall）。
                  style: theme.textTheme.headlineSmall!,
                  child: title,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: content,
                  ),
                ),
              ),
              if (actions != null && actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 4,
                    children: actions!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// 与 SDK 内部常量保持一致，避免两条路径的默认高度比例不同。
const double _kDefaultScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;
