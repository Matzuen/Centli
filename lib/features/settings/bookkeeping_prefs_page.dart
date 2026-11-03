import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/constants/pref_keys.dart';
import '../../data/db/database_provider.dart';

final _prefBoolProvider =
    StreamProvider.family<bool, ({String key, bool defaultOn})>((ref, args) {
  return ref
      .watch(databaseProvider)
      .watchSetting(args.key)
      .map((raw) => prefBool(raw, defaultOn: args.defaultOn));
});

/// 记账偏好二级页：从「我的」设置入口进入，开关逻辑与原先主页内联一致。
class BookkeepingPrefsPage extends ConsumerWidget {
  const BookkeepingPrefsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('记账偏好')),
      body: ListView(
        padding: CentliSpacing.pagePadding,
        children: [
          CentliSoftCard(
            child: Column(
              children: [
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.homeShowBudgetCard,
                  title: '首页显示预算卡',
                  subtitle: '概览卡片下方的本月预算进度',
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.homeTxnPreview,
                  title: '首页流水仅预览',
                  subtitle: '开：约 6 条；关：当前区间全量',
                  defaultOn: true,
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.homeTrendExpanded,
                  title: '首页趋势默认展开',
                  subtitle: '关：折叠（默认）；开：进入即看净资产曲线',
                  defaultOn: false,
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.budgetWarnNotify,
                  title: '预算进度预警',
                  subtitle: '用到约 80% 时本地提醒一次（可关闭）',
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.rememberCategoryAccount,
                  title: '记忆分类对应账户',
                  subtitle: '选分类时回填该分类上次资产账户',
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.rememberCategoryNote,
                  title: '记忆分类对应备注',
                  subtitle: '选分类时回填该分类上次备注',
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.confirmBeforeDelete,
                  title: '删除前确认',
                  subtitle: '长按流水删除时弹出确认',
                ),
                const Divider(height: 1),
                _prefSwitch(
                  context,
                  ref,
                  key: PrefKeys.recycleAutoPurge,
                  title: '回收站自动清理',
                  subtitle: '启动时永久删除超过 30 天的记录',
                ),
              ],
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
        ],
      ),
    );
  }

  Widget _prefSwitch(
    BuildContext context,
    WidgetRef ref, {
    required String key,
    required String title,
    String? subtitle,
    VoidCallback? onChangedExtra,
    bool defaultOn = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final on = ref
            .watch(_prefBoolProvider((key: key, defaultOn: defaultOn)))
            .valueOrNull ??
        defaultOn;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
      value: on,
      onChanged: (v) async {
        await ref.read(databaseProvider).setSetting(key, v ? 'true' : 'false');
        onChangedExtra?.call();
      },
    );
  }
}
