import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

import '../features/assets/account_detail_page.dart';
import '../features/assets/assets_page.dart';
import '../features/assets/asset_types_page.dart';
import '../features/home/home_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/onboarding/splash_page.dart';
import '../features/pending/pending_page.dart';
import '../features/ledger/ledger_detail_page.dart';
import '../features/ledger/search_page.dart';
import '../features/settings/auto_capture_page.dart';
import '../features/settings/manual_capture_help_page.dart';
import '../features/settings/recognition_rules_page.dart';
import '../features/settings/recognition_rule_edit_page.dart';
import '../features/settings/smart_fill_settings_page.dart';
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
import '../features/recurring/recurring_list_page.dart';
import '../features/recurring/recurring_wizard_page.dart';
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
    overridePlatformDefaultLocation: true,
    refreshListenable: refreshListenable,
    redirect: redirect,
    errorBuilder: (context, state) => const _UnknownRoutePage(),
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
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
                      final focus = state.uri.queryParameters['focus'];
                      final review =
                          state.uri.queryParameters['review'] == '1';
                      return PendingPage(
                        initialFilter: tab,
                        focusPendingId: focus,
                        openConfirm: review || focus != null,
                      );
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
                    path: 'types',
                    builder: (context, state) => const AssetTypesPage(),
                  ),
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
                    path: 'recurring',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const RecurringListPage(),
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) {
                          final extra = state.extra;
                          return RecurringWizardPage(
                            args: extra is RecurringWizardArgs ? extra : null,
                          );
                        },
                      ),
                    ],
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
                    routes: [
                      GoRoute(
                        path: 'manual-help',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const ManualCaptureHelpPage(),
                      ),
                      GoRoute(
                        path: 'rules',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) =>
                            const RecognitionRulesPage(),
                        routes: [
                          GoRoute(
                            path: 'edit',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) {
                              final id = state.uri.queryParameters['id'];
                              return RecognitionRuleEditPage(ruleId: id);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'smart-fill',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SmartFillSettingsPage(),
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

/// Friendly unknown-route page — never surfaces raw GoException to users.
class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliGradientScaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 64,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: CentliSpacing.sectionLoose),
                Text(
                  '页面不存在',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                Text(
                  '这个地址打不开，回首页继续记账吧',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.sectionLoose + CentliSpacing.item),
                FilledButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('回首页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
