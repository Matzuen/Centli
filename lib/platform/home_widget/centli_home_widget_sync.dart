import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/utils/date_range.dart';
import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';

/// P3 Android home-screen widget sync (today expense + pending count).
///
/// Native UI: [CentliHomeWidgetProvider]. Data keys are written to the
/// SharedPreferences bridge used by `home_widget`.
abstract final class CentliHomeWidgetSync {
  static const androidProviderName = 'CentliHomeWidgetProvider';
  static const androidQualifiedName =
      'com.centli.centli.CentliHomeWidgetProvider';

  static const keyExpenseLabel = 'expense_label';
  static const keyExpenseValue = 'expense_value';
  static const keyPendingLabel = 'pending_label';
  static const keyPendingValue = 'pending_value';
  static const keySubtitle = 'subtitle';
  static const keyHasPending = 'has_pending';

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Push latest today-expense / pending snapshot and request a redraw.
  static Future<void> sync(CentliDatabase db) async {
    if (!supported) return;
    try {
      final ledgerId = await db.currentLedgerId();
      final ledger = ledgerId == null ? null : await db.getLedger(ledgerId);
      if (ledger == null) {
        await _writePlaceholder();
        await _update();
        return;
      }

      // 资产锁开启时小组件始终藏金额（会话内「开眼」不写回设置）。
      final hide = (await db.getSetting('app_lock')) == 'true';
      final today = DateRangeWindow.lastDays(days: 1);
      final summary = await db.rangeSummaryInBase(
        ledger.id,
        today.startMs,
        today.endMs,
        ledger.baseCurrency,
      );
      final pending = await db.watchPendingCount(ledger.id).first;

      final expenseText = formatMinor(
        ledger.baseCurrency,
        summary.expenseMinor,
        hide: hide,
      );
      final pendingText = pending > 0 ? '$pending' : '0';
      const pendingLabel = '\u5f85\u786e\u8ba4';
      final subtitle =
          pending > 0 ? '\u70b9\u6309\u67e5\u770b\u5f85\u786e\u8ba4' : '\u70b9\u6309\u6253\u5f00\u5398\u8bb0';

      await HomeWidget.saveWidgetData<String>(
          keyExpenseLabel, '\u4eca\u65e5\u652f\u51fa');
      await HomeWidget.saveWidgetData<String>(keyExpenseValue, expenseText);
      await HomeWidget.saveWidgetData<String>(keyPendingLabel, pendingLabel);
      await HomeWidget.saveWidgetData<String>(keyPendingValue, pendingText);
      await HomeWidget.saveWidgetData<String>(keySubtitle, subtitle);
      await HomeWidget.saveWidgetData<String>(
        keyHasPending,
        pending > 0 ? '1' : '0',
      );
      await _update();
    } catch (e, st) {
      debugPrint('CentliHomeWidgetSync.sync failed: $e\n$st');
    }
  }

  static Future<void> _writePlaceholder() async {
    await HomeWidget.saveWidgetData<String>(
        keyExpenseLabel, '\u4eca\u65e5\u652f\u51fa');
    await HomeWidget.saveWidgetData<String>(keyExpenseValue, '--');
    await HomeWidget.saveWidgetData<String>(
        keyPendingLabel, '\u5f85\u786e\u8ba4');
    await HomeWidget.saveWidgetData<String>(keyPendingValue, '0');
    await HomeWidget.saveWidgetData<String>(
        keySubtitle, '\u6253\u5f00 App \u521d\u59cb\u5316\u8d26\u672c');
    await HomeWidget.saveWidgetData<String>(keyHasPending, '0');
  }

  static Future<void> _update() async {
    await HomeWidget.updateWidget(
      name: androidProviderName,
      androidName: androidProviderName,
      qualifiedAndroidName: androidQualifiedName,
    );
  }

  /// Best-effort pin prompt (Android 8+); returns false if unsupported.
  static Future<bool> requestPin() async {
    if (!supported) return false;
    try {
      final ok = await HomeWidget.isRequestPinWidgetSupported() ?? false;
      if (!ok) return false;
      await HomeWidget.requestPinWidget(
        name: androidProviderName,
        androidName: androidProviderName,
        qualifiedAndroidName: androidQualifiedName,
      );
      return true;
    } catch (e, st) {
      debugPrint('CentliHomeWidgetSync.requestPin failed: $e\n$st');
      return false;
    }
  }

  /// Map widget launch URI path to in-app route.
  static String? routeForUri(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host;
    final path = uri.path;
    if (host == 'pending' || path == '/pending' || path.endsWith('pending')) {
      return '/home/pending';
    }
    if (host == 'home' || path == '/home' || path.isEmpty || path == '/') {
      return '/home';
    }
    return '/home';
  }
}
