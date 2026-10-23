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
/// 4. 最内层是半透明填充 + 描边（宽度见 [CentliTheme.glassBorderWidth]）
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
    this.borderWidth,
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

  /// 描边颜色；默认 [CentliTheme.glassBorder]。
  final Color? borderColor;

  /// 描边线宽；默认 [CentliTheme.glassBorderWidth]。
  final double? borderWidth;

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
    final stroke = borderWidth ?? CentliTheme.glassBorderWidth;
    final doBlur = blur && sigma > 0 && CentliGlass.blurEnabled;

    // 半透明填充 + 高光描边；画在模糊层之上。
    // Material(transparency) 必须在 DecoratedBox *之内*：否则 sheet/dialog
    // 里裸 ListTile 向上找到的 Material 在玻璃外，_debugCheckBackgroundIsHidden
    // 会报「ink splashes may be invisible」。CentliSoftCard 已各自包一层，
    // 这里统一兜底，覆盖 showGlassSheet / showGlassDialog 全部路径。
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: hairline, width: stroke),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: content,
      ),
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

/// 毛玻璃弹窗：用 [showGeneralDialog]（不要用系统 [Dialog] 路由的默认材质），
/// 这样 [BackdropFilter] 才能采到身后页面，效果与浮动菜单一致。
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
  final label =
      barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: label,
    // 高透毛玻璃下不再叠黑幕；点外侧仍可关闭。
    barrierColor: barrierColor ?? Colors.transparent,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, anim, secondaryAnim) {
      Widget page = builder(ctx);
      if (useSafeArea) {
        page = SafeArea(child: page);
      }
      return page;
    },
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
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
  // 默认走根 Navigator：Shell 底栏在 body 之上，挂分支 Navigator 会被底栏挡住。
  bool useRootNavigator = true,
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
  // 弹层材质透明时，系统 showDragHandle 会画在 CentliGlass 外侧（悬空灰线）。
  // 把手改画在玻璃内部。
  final paintHandleInside = showDragHandle == true;
  return showModalBottomSheet<T>(
    context: context,
    barrierLabel: barrierLabel,
    // 高透毛玻璃下不再叠黑幕（否则整页发灰）；点外侧仍可关闭。
    barrierColor: barrierColor ?? Colors.transparent,
    constraints: constraints,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
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
    builder: (ctx) {
      final body = Builder(builder: builder);
      final effectiveShape = shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          );
      // 圆角跟 shape 对齐；未传 backgroundColor 时用全局调教好的雾面。
      final radiusGeometry = effectiveShape is RoundedRectangleBorder
          ? effectiveShape.borderRadius
          : const BorderRadius.vertical(top: Radius.circular(24));
      return CentliGlass(
        borderRadius: radiusGeometry.resolve(Directionality.of(ctx)),
        blur: true,
        sigma: CentliTheme.glassSigma,
        tint: backgroundColor ?? CentliTheme.glassTint(ctx),
        child: paintHandleInside
            ? _GlassSheetBodyWithHandle(child: body)
            : body,
      );
    },
  );
}

/// 拖拽条画在玻璃板内顶部，避免透明 Modal 材质把系统 handle 晾在外面。
class _GlassSheetBodyWithHandle extends StatelessWidget {
  const _GlassSheetBodyWithHandle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final handle = Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              Flexible(child: child),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            handle,
            child,
          ],
        );
      },
    );
  }
}

/// 毛玻璃弹窗面板：`AlertDialog` 的等价替代。
///
/// 只覆盖项目里实际用到的 `title` / `content` / `actions` / `insetPadding`
/// 四个参数；**不再包一层系统 [Dialog]**（其材质会挡掉 BackdropFilter）。
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
    final pad =
        insetPadding ??
        const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
    return Center(
      child: Padding(
        padding: pad,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
          child: Material(
            type: MaterialType.transparency,
            child: CentliGlass(
              borderRadius: BorderRadius.circular(CentliTheme.cardRadius),
              blur: true,
              sigma: CentliTheme.glassDialogSigma,
              tint: CentliTheme.glassTint(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: DefaultTextStyle(
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
        ),
      ),
    );
  }
}

// 与 SDK 内部常量保持一致，避免两条路径的默认高度比例不同。
const double _kDefaultScrollControlDisabledMaxHeightRatio = 9.0 / 16.0;

/// 毛玻璃浮动菜单的一项（与首页账本下拉同款：勾选 / 分隔 / 文案）。

/// 危险主按钮样式（删除 / 清空 / 永久操作）：error 底 + onError 字。
ButtonStyle centliDangerFilledStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.error,
    foregroundColor: scheme.onError,
  );
}

