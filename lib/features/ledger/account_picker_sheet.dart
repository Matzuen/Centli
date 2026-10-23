import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/glass.dart';
import '../../data/db/centli_database.dart';

/// Sentinel left-rail id：展示全部资产账户（不按类型过滤）。
const kAccountPickerAllTab = '__all__';

/// Finch 式资产账户选择：左侧「全部」+ 资产类型，右侧图标网格（对齐分类选择）。
Future<String?> showAccountPickerSheet(
  BuildContext context, {
  required List<Account> accounts,
  List<AssetType> assetTypes = const [],
  String? selectedId,
  String title = '选择资产账户',
}) {
  return showGlassSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AccountPickerBody(
      accounts: accounts,
      assetTypes: assetTypes,
      selectedId: selectedId,
      title: title,
    ),
  );
}

class _AccountPickerBody extends StatefulWidget {
  const _AccountPickerBody({
    required this.accounts,
    required this.assetTypes,
    required this.title,
    this.selectedId,
  });

  final List<Account> accounts;
  final List<AssetType> assetTypes;
  final String title;
  final String? selectedId;

  @override
  State<_AccountPickerBody> createState() => _AccountPickerBodyState();
}

class _AccountPickerBodyState extends State<_AccountPickerBody> {
  /// [kAccountPickerAllTab] or an [AssetType.id] / orphan type key.
  late String _tabId;
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _tabId = _initialTabId();
  }

  Map<String, String> get _typeNames {
    final map = <String, String>{
      for (final t in widget.assetTypes) t.id: t.name,
    };
    return map;
  }

  /// 左侧栏：全部 + 有账户的类型（按 assetTypes 排序，孤儿类型垫后）。
  List<({String id, String name})> get _tabs {
    final names = _typeNames;
    final used = <String>{};
    for (final a in widget.accounts) {
      final t = a.type.trim();
      if (t.isNotEmpty) used.add(t);
    }
    final tabs = <({String id, String name})>[
      (id: kAccountPickerAllTab, name: '全部'),
    ];
    for (final t in widget.assetTypes) {
      if (used.contains(t.id)) {
        tabs.add((id: t.id, name: t.name));
        used.remove(t.id);
      }
    }
    final orphans = used.toList()..sort();
    for (final id in orphans) {
      tabs.add((id: id, name: names[id] ?? '其他'));
    }
    return tabs;
  }

  String _initialTabId() {
    final tabs = _tabs;
    if (tabs.isEmpty) return kAccountPickerAllTab;
    final sel = widget.selectedId;
    if (sel != null) {
      for (final a in widget.accounts) {
        if (a.id != sel) continue;
        final typeId = a.type.trim();
        if (typeId.isNotEmpty && tabs.any((t) => t.id == typeId)) {
          return typeId;
        }
        break;
      }
    }
    return kAccountPickerAllTab;
  }

  List<Account> get _gridItems {
    if (_tabId == kAccountPickerAllTab) return widget.accounts;
    return widget.accounts.where((a) => a.type.trim() == _tabId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final tabs = _tabs;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: CentliSpacing.item),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await context.push('/assets/types');
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('管理'),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget.accounts.isEmpty
                ? Center(
                    child: Text(
                      '暂无资产账户',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 96,
                        child: ColoredBox(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 6,
                            ),
                            itemCount: tabs.length,
                            itemBuilder: (context, i) {
                              final tab = tabs[i];
                              final selected = tab.id == _tabId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: selected
                                      ? scheme.surface
                                      : Colors.transparent,
                                  elevation: selected ? 1.5 : 0,
                                  shadowColor:
                                      scheme.shadow.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () =>
                                        setState(() => _tabId = tab.id),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        tab.name,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? CentliTheme.softBlue
                                              : scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.2,
                          child: _gridItems.isEmpty
                              ? Center(
                                  child: Text(
                                    '该分类下暂无账户',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              : GridView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 12, 12, 24),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.65,
                                  ),
                                  itemCount: _gridItems.length,
                                  itemBuilder: (context, i) {
                                    final a = _gridItems[i];
                                    final selected = a.id == _selectedId;
                                    final archived = a.archived == 1;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () =>
                                          Navigator.pop(context, a.id),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 160),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? CentliTheme.softBlue
                                                  .withValues(alpha: 0.10)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: selected
                                                ? CentliTheme.softBlue
                                                    .withValues(alpha: 0.45)
                                                : Colors.transparent,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 6,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CentliIconChip(
                                              name: a.name,
                                              kind: 'account',
                                              iconKey: a.icon,
                                              size: 44,
                                              roundedSquare: true,
                                            ),
                                            const SizedBox(
                                              height: CentliSpacing.item,
                                            ),
                                            Text(
                                              a.name,
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.15,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: selected
                                                    ? CentliTheme.softBlue
                                                    : scheme.onSurface,
                                              ),
                                            ),
                                            if (archived)
                                              Text(
                                                '已归档',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              )
                                            else
                                              Text(
                                                currencyLabel(a.currency),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
