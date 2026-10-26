import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database_provider.dart';
import '../features/ledger/bookkeeping_sheet.dart' deferred as bookkeeping;
import '../features/ledger/quick_bookkeeping_sheet.dart' deferred as quick_bk;
import 'theme.dart';
import '../core/widgets/glass.dart';

/// Flat 5-tab shell: 首页 / 统计 / 记账(+) / 资产 / 我的
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
    (
      icon: Icons.bar_chart_outlined,
      selected: Icons.bar_chart_rounded,
      label: '统计',
    ),
    (icon: Icons.add_circle_outline, selected: Icons.add_circle, label: '记一笔'),
    (
      icon: Icons.account_balance_wallet_outlined,
      selected: Icons.account_balance_wallet_rounded,
      label: '资产',
    ),
    (icon: Icons.person_outline, selected: Icons.person_rounded, label: '我的'),
  ];

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
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('再按一次退出应用'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
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
    final selectedIndex = navigationShell.currentIndex == 2
        ? 0
        : navigationShell.currentIndex;

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
        bottomNavigationBar: CentliGlass(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          blur: true,
          sigma: CentliTheme.glassSigma,
          tint: CentliTheme.glassNavTint(context),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              if (index == 2) {
                AppShell.openBookkeeping(context);
                return;
              }
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: [
              for (var i = 0; i < AppShell._tabs.length; i++)
                NavigationDestination(
                  icon: i == 0
                      ? _PendingBadgeIcon(
                          icon: AppShell._tabs[i].icon,
                          count: pendingCount,
                        )
                      : i == 2
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () =>
                              AppShell.openQuickBookkeeping(context),
                          child: Icon(AppShell._tabs[i].icon),
                        )
                      : Icon(AppShell._tabs[i].icon),
                  selectedIcon: i == 0
                      ? _PendingBadgeIcon(
                          icon: AppShell._tabs[i].selected,
                          count: pendingCount,
                        )
                      : i == 2
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () =>
                              AppShell.openQuickBookkeeping(context),
                          child: Icon(AppShell._tabs[i].selected),
                        )
                      : Icon(AppShell._tabs[i].selected),
                  label: AppShell._tabs[i].label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingBadgeIcon extends StatelessWidget {
  const _PendingBadgeIcon({required this.icon, required this.count});
  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: Icon(icon),
    );
  }
}