/// 统一确认对话框：左「取消」右主操作；[destructive] 时主操作用危险色。
///
/// 返回 `true` 表示确认，`false`/`null` 表示取消或关闭。
Future<bool?> showGlassConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  return showGlassDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => CentliGlassDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive ? centliDangerFilledStyle(ctx) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

class CentliMenuItem<T> {
  const CentliMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.selected = false,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool selected;
  final bool destructive;
}

/// 在锚点旁弹出毛玻璃菜单；样式与首页账本下拉一致。
///
/// 用 [showGeneralDialog] 挂在路由层，[BackdropFilter] 才能采到身后页面。
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<CentliMenuItem<T>> items,
  double minWidth = 148,
  double maxWidth = 280,
  /// `true` 时菜单右缘对齐锚点右缘（顶栏 / trailing 三点菜单）。
  bool alignEnd = false,
}) {
  assert(items.isNotEmpty, 'showGlassMenu items must not be empty');
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) {
    return Future<T?>.value(null);
  }

  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = box.size;
  final menuTop = topLeft.dy + size.height + 4;
  final screenW = overlay.size.width;
  final cappedMax = maxWidth.clamp(minWidth, screenW - 16);

  double menuLeft;
  double? menuRight;
  if (alignEnd) {
    menuRight = screenW - (topLeft.dx + size.width);
    if (menuRight < 8) menuRight = 8;
    menuLeft = 8;
  } else {
    menuLeft = topLeft.dx.clamp(8.0, screenW - minWidth - 8);
    menuRight = null;
  }

  final scheme = Theme.of(context).colorScheme;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, anim, secondaryAnim) {
      return Stack(
        children: [
          Positioned(
            left: alignEnd ? null : menuLeft,
            right: alignEnd ? menuRight : null,
            top: menuTop,
            child: FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: Material(
                type: MaterialType.transparency,
                child: CentliGlass(
                  borderRadius: BorderRadius.circular(
                    CentliTheme.glassMenuRadius,
                  ),
                  blur: true,
                  sigma: CentliTheme.glassSigma,
                  tint: CentliTheme.glassTint(ctx),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: minWidth,
                      maxWidth: cappedMax,
                    ),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.45),
                              ),
                            _CentliMenuTile<T>(item: items[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CentliMenuTile<T> extends StatelessWidget {
  const _CentliMenuTile({required this.item});

  final CentliMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.destructive
        ? scheme.error
        : item.selected
            ? scheme.primary
            : scheme.onSurface;
    return InkWell(
      onTap: () => Navigator.pop(context, item.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: item.selected
                  ? Icon(Icons.check_rounded, size: 18, color: color)
                  : item.icon != null
                      ? Icon(item.icon, size: 18, color: color)
                      : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      item.selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轻提示语义：底色 + 字色同色系（成功绿 / 失败红 / 警告·提示黄）。
enum GlassSnackTone { info, success, error, warning }

/// 按文案猜语义；调用方可显式传 [GlassSnackTone] 覆盖。
GlassSnackTone inferGlassSnackTone(String message) {
  final m = message.trim();
  if (RegExp(r'失败|错误|无效|无法|不能|禁止|异常').hasMatch(m)) {
    return GlassSnackTone.error;
  }
  if (RegExp(r'已入账|已保存|已删除|已恢复|已清空|已忽略|成功|完成|已复制').hasMatch(m)) {
    return GlassSnackTone.success;
  }
  if (RegExp(r'^请|注意|将补|未选|缺少|即将').hasMatch(m)) {
    return GlassSnackTone.warning;
  }
  return GlassSnackTone.info;
}

/// 浅色底约 0.72 透明，仍带一点毛玻璃透感。
const double _kGlassSnackTintAlpha = 0.72;

Color _glassSnackTint(bool dark, GlassSnackTone tone) {
  if (dark) {
    return switch (tone) {
      GlassSnackTone.success =>
        const Color(0xFF1B3D2A).withValues(alpha: _kGlassSnackTintAlpha),
      GlassSnackTone.error =>
        const Color(0xFF4A1F1F).withValues(alpha: _kGlassSnackTintAlpha),
      GlassSnackTone.warning || GlassSnackTone.info =>
        const Color(0xFF3D3420).withValues(alpha: _kGlassSnackTintAlpha),
    };
  }
  return switch (tone) {
    GlassSnackTone.success =>
      const Color(0xFFE8F5E9).withValues(alpha: _kGlassSnackTintAlpha),
    GlassSnackTone.error =>
      const Color(0xFFFFEBEE).withValues(alpha: _kGlassSnackTintAlpha),
    GlassSnackTone.warning || GlassSnackTone.info =>
      const Color(0xFFFFF8E1).withValues(alpha: _kGlassSnackTintAlpha),
  };
}

/// 与底同色系、加深，保证对比度。
Color _glassSnackForeground(bool dark, GlassSnackTone tone) {
  if (dark) {
    return switch (tone) {
      GlassSnackTone.success => const Color(0xFFA5D6A7),
      GlassSnackTone.error => const Color(0xFFEF9A9A),
      GlassSnackTone.warning || GlassSnackTone.info =>
        const Color(0xFFFFE082),
    };
  }
  return switch (tone) {
    GlassSnackTone.success => const Color(0xFF2E7D32),
    GlassSnackTone.error => const Color(0xFFC62828),
    GlassSnackTone.warning || GlassSnackTone.info =>
      const Color(0xFF8D6E00),
  };
}

Color _glassSnackBorder(bool dark, GlassSnackTone tone) {
  if (dark) {
    return switch (tone) {
      GlassSnackTone.success =>
        const Color(0xFF81C784).withValues(alpha: 0.35),
      GlassSnackTone.error =>
        const Color(0xFFE57373).withValues(alpha: 0.35),
      GlassSnackTone.warning || GlassSnackTone.info =>
        const Color(0xFFFFD54F).withValues(alpha: 0.30),
    };
  }
  return switch (tone) {
    GlassSnackTone.success =>
      const Color(0xFF43A047).withValues(alpha: 0.28),
    GlassSnackTone.error =>
      const Color(0xFFE53935).withValues(alpha: 0.28),
    GlassSnackTone.warning || GlassSnackTone.info =>
      const Color(0xFFF9A825).withValues(alpha: 0.35),
  };
}

/// 毛玻璃轻提示：短时显示在底部，不挡住周围点击。
///
/// 不用系统 [SnackBar]（全宽实心底 + 默认 4 秒 + 命中区域过大）。
void showGlassSnackBar(
  BuildContext context,
  String message, {
  GlassSnackTone? tone,
  Duration duration = const Duration(milliseconds: 1600),
}) {
  // 清掉可能残留的实心 SnackBar，避免叠两层。
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

  final resolved = tone ?? inferGlassSnackTone(message);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final fg = _glassSnackForeground(dark, resolved);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: fg)),
        backgroundColor: _glassSnackTint(dark, resolved),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bottom =
          MediaQuery.paddingOf(ctx).bottom + CentliTheme.glassSnackBottomGap;
      // 只用 Positioned 包住这一条：条外区域不进命中测试，背后可点。
      return Positioned(
        left: 16,
        right: 16,
        bottom: bottom,
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: () {
              if (entry.mounted) entry.remove();
            },
            child: CentliGlass(
              borderRadius: BorderRadius.circular(14),
              blur: true,
              sigma: CentliTheme.glassSigma,
              tint: _glassSnackTint(isDark, resolved),
              borderColor: _glassSnackBorder(isDark, resolved),
              borderWidth: 1,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _glassSnackForeground(isDark, resolved),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  Future<void>.delayed(duration, () {
    if (entry.mounted) entry.remove();
  });
}

/// [PopupMenuButton] 的毛玻璃替代：三点 / 自定义 child 都可。
class CentliGlassPopupButton<T> extends StatelessWidget {
  const CentliGlassPopupButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = const Icon(Icons.more_vert),
    this.tooltip,
    this.child,
    this.alignEnd = true,
    this.enabled = true,
    this.minWidth = 148,
    this.maxWidth = 280,
  });

  final List<CentliMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget? icon;
  final String? tooltip;
  final Widget? child;
  final bool alignEnd;
  final bool enabled;
  final double minWidth;
  final double maxWidth;

  Future<void> _open(BuildContext anchorContext) async {
    if (!enabled || items.isEmpty) return;
    final value = await showGlassMenu<T>(
      context: anchorContext,
      anchorContext: anchorContext,
      items: items,
      alignEnd: alignEnd,
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorCtx) {
        if (child != null) {
          final tap = InkWell(
            onTap: enabled ? () => _open(anchorCtx) : null,
            borderRadius: BorderRadius.circular(20),
            child: child,
          );
          if (tooltip == null || tooltip!.isEmpty) return tap;
          return Tooltip(message: tooltip!, child: tap);
        }
        return IconButton(
          tooltip: tooltip,
          onPressed: enabled ? () => _open(anchorCtx) : null,
          icon: icon ?? const Icon(Icons.more_vert),
        );
      },
    );
  }
}
