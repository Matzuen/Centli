/// App settings keys（`app_settings` / Drift getSetting·setSetting）。
///
/// 布尔开关：缺省视为 [defaultOn]（未写入时保持旧行为）。
abstract final class PrefKeys {
  /// 首页是否展示预算进度条。默认开。
  static const homeShowBudgetCard = 'home_show_budget_card';

  /// 选分类时自动回填该分类上次使用的资产账户。默认开。
  static const rememberCategoryAccount = 'remember_category_account';

  /// 选分类时自动回填该分类上次备注。默认开。
  static const rememberCategoryNote = 'remember_category_note';

  /// 删除流水前是否弹确认（列表长按删除）。默认开。
  static const confirmBeforeDelete = 'confirm_before_delete';

  /// 打开 App 时自动清理回收站超过 30 天的记录。默认开。
  static const recycleAutoPurge = 'recycle_auto_purge';
}

bool prefBool(String? raw, {bool defaultOn = true}) {
  if (raw == null || raw.trim().isEmpty) return defaultOn;
  final t = raw.trim().toLowerCase();
  if (t == 'true' || t == '1' || t == 'yes') return true;
  if (t == 'false' || t == '0' || t == 'no') return false;
  return defaultOn;
}
