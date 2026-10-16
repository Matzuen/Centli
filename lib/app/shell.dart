import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database_provider.dart';
import '../features/ledger/bookkeeping_sheet.dart' deferred as bookkeeping;
import 'theme.dart';

/// Flat 5-tab shell: 首页 / 统计 / 记账(+) / 资产 / 我的 (Centli screenshot).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
    (icon: Icons.bar_chart_outlined, selected: Icons.bar_chart_rounded, label: '统计'),
    (icon: Icons.add_circle_outline, selected: Icons.add_circle, label: '记一笔'),
    (
      icon: Icons.account_balance_wallet_outlined,
      selected: Icons.account_balance_wallet_rounded,
      label: '资产',
    ),
    (icon: Icons.person_outline, selected: Icons.person_rounded, label: '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final ledgerId = ledgerAsync.valueOrNull?.id;
    final pendingCount = ledgerId == null
        ? 0
        : (ref.watch(pendingCountProvider(ledgerId)).valueOrNull ?? 0);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Branch 2 is the placeholder for 记账; keep prior tab highlighted while sheet is open.
    final selectedIndex = navigationShell.currentIndex == 2
        ? 0
        : navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: CentliTheme.scaffoldGradient(dark: dark),
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            _openBookkeeping(context);
            return;
          }
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: i == 0
                  ? _PendingBadgeIcon(
                      icon: _tabs[i].icon,
                      count: pendingCount,
                    )
                  : Icon(_tabs[i].icon),
              selectedIcon: i == 0
                  ? _PendingBadgeIcon(
                      icon: _tabs[i].selected,
                      count: pendingCount,
                    )
                  : Icon(_tabs[i].selected),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }

  /// Load speech / LLM bookkeeping code only when the user opens 记账.
  static Future<void> _openBookkeeping(BuildContext context) async {
    await bookkeeping.loadLibrary();
    if (!context.mounted) return;
    await bookkeeping.showBookkeepingSheet(context);
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
