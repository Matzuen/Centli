import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 毛玻璃基础组件：模糊「已经画在下面」的内容，再盖一层半透明色。
///
/// 只新增半透明的玻璃色，**不改任何渐变色**（`CentliTheme.gradientTop/Mid/
/// Bottom` 与 `scaffoldGradient` 保持原样），所以页面底色仍是原来的渐变。
///
/// 结构（顺序很重要）：
/// 1. 外层承担阴影（阴影要被圆角裁掉就看不见了）
/// 2. `ClipRRect` 限制模糊的作用范围，避免整屏模糊
/// 3. `BackdropFilter` 采样下方像素并模糊
/// 4. 最内层是半透明填充 + 1px 高光描边，形成玻璃质感
class CentliGlass extends StatelessWidget {
  const CentliGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.sigma = CentliTheme.glassSigma,
    this.tint,
    this.borderColor,
    this.shadow = true,
    this.padding,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// 全局模糊开关：`BackdropFilter` 在低端机上是实打实的开销。
  /// 置 false 后所有玻璃表面退化成「半透明 + 高光边」，观感仍统一，只是不模糊。
  static bool blurEnabled = true;

  /// 默认按卡片圆角；底部弹层可传只圆上面的角。
  final BorderRadius? borderRadius;

  /// 模糊半径。0 表示只做半透明（低端机或测试里可以直接关掉）。
  final double sigma;

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

    if (sigma > 0 && CentliGlass.blurEnabled) {
      surface = ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
          child: surface,
        ),
      );
    } else {
      surface = ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: radius,
        child: surface,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ? CentliTheme.glassShadow(context, dark: dark) : null,
      ),
      child: surface,
    );
  }
}

/// 弹窗 / 菜单背后的整屏磨砂底：全屏模糊 + 一层很薄的色纱。
///
/// 单独抽出来是因为「弹窗自己的圆角表面」和「它背后那面磨砂墙」是两件事：
/// 只有把整屏都模糊掉，半透明的弹窗看起来才像玻璃，而不是一块灰板。
class CentliGlassBackdrop extends StatelessWidget {
  const CentliGlassBackdrop({
    super.key,
    this.sigma = CentliTheme.glassBackdropSigma,
  });

  final double sigma;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (sigma <= 0 || !CentliGlass.blurEnabled) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
        child: ColoredBox(color: CentliTheme.glassVeil(context, dark: dark)),
      ),
    );
  }
}

/// `showDialog` 的毛玻璃版本：调用点只需换函数名，其余参数逐一透传。
///
/// 实现方式是给弹窗背后铺一层 [CentliGlassBackdrop]，弹窗表面本身通过
/// `dialogTheme.backgroundColor` 换成半透明，于是玻璃感来自「背后被磨砂 +
/// 表面半透明」，弹窗内部的排版与行为完全不变。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
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
    // 磨砂层自己会压暗画面，系统遮罩再压一次就糊成一团。
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.16),
    barrierLabel: barrierLabel,
    // 关掉 route 级 SafeArea，改用自己的一层，让磨砂能铺到屏幕边缘。
    useSafeArea: false,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
    builder: (ctx) => Stack(
      fit: StackFit.expand,
      children: [
        const CentliGlassBackdrop(),
        SafeArea(child: Builder(builder: builder)),
      ],
    ),
  );
}

/// `showModalBottomSheet` 的毛玻璃版本：同样只换函数名。
///
/// 底部弹层只占屏幕下方一块，所以不需要整屏磨砂；把弹层自己的表面换成
/// [CentliGlass]，模糊的就是它正下方那块页面内容。
///
/// 调用点传进来的 `backgroundColor` 会被当作玻璃底色（不传则用默认雾面），
/// 这样原本传白色的弹层不会突然变成透明白；`elevation` 保留但不参与玻璃
/// 层次（玻璃的投影由 [CentliGlass] 统一处理）。
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
    shape: shape ??
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

// 与 SDK 内部常量保持一致，避免两条路径的默认高度比例不同。
const double _kDefaultScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;
