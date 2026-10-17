import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/db/database_provider.dart';
import '../features/ledger/bookkeeping_sheet.dart' deferred as bookkeeping;
import '../features/ledger/quick_bookkeeping_sheet.dart' deferred as quick_bk;
import 'theme.dart';

/// Flat 5-tab shell: \u9996\u9875 / \u7edf\u8ba1 / \u8bb0\u8d26(+) / \u8d44\u4ea7 / \u6211\u7684
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '\u9996\u9875'),
    (icon: Icons.bar_chart_outlined, selected: Icons.bar_chart_rounded, label: '\u7edf\u8ba1'),
    (icon: Icons.add_circle_outline, selected: Icons.add_circle, label: '\u8bb0\u4e00\u7b14'),
    (
      icon: Icons.account_balance_wallet_outlined,
      selected: Icons.account_balance_wallet_rounded,
      label: '\u8d44\u4ea7',
    ),
    (icon: Icons.person_outline, selected: Icons.person_rounded, label: '\u6211\u7684'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final ledgerId = ledgerAsync.valueOrNull?.id;
    final pendingCount = ledgerId == null
        ? 0
        : (ref.watch(pendingCountProvider(ledgerId)).valueOrNull ?? 0);
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Branch 2 is the placeholder for \u8bb0\u8d26; keep prior tab highlighted while sheet is open.
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
                  : i == 2
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _openQuickBookkeeping(context),
                      child: Icon(_tabs[i].icon),
                    )
                  : Icon(_tabs[i].icon),
              selectedIcon: i == 0
                  ? _PendingBadgeIcon(
                      icon: _tabs[i].selected,
                      count: pendingCount,
                    )
                  : i == 2
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () => _openQuickBookkeeping(context),
                      child: Icon(_tabs[i].selected),
                    )
                  : Icon(_tabs[i].selected),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }

  /// Load traditional manual bookkeeping sheet (deferred).
  static Future<void> _openBookkeeping(BuildContext context) async {
    await bookkeeping.loadLibrary();
    if (!context.mounted) return;
    await bookkeeping.showBookkeepingSheet(context);
  }

  static Future<void> _openQuickBookkeeping(BuildContext context) async {
    await quick_bk.loadLibrary();
    if (!context.mounted) return;
    await quick_bk.showQuickBookkeepingSheet(context);
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
