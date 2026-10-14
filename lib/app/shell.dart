import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database_provider.dart';
import '../features/ledger/bookkeeping_sheet.dart';
import '../features/pending/pending_page.dart';

/// 5-tab shell with Home pending-count badge (P1).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_outlined, selected: Icons.home, label: '首页'),
    (icon: Icons.bar_chart_outlined, selected: Icons.bar_chart, label: '统计'),
    (icon: Icons.add_circle_outline, selected: Icons.add_circle, label: '记账'),
    (icon: Icons.account_balance_wallet_outlined,
        selected: Icons.account_balance_wallet,
        label: '资产'),
    (icon: Icons.person_outline, selected: Icons.person, label: '我的'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final ledgerId = ledgerAsync.valueOrNull?.id;
    final pendingCount = ledgerId == null
        ? 0
        : (ref.watch(pendingCountProvider(ledgerId)).valueOrNull ?? 0);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            showBookkeepingSheet(context);
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
