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

final hideAmountProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchHideAmount();
});

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('onboarding_done');
  return v == 'true';
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
