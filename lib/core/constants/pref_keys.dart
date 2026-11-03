/// App settings keys（`app_settings` / Drift getSetting·setSetting）。
///
/// 布尔开关：缺省视为 [defaultOn]（未写入时保持旧行为）。
abstract final class PrefKeys {
  /// 首页是否展示预算进度条。默认开。
  static const homeShowBudgetCard = 'home_show_budget_card';

  /// 预算进度到约 80% 时发本地通知。默认开。
  static const budgetWarnNotify = 'budget_warn_notify';

  /// 选分类时自动回填该分类上次使用的资产账户。默认开。
  static const rememberCategoryAccount = 'remember_category_account';

  /// 选分类时自动回填该分类上次备注。默认开。
  static const rememberCategoryNote = 'remember_category_note';

  /// 删除流水前是否弹确认（列表长按删除）。默认开。
  static const confirmBeforeDelete = 'confirm_before_delete';

  /// 打开 App 时自动清理回收站超过 30 天的记录。默认开。
  static const recycleAutoPurge = 'recycle_auto_purge';

  /// 本地自动备份目录（系统目录选择 / SAF 返回的路径）。
  static const backupDir = 'backup_dir';

  /// 自动备份频率：off / daily / weekly / monthly。默认 off。
  static const backupFrequency = 'backup_frequency';

  /// 上次成功备份时间（UTC ISO8601）。
  static const backupLastOkAt = 'backup_last_ok_at';

  /// 上次自动/手动备份失败原因（成功时清空）。
  static const backupLastError = 'backup_last_error';

  /// 是否已展示过首次备份引导（或已进入过备份设置）。
  static const backupPromptSeen = 'backup_prompt_seen';

  /// 某预算在本周期已发过 80% 预警：`budget_warn_sent:{ledgerId}:{yyyy-MM}:{categoryId}`。
  /// [categoryId] 为空字符串表示月度总额预算。
  static String budgetWarnSentKey({
    required String ledgerId,
    required String yearMonth,
    required String categoryId,
  }) =>
      'budget_warn_sent:$ledgerId:$yearMonth:$categoryId';
}

bool prefBool(String? raw, {bool defaultOn = true}) {
  if (raw == null || raw.trim().isEmpty) return defaultOn;
  final t = raw.trim().toLowerCase();
  if (t == 'true' || t == '1' || t == 'yes') return true;
  if (t == 'false' || t == '0' || t == 'no') return false;
  return defaultOn;
}
