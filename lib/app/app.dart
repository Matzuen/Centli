import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import '../core/utils/date_range.dart';
import '../data/db/database_provider.dart';
import '../features/security/app_lock_controller.dart';
import '../platform/home_widget/centli_home_widget_sync.dart';
import '../platform/notifications/notification_ingest_bridge.dart';
import '../platform/pending/pending_capture_intake.dart';
import '../platform/notifications/noti_template_store.dart';
import '../platform/notifications/notification_listener_stub.dart';
import 'router.dart';
import 'theme.dart';

class CentliApp extends ConsumerStatefulWidget {
  const CentliApp({super.key});

  @override
  ConsumerState<CentliApp> createState() => _CentliAppState();
}

class _CentliAppState extends ConsumerState<CentliApp> {
  GoRouter? _router;
  final _RouterRefresh _refresh = _RouterRefresh();
  bool _bridgeStarted = false;
  AppLifecycleListener? _lifecycle;
  bool _wasBackgrounded = false;
  StreamSubscription<Uri?>? _widgetClickSub;
  StreamSubscription<int>? _pendingCountSub;
  StreamSubscription<dynamic>? _todayTxSub;
  String? _pendingWatchLedgerId;

  @override
  void initState() {
    super.initState();
    _router = createRouter(
      refreshListenable: _refresh,
      redirect: _redirect,
    );
    NotificationCaptureStub.onOpenRoute = _onOpenRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureBridge());
    _lifecycle = AppLifecycleListener(
      onStateChange: _onLifecycle,
    );
    _listenWidgetClicks();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _refresh.dispose();
    _widgetClickSub?.cancel();
    _pendingCountSub?.cancel();
    _todayTxSub?.cancel();
    if (NotificationCaptureStub.onOpenRoute == _onOpenRoute) {
      NotificationCaptureStub.onOpenRoute = null;
    }
    super.dispose();
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_wasBackgrounded) return;
    _wasBackgrounded = false;
    _relockIfNeeded();
    unawaited(_syncHomeWidget());
  }

  Future<void> _relockIfNeeded() async {
    final router = _router;
    if (router == null) return;
    final enabled = await ref.read(databaseProvider).getSetting('app_lock');
    if (enabled != 'true') return;
    final unlocked = ref.read(appLockUnlockedProvider);
    if (!unlocked) return;
    ref.read(appLockUnlockedProvider.notifier).lock();
    final loc = router.state.uri.path;
    if (loc == '/lock' || loc == '/splash' || loc == '/onboarding') return;
    router.go('/lock');
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final path = state.uri.path;
    if (path == '/splash' || path == '/onboarding' || path == '/lock') {
      return null;
    }
    final lockAsync = ref.read(appLockEnabledProvider);
    final lockOn = lockAsync.valueOrNull;
    // While loading, do not bounce; splash already gates cold start.
    if (lockOn != true) return null;
    final unlocked = ref.read(appLockUnlockedProvider);
    if (!unlocked) return '/lock';
    return null;
  }

  void _onOpenRoute(String route, String? pendingId) {
    final router = _router;
    if (router == null) return;
    // Local-push tap → pending list (pendingId reserved for future scroll-to).
    final lockOn = ref.read(appLockEnabledProvider).valueOrNull ?? false;
    final unlocked = ref.read(appLockUnlockedProvider);
    if (lockOn && !unlocked) {
      router.go('/lock');
      return;
    }
    router.go(route);
  }

  Future<void> _ensureBridge() async {
    if (_bridgeStarted || !mounted) return;
    _bridgeStarted = true;
    final db = ref.read(databaseProvider);
    // Templates are loaded lazily on first capture (ingestRaw / parse).
    // Preload in background so cold start is not blocked on JSON/disk I/O.
    unawaited(NotiTemplateStore.load());
    // Bind native channels promptly, but do not await home-widget I/O here.
    await NotificationIngestBridge.start(db);
    await PendingCaptureIntake.start(
      db,
      navigate: (route) {
        final router = _router;
        if (router == null) return;
        final lockOn = ref.read(appLockEnabledProvider).valueOrNull ?? false;
        final unlocked = ref.read(appLockUnlockedProvider);
        if (lockOn && !unlocked) {
          router.go('/lock');
          return;
        }
        router.go(route);
      },
    );
    // Widget sync after first frame path — lower priority than first route.
    unawaited(_syncHomeWidget());
    unawaited(_handleInitialWidgetLaunch());
  }

  Future<void> _syncHomeWidget() async {
    if (!CentliHomeWidgetSync.supported) return;
    final db = ref.read(databaseProvider);
    await CentliHomeWidgetSync.sync(db);
    await _ensurePendingWatch();
  }

  Future<void> _ensurePendingWatch() async {
    if (!CentliHomeWidgetSync.supported) return;
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null) {
      await _pendingCountSub?.cancel();
      await _todayTxSub?.cancel();
      _pendingCountSub = null;
      _todayTxSub = null;
      _pendingWatchLedgerId = null;
      return;
    }
    if (_pendingWatchLedgerId == ledgerId &&
        _pendingCountSub != null &&
        _todayTxSub != null) {
      return;
    }
    await _pendingCountSub?.cancel();
    await _todayTxSub?.cancel();
    _pendingWatchLedgerId = ledgerId;
    final today = DateRangeWindow.lastDays(days: 1);
    _pendingCountSub = db.watchPendingCount(ledgerId).listen((_) {
      unawaited(CentliHomeWidgetSync.sync(db));
    });
    _todayTxSub = db
        .watchTransactionsInRange(ledgerId, today.startMs, today.endMs)
        .listen((_) {
      unawaited(CentliHomeWidgetSync.sync(db));
    });
  }

  Future<void> _handleInitialWidgetLaunch() async {
    if (!CentliHomeWidgetSync.supported) return;
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      final route = CentliHomeWidgetSync.routeForUri(uri);
      if (route != null) {
        _onOpenRoute(route, null);
      }
    } catch (e, st) {
      debugPrint('widget initial launch: $e\n$st');
    }
  }

  void _listenWidgetClicks() {
    if (!CentliHomeWidgetSync.supported) return;
    try {
      _widgetClickSub = HomeWidget.widgetClicked.listen((uri) {
        final route = CentliHomeWidgetSync.routeForUri(uri);
        if (route != null) {
          _onOpenRoute(route, null);
        }
        unawaited(_syncHomeWidget());
      });
    } catch (e, st) {
      debugPrint('widget click listen: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(appLockEnabledProvider, (previous, next) {
      _refresh.ping();
    });
    ref.listen<bool>(appLockUnlockedProvider, (previous, next) {
      _refresh.ping();
    });
    ref.listen(currentLedgerProvider, (previous, next) {
      unawaited(_syncHomeWidget());
    });
    ref.listen(hideAmountProvider, (previous, next) {
      unawaited(_syncHomeWidget());
    });
    ref.watch(appLockEnabledProvider);
    ref.watch(appLockUnlockedProvider);

    final router = _router;
    if (router == null) {
      return const SizedBox.shrink();
    }

    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Centli',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: CentliTheme.light(),
      darkTheme: CentliTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

/// Notifies [GoRouter] when Riverpod lock state flips.
class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}
