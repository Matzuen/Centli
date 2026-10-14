import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/assets/account_detail_page.dart';
import '../features/assets/assets_page.dart';
import '../features/home/home_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/onboarding/splash_page.dart';
import '../features/pending/pending_page.dart';
import '../features/ledger/ledger_detail_page.dart';
import '../features/ledger/search_page.dart';
import '../features/security/app_lock_page.dart';
import '../features/settings/auto_capture_page.dart';
import '../features/settings/permission_explain_page.dart';
import '../features/settings/categories_page.dart';
import '../features/settings/me_page.dart';
import '../features/settings/export_page.dart';
import '../features/settings/import_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/privacy_policy_page.dart';
import '../features/settings/security_page.dart';
import '../features/settings/fx_rates_page.dart';
import '../features/settings/budget_page.dart';
import '../features/settings/recycle_bin_page.dart';
import '../features/settings/ledgers_page.dart';
import '../features/stats/stats_page.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createRouter({
  Listenable? refreshListenable,
  GoRouterRedirect? redirect,
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/lock',
        builder: (context, state) => const AppLockPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomePage(),
                routes: [
                  GoRoute(
                    path: 'pending',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) {
                      final tab = state.uri.queryParameters['tab'];
                      return PendingPage(initialFilter: tab);
                    },
                  ),
                  GoRoute(
                    path: 'search',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SearchPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsPage(),
              ),
            ],
          ),
          // Center + tab — placeholder branch so indices align (0..4)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ledger/new',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/assets',
                builder: (context, state) => const AssetsPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return AccountDetailPage(accountId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MePage(),
                routes: [
                  GoRoute(
                    path: 'categories',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const CategoriesPage(),
                  ),
                  GoRoute(
                    path: 'budget',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const BudgetPage(),
                  ),
                  GoRoute(
                    path: 'ledgers',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const LedgersPage(),
                  ),
                  GoRoute(
                    path: 'recycle',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const RecycleBinPage(),
                  ),
                  GoRoute(
                    path: 'auto',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AutoCapturePage(),
                  ),
                  GoRoute(
                    path: 'export',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const ExportPage(),
                  ),
                  GoRoute(
                    path: 'import',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const ImportPage(),
                  ),
                  GoRoute(
                    path: 'security',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SecurityPage(),
                  ),
                  GoRoute(
                    path: 'fx',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const FxRatesPage(),
                  ),
                  GoRoute(
                    path: 'about',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AboutPage(),
                    routes: [
                      GoRoute(
                        path: 'privacy',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const PrivacyPolicyPage(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'permission',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) {
                      final q = state.uri.queryParameters;
                      return PermissionExplainPage(
                        openSettingsOnEntry: q['open'] == '1',
                        finishOnboarding: q['onboarding'] == '1',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/ledger/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return LedgerDetailPage(transactionId: id);
        },
      ),
    ],
  );
}
