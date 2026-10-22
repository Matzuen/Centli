import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/fx.dart';
import 'centli_database.dart';

final databaseProvider = Provider<CentliDatabase>((ref) {
  final db = CentliDatabase();
  ref.onDispose(db.close);
  return db;
});

final currentLedgerIdProvider = FutureProvider<String?>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.currentLedgerId();
});

/// Live current ledger (name + baseCurrency). Prefer over id-only when
/// multi-currency display needs the base currency.
final currentLedgerProvider = StreamProvider<Ledger?>((ref) {
  return ref.watch(databaseProvider).watchCurrentLedger();
});

/// True only for explicit done markers (`true` / `1`).
/// Missing / `false` / empty → first-run guide should show.
bool isOnboardingDoneSetting(String? raw) {
  final v = raw?.trim().toLowerCase();
  return v == 'true' || v == '1' || v == 'yes';
}

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('onboarding_done');
  return isOnboardingDoneSetting(v);
});

final fxBookProvider = StreamProvider<FxBook>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchFxRates().asyncMap((rows) async {
    return FxBook([
      for (final r in rows)
        FxQuote(
          day: r.day,
          fromCcy: r.fromCcy,
          toCcy: r.toCcy,
          rate: r.rate,
        ),
    ]);
  });
});

final themeModeProvider = StreamProvider<ThemeMode>((ref) {
  return ref.watch(databaseProvider).watchSetting('theme_mode').map((v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  });
});

/// Bumped when native SQLite mutates pending / transactions outside Drift
/// (悬浮窗入账、通知栏忽略等). Watchers should depend on this.
final pendingExternalWriteTickProvider = StateProvider<int>((ref) => 0);

/// Native / 下拉刷新：推 Drift stream + bump tick，让未监听 table updates 的
/// Riverpod 也能重建。
void notifyExternalSqliteWrite(
  CentliDatabase db,
  StateController<int> tick,
) {
  tick.state++;
  db.notifyExternalMutation();
}

final pendingCountProvider = StreamProvider.family<int, String>((ref, ledgerId) {
  ref.watch(pendingExternalWriteTickProvider);
  return ref.watch(databaseProvider).watchPendingCount(ledgerId);
});

/// Emits a bump whenever any transaction row for [ledgerId] may have changed.
/// Use as an invalidation signal only — never aggregate from the watched list;
/// always re-query untruncated summaries (rangeSummaryInBase / netWorthInBase / …).
final txnWriteSignalProvider = StreamProvider.family<int, String>((ref, ledgerId) {
  // Native 写库不会推 Drift stream；外部 tick 也要能打到首页汇总/流水。
  ref.watch(pendingExternalWriteTickProvider);
  var version = 0;
  return ref
      .watch(databaseProvider)
      .watchRecentTransactions(ledgerId, limit: 1)
      .map((_) => version++);
});

