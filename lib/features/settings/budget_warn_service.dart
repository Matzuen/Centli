import '../../core/constants/pref_keys.dart';
import '../../core/utils/budget_progress_style.dart';
import '../../data/db/centli_database.dart';
import '../../platform/notifications/notification_listener_stub.dart';

/// 预算前置预警：进度到约 80% 发一次本地通知；按账本+周期+分类去重。
class BudgetWarnService {
  BudgetWarnService({
    required this.db,
    Future<void> Function({
      required int notifId,
      required String title,
      required String body,
    })? showNotify,
  }) : showNotify = showNotify ??
            (({required int notifId,
                required String title,
                required String body}) =>
                NotificationCaptureStub.showBudgetWarn(
                  notifId: notifId,
                  title: title,
                  body: body,
                ));

  final CentliDatabase db;
  final Future<void> Function({
    required int notifId,
    required String title,
    required String body,
  }) showNotify;

  /// 检查 [progress] 中已设额度的总预算与分类预算；仅对当前自然月触发。
  Future<void> evaluate({
    required String ledgerId,
    required MonthBudgetProgress progress,
  }) async {
    if (ledgerId.isEmpty) return;
    // 历史月份浏览不打扰。
    if (progress.yearMonth != budgetYearMonth()) return;

    final enabled = prefBool(await db.getSetting(PrefKeys.budgetWarnNotify));
    if (!enabled) return;

    final totalLimit = progress.totalLimitMinor;
    if (totalLimit != null && totalLimit > 0) {
      await _maybeWarn(
        ledgerId: ledgerId,
        yearMonth: progress.yearMonth,
        categoryId: '',
        label: '月度总预算',
        limitMinor: totalLimit,
        spentMinor: progress.spentTotalMinor,
      );
    }
    for (final c in progress.categories) {
      if (c.limitMinor <= 0) continue;
      await _maybeWarn(
        ledgerId: ledgerId,
        yearMonth: progress.yearMonth,
        categoryId: c.categoryId,
        label: c.name,
        limitMinor: c.limitMinor,
        spentMinor: c.spentMinor,
      );
    }
  }

  Future<void> _maybeWarn({
    required String ledgerId,
    required String yearMonth,
    required String categoryId,
    required String label,
    required int limitMinor,
    required int spentMinor,
  }) async {
    final ratio = spentMinor / limitMinor;
    if (ratio < BudgetProgressStyle.notifyAt) return;

    final key = PrefKeys.budgetWarnSentKey(
      ledgerId: ledgerId,
      yearMonth: yearMonth,
      categoryId: categoryId,
    );
    final sent = await db.getSetting(key);
    if (sent != null && sent.trim().isNotEmpty) return;

    final pct = (ratio * 100).clamp(0, 999).toStringAsFixed(0);
    final title = '预算预警';
    final body = categoryId.isEmpty
        ? '本月总预算已用约 $pct%，请留意开支'
        : '「$label」预算已用约 $pct%，请留意开支';
    final notifId = key.hashCode & 0x7fffffff;
    await showNotify(notifId: notifId, title: title, body: body);
    await db.setSetting(key, DateTime.now().toUtc().toIso8601String());
  }
}
