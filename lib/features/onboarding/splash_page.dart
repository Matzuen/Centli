import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database_provider.dart';
import '../../data/fx/fx_remote_service.dart';
import '../security/app_lock_controller.dart';

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
    // Touch DB so onCreate + seedDefaults run before first home paint.
    final done = await db.getSetting('onboarding_done');
    final lockOn = (await db.getSetting('app_lock')) == 'true';
    // P3: once-per-day remote FX (non-blocking; failures ignored).
    final ledgerId = await db.currentLedgerId();
    var base = 'CNY';
    if (ledgerId != null) {
      final ledger = await db.getLedger(ledgerId);
      if (ledger != null) base = ledger.baseCurrency;
    }
    scheduleFxAutoRefresh(db, base);
    final elapsed = DateTime.now().difference(started);
    const minShow = Duration(milliseconds: 900);
    if (elapsed < minShow) {
      await Future<void>.delayed(minShow - elapsed);
    }
    if (!mounted) return;
    if (done == 'true') {
      if (lockOn) {
        ref.read(appLockUnlockedProvider.notifier).lock();
        context.go('/lock');
      } else {
        ref.read(appLockUnlockedProvider.notifier).unlock();
        context.go('/home');
      }
    } else {
      context.go('/onboarding');
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
              const SizedBox(height: 24),
              Text(
                'Centli',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Centli · 厘清每一笔账单',
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
