import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/fx/fx_remote_service.dart';
import '../recurring/recurring_runner.dart';
import '../../app/deep_link.dart';
import '../security/app_lock_controller.dart';
import '../../app/theme.dart';

/// Cold-start splash: brand mark + open DB / read settings, then route.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final db = ref.read(databaseProvider);
    // Parallel settings reads; first touch also opens Drift (LazyDatabase).
    final done = await db.getSetting('onboarding_done');

    // FX + ledger lookup are not needed to choose the first route — defer.
    unawaited(_scheduleFxDeferred(db));
    unawaited(_scheduleRecurringDeferred(db));

    final elapsed = DateTime.now().difference(started);
    // Keep a short brand beat without padding slow boots further.
    const minShow = Duration(milliseconds: 400);
    if (elapsed < minShow) {
      await Future<void>.delayed(minShow - elapsed);
    }
    if (!mounted) return;
    // 资产锁只藏金额，进 App 不再拦全屏解锁。
    ref.read(appLockUnlockedProvider.notifier).unlock();
    ref.read(amountsRevealedProvider.notifier).conceal();
    if (done == 'true') {
      final deep = PendingDeepLink.take();
      context.go(deep ?? '/home');
    } else {
      // Keep PendingDeepLink until onboarding finishes — do not take() here.
      context.go('/onboarding');
    }
  }

  Future<void> _scheduleFxDeferred(CentliDatabase db) async {
    try {
      final ledgerId = await db.currentLedgerId();
      var base = 'CNY';
      if (ledgerId != null) {
        final ledger = await db.getLedger(ledgerId);
        if (ledger != null) base = ledger.baseCurrency;
      }
      scheduleFxAutoRefresh(db, base);
    } catch (_) {
      scheduleFxAutoRefresh(db, 'CNY');
    }
  }
  Future<void> _scheduleRecurringDeferred(CentliDatabase db) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await runDueRecurring(db);
    } catch (_) {
      // Never block splash / crash on recurring catch-up.
    }
  }


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 48,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose + CentliSpacing.item),
              Text(
                'Centli',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: CentliSpacing.item),
              Text(
                'Centli · 厘清资产，安心记账',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
