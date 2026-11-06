import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database_provider.dart';
import '../features/ledger/bookkeeping_sheet.dart' deferred as bookkeeping;
import '../features/ledger/quick_bookkeeping_sheet.dart' deferred as quick_bk;
import 'theme.dart';
import '../core/widgets/glass.dart';

/// Flat shell: 首页 / 统计 / 记一笔 pill / 资产 / 我的
/// 中央「+ 记一笔」短按手记 sheet、长按快记；非 NavigationBar 假 Tab 图标。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Load traditional manual bookkeeping sheet (deferred).
  static Future<void> openBookkeeping(BuildContext context) async {
    await bookkeeping.loadLibrary();
    if (!context.mounted) return;
    await bookkeeping.showBookkeepingSheet(context);
  }

  static Future<void> openQuickBookkeeping(BuildContext context) async {
    await quick_bk.loadLibrary();
    if (!context.mounted) return;
    await quick_bk.showQuickBookkeepingSheet(context);
  }

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  DateTime? _lastBackAt;

  void _onRootBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    showGlassSnackBar(
      context,
      '再按一次退出应用',
      tone: GlassSnackTone.warning,
      duration: const Duration(seconds: 2),
    );
  }

  void _goBranch(int branchIndex) {
    widget.navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final ledgerId = ledgerAsync.valueOrNull?.id;
    final pendingCount = ledgerId == null
        ? 0
        : (ref.watch(pendingCountProvider(ledgerId)).valueOrNull ?? 0);
    // Branch 2 is the placeholder for 记一笔; keep prior tab highlighted while sheet is open.
    final rawIndex = navigationShell.currentIndex;
    final selectedBranch = rawIndex == 2 ? 0 : rawIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onRootBack();
      },
      child: CentliGradientScaffold(
        // 内容延伸到底栏后方，BackdropFilter 才能采到页面内容。
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: _CentliMainBar(
          selectedBranch: selectedBranch,
          pendingCount: pendingCount,
          onBranch: _goBranch,
          onBookkeeping: () => AppShell.openBookkeeping(context),
          onBookkeepingLongPress: () => AppShell.openQuickBookkeeping(context),
        ),
      ),
    );
  }
}

/// 五槽底栏：首页 · 统计 · 记一笔 pill · 资产 · 我的（路由分支仍为 0/1/2占位/3/4）。
class _CentliMainBar extends StatelessWidget {
  const _CentliMainBar({
    required this.selectedBranch,
    required this.pendingCount,
    required this.onBranch,
    required this.onBookkeeping,
    required this.onBookkeepingLongPress,
  });

  final int selectedBranch;
  final int pendingCount;
  final ValueChanged<int> onBranch;
  final VoidCallback onBookkeeping;
  final VoidCallback onBookkeepingLongPress;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final left = MediaQuery.paddingOf(context).left;
    final right = MediaQuery.paddingOf(context).right;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: CentliGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        blur: true,
        sigma: CentliTheme.glassSigma,
        tint: CentliTheme.glassNavTint(context),
        borderColor: CentliTheme.glassBorder(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: EdgeInsets.only(
                  left: left > 2 ? left : 2,
                  right: right > 2 ? right : 2,
                ),
                child: Row(
                  children: [
                    _TabItem(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: '首页',
                      selected: selectedBranch == 0,
                      onTap: () => onBranch(0),
                      badge: pendingCount,
                    ),
                    _TabItem(
                      icon: Icons.bar_chart_outlined,
                      selectedIcon: Icons.bar_chart_rounded,
                      label: '统计',
                      selected: selectedBranch == 1,
                      onTap: () => onBranch(1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 9,
                      ),
                      child: _BookkeepingPill(
                        onTap: onBookkeeping,
                        onLongPress: onBookkeepingLongPress,
                      ),
                    ),
                    _TabItem(
                      icon: Icons.account_balance_wallet_outlined,
                      selectedIcon: Icons.account_balance_wallet_rounded,
                      label: '资产',
                      selected: selectedBranch == 3,
                      onTap: () => onBranch(3),
                    ),
                    _TabItem(
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person_rounded,
                      label: '我的',
                      selected: selectedBranch == 4,
                      onTap: () => onBranch(4),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: bottom > 0 ? bottom : 6),
          ],
        ),
      ),
    );
  }
}

class _BookkeepingPill extends StatelessWidget {
  const _BookkeepingPill({
    required this.onTap,
    required this.onLongPress,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: CentliTheme.brandGrad(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: CentliTheme.brandPrimary.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 2),
                Text(
                  '记一笔',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? CentliTheme.brandPrimary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : ''),
              child: Icon(
                selected ? selectedIcon : icon,
                size: 22,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
