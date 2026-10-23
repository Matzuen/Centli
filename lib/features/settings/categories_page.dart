import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/icon_picker_sheet.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

final _categoriesProvider =
    StreamProvider.family<List<Category>, (String, String)>((ref, key) {
  final (ledgerId, kind) = key;
  return ref.watch(databaseProvider).watchCategories(ledgerId, kind);
});

final _archivedCategoriesProvider =
    StreamProvider.family<List<Category>, (String, String)>((ref, key) {
  final (ledgerId, kind) = key;
  return ref.watch(databaseProvider).watchArchivedCategories(ledgerId, kind);
});

/// Category manager: expense / income tabs, add / rename / archive / unarchive,
/// and P2 drag-to-reorder (active list only; sort_order persisted).
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  /// false = 使用中, true = 已归档
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _kind => switch (_tabs.index) {
        1 => 'in',
        2 => 'transfer',
        _ => 'out',
      };

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerIdProvider);

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: '支出'),
                  Tab(text: '收入'),
                  Tab(text: '转账'),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('使用中'),
                      icon: Icon(Icons.folder_outlined, size: 18),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('已归档'),
                      icon: Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                  ],
                  selected: {_showArchived},
                  onSelectionChanged: (s) {
                    setState(() => _showArchived = s.first);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: (!_showArchived && ledgerAsync.valueOrNull != null)
          ? FloatingActionButton(
              tooltip: '新建分类',
              onPressed: () => promptCreateCategory(
                context,
                ref,
                ledgerId: ledgerAsync.valueOrNull!,
                kind: _kind,
              ),
              child: const Icon(Icons.add),
            )
          : null,
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledgerId) {
          if (ledgerId == null) {
            return const Center(child: Text('尚未初始化记账本'));
          }
          return TabBarView(
            controller: _tabs,
            children: [
              _CategoryKindList(
                ledgerId: ledgerId,
                kind: 'out',
                showArchived: _showArchived,
              ),
              _CategoryKindList(
                ledgerId: ledgerId,
                kind: 'in',
                showArchived: _showArchived,
              ),
              _CategoryKindList(
                ledgerId: ledgerId,
                kind: 'transfer',
                showArchived: _showArchived,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryKindList extends ConsumerWidget {
  const _CategoryKindList({
    required this.ledgerId,
    required this.kind,
    required this.showArchived,
  });

  final String ledgerId;
  final String kind;
  final bool showArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = showArchived
        ? ref.watch(_archivedCategoriesProvider((ledgerId, kind)))
        : ref.watch(_categoriesProvider((ledgerId, kind)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (cats) {
        final roots = cats.where((c) => c.parentId == null).toList();
        final childrenOf = <String, List<Category>>{};
        for (final c in cats) {
          final p = c.parentId;
          if (p != null) {
            childrenOf.putIfAbsent(p, () => []).add(c);
          }
        }

        // Orphan archived children (parent still active or not in this list)
        final rootIds = roots.map((r) => r.id).toSet();
        final orphans = cats
            .where(
              (c) =>
                  c.parentId != null && !rootIds.contains(c.parentId),
            )
            .toList();

        if (roots.isEmpty && orphans.isEmpty) {
          return CentliEmptyState(
            icon: showArchived
                ? Icons.inventory_2_outlined
                : Icons.category_outlined,
            title: showArchived ? '暂无已归档分类' : '暂无分类',
            message: showArchived
                ? '归档的分类会出现在这里，可随时恢复使用。'
                : '点右下角 + 添加支出/收入分类；可建父子层级并拖拽排序。',
          );
        }

        Future<void> persistOrder(List<Category> ordered) {
          return ref.read(databaseProvider).reorderCategories(
                ordered.map((c) => c.id).toList(),
              );
        }

        void onReorderRoots(int oldIndex, int newIndex) {
          final next = List<Category>.of(roots);
          final item = next.removeAt(oldIndex);
          next.insert(newIndex, item);
          persistOrder(next);
        }

        const listPadding = EdgeInsets.fromLTRB(
          CentliSpacing.pageH,
          CentliSpacing.section,
          CentliSpacing.pageH,
          88,
        );

        Widget rootTile(Category root, int index, {required bool reorderable}) {
          return _CategoryTreeNode(
            key: ValueKey(root.id),
            category: root,
            children: childrenOf[root.id] ?? const <Category>[],
            showArchived: showArchived,
            reorderable: reorderable,
            dragIndex: index,
            onReorderChildren: showArchived
                ? null
                : (ordered) => persistOrder(ordered),
            onAddChild: showArchived
                ? null
                : () => promptCreateCategory(
                      context,
                      ref,
                      ledgerId: ledgerId,
                      kind: kind,
                      parentId: root.id,
                    ),
            onRename: showArchived
                ? null
                : () => promptRenameCategory(context, ref, root),
            onArchive: showArchived
                ? null
                : () => promptArchiveCategory(context, ref, root),
            onUnarchive: showArchived
                ? () => promptUnarchiveCategory(context, ref, root)
                : null,
            onRenameChild: showArchived
                ? null
                : (child) => promptRenameCategory(context, ref, child),
            onArchiveChild: showArchived
                ? null
                : (child) => promptArchiveCategory(context, ref, child),
            onUnarchiveChild: showArchived
                ? (child) => promptUnarchiveCategory(context, ref, child)
                : null,
          );
        }

        if (showArchived) {
          return ListView(
            padding: listPadding,
            children: [
              for (var i = 0; i < roots.length; i++)
                rootTile(roots[i], i, reorderable: false),
              if (orphans.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    '已归档子分类',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final child in orphans)
                  CentliSoftCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CentliIconChip(name: child.name, kind: child.kind, iconKey: child.icon, size: 40),
                      title: Text(child.name),
                      subtitle: const Text('二级'),
                      trailing: CentliGlassPopupButton<String>(
                        onSelected: (v) {
                          if (v == 'unarchive') {
                            promptUnarchiveCategory(context, ref, child);
                          }
                        },
                        items: const [
                          CentliMenuItem(
                            value: 'unarchive',
                            label: '取消归档',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        }

        // Active list: drag-to-reorder roots (and children inside each node).
        if (orphans.isEmpty) {
          return ReorderableListView.builder(
            padding: listPadding,
            buildDefaultDragHandles: false,
            itemCount: roots.length,
            onReorderItem: onReorderRoots,
            itemBuilder: (context, index) =>
                rootTile(roots[index], index, reorderable: true),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.all(CentliSpacing.cardPad),
                buildDefaultDragHandles: false,
                itemCount: roots.length,
                onReorderItem: onReorderRoots,
                itemBuilder: (context, index) =>
                    rootTile(roots[index], index, reorderable: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已归档子分类',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                children: [
                  for (final child in orphans)
                    CentliSoftCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CentliIconChip(name: child.name, kind: child.kind, iconKey: child.icon, size: 40),
                        title: Text(child.name),
                        subtitle: const Text('二级'),
                        trailing: CentliGlassPopupButton<String>(
                          onSelected: (v) {
                            if (v == 'unarchive') {
                              promptUnarchiveCategory(context, ref, child);
                            }
                          },
                          items: const [
                            CentliMenuItem(
                              value: 'unarchive',
                              label: '取消归档',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

}

class _CategoryTreeNode extends StatelessWidget {
  const _CategoryTreeNode({
    super.key,
    required this.category,
    required this.children,
    required this.showArchived,
    this.reorderable = false,
    this.dragIndex = 0,
    this.onReorderChildren,
    this.onAddChild,
    this.onRename,
    this.onArchive,
    this.onUnarchive,
    this.onRenameChild,
    this.onArchiveChild,
    this.onUnarchiveChild,
  });

  final Category category;
  final List<Category> children;
  final bool showArchived;
  final bool reorderable;
  final int dragIndex;
  final ValueChanged<List<Category>>? onReorderChildren;
  final VoidCallback? onAddChild;
  final VoidCallback? onRename;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final ValueChanged<Category>? onRenameChild;
  final ValueChanged<Category>? onArchiveChild;
  final ValueChanged<Category>? onUnarchiveChild;


  Widget _menu({
    VoidCallback? onRename,
    VoidCallback? onArchive,
    VoidCallback? onUnarchive,
    VoidCallback? onAddChild,
  }) {
    return CentliGlassPopupButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'rename':
            onRename?.call();
          case 'child':
            onAddChild?.call();
          case 'archive':
            onArchive?.call();
          case 'unarchive':
            onUnarchive?.call();
        }
      },
      items: [
        if (showArchived)
          const CentliMenuItem(value: 'unarchive', label: '取消归档')
        else ...[
          const CentliMenuItem(value: 'rename', label: '重命名'),
          if (onAddChild != null)
            const CentliMenuItem(value: 'child', label: '添加子分类'),
          const CentliMenuItem(value: 'archive', label: '归档'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canReorderChildren =
        reorderable && onReorderChildren != null && children.length > 1;

    final Widget childList;
    if (children.isEmpty) {
      childList = ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 40, right: 8),
        title: Text(
          '暂无子分类',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (canReorderChildren) {
      childList = ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) {
          final next = List<Category>.of(children);
          final item = next.removeAt(oldIndex);
          next.insert(newIndex, item);
          onReorderChildren!(next);
        },
        children: [
          for (var i = 0; i < children.length; i++)
            ListTile(
              key: ValueKey(children[i].id),
              contentPadding: const EdgeInsets.only(left: 8, right: 4),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                  CentliIconChip(name: children[i].name, kind: children[i].kind, iconKey: children[i].icon, size: 32),
                ],
              ),
              title: Text(children[i].name),
              subtitle: const Text('二级'),
              trailing: _menu(
                onRename: onRenameChild == null
                    ? null
                    : () => onRenameChild!(children[i]),
                onArchive: onArchiveChild == null
                    ? null
                    : () => onArchiveChild!(children[i]),
                onUnarchive: onUnarchiveChild == null
                    ? null
                    : () => onUnarchiveChild!(children[i]),
              ),
              onTap: onRenameChild == null
                  ? null
                  : () => onRenameChild!(children[i]),
            ),
        ],
      );
    } else {
      childList = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in children)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 40, right: 4),
              leading: CentliIconChip(name: child.name, kind: child.kind, iconKey: child.icon, size: 32),
              title: Text(child.name),
              subtitle: Text(showArchived ? '已归档 · 二级' : '二级'),
              trailing: _menu(
                onRename: onRenameChild == null
                    ? null
                    : () => onRenameChild!(child),
                onArchive: onArchiveChild == null
                    ? null
                    : () => onArchiveChild!(child),
                onUnarchive: onUnarchiveChild == null
                    ? null
                    : () => onUnarchiveChild!(child),
              ),
              onTap: showArchived
                  ? (onUnarchiveChild == null
                      ? null
                      : () => onUnarchiveChild!(child))
                  : (onRenameChild == null
                      ? null
                      : () => onRenameChild!(child)),
            ),
        ],
      );
    }

    return CentliSoftCard(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: children.isNotEmpty,
          leading: reorderable
              ? ReorderableDragStartListener(
                  index: dragIndex,
                  child: const Icon(Icons.drag_handle),
                )
              : CentliIconChip(name: category.name, kind: category.kind, iconKey: category.icon, size: 40),
          title: Row(
            children: [
              if (reorderable) ...[
                CentliIconChip(name: category.name, kind: category.kind, iconKey: category.icon, size: 40),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(category.name)),
              _menu(
                onRename: onRename,
                onArchive: onArchive,
                onUnarchive: onUnarchive,
                onAddChild: onAddChild,
              ),
            ],
          ),
          subtitle: Text(showArchived ? '已归档 · 一级' : '一级'),
          childrenPadding: const EdgeInsets.only(left: 12, right: 8, bottom: 8),
          children: [childList],
        ),
      ),
    );
  }
}

Future<void> promptCreateCategory(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  required String kind,
  String? parentId,
}) async {
  final result = await _promptCategoryEditor(
    context,
    title: parentId == null ? '新建分类' : '新建子分类',
  );
  if (result == null) return;
  await ref.read(databaseProvider).createCategory(
        ledgerId: ledgerId,
        name: result.name,
        kind: kind,
        parentId: parentId,
        icon: result.iconKey,
      );
}

Future<void> promptRenameCategory(
  BuildContext context,
  WidgetRef ref,
  Category cat,
) async {
  final result = await _promptCategoryEditor(
    context,
    title: '编辑分类',
    initialName: cat.name,
    initialIconKey: cat.icon,
  );
  if (result == null) return;
  if (result.name != cat.name || result.iconKey != cat.icon) {
    await ref.read(databaseProvider).renameCategory(
          id: cat.id,
          name: result.name,
          icon: result.iconKey,
          updateIcon: true,
        );
  }
}

Future<void> promptArchiveCategory(
  BuildContext context,
  WidgetRef ref,
  Category cat,
) async {
  final db = ref.read(databaseProvider);
  final txnCount = await db.countTransactionsForCategory(cat.id);
  if (!context.mounted) return;
  final msg = txnCount > 0
      ? '「${cat.name}」已有 $txnCount 笔流水，将归档（不再出现在记账面板），历史账单保留。'
      : '确定归档「${cat.name}」？';
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: const Text('归档分类'),
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('归档'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await db.archiveCategory(cat.id);
  if (context.mounted) {
    showGlassSnackBar(context, '已归档 ${cat.name}');
  }
}

Future<void> promptUnarchiveCategory(
  BuildContext context,
  WidgetRef ref,
  Category cat,
) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: const Text('取消归档'),
      content: Text(
        '确定取消归档「${cat.name}」？将重新出现在分类管理与记账面板。'
        '${cat.parentId == null ? '其子分类也会一并恢复。' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('取消归档'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(databaseProvider).unarchiveCategory(cat.id);
  if (context.mounted) {
    showGlassSnackBar(context, '已取消归档 ${cat.name}');
  }
}

class _CategoryEditorResult {
  const _CategoryEditorResult({required this.name, this.iconKey});
  final String name;
  final String? iconKey;
}

Future<_CategoryEditorResult?> _promptCategoryEditor(
  BuildContext context, {
  required String title,
  String initialName = '',
  String? initialIconKey,
}) async {
  final ctrl = TextEditingController(text: initialName);
  String? iconKey = initialIconKey;

  final result = await showGlassDialog<_CategoryEditorResult>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return CentliGlassDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(40),
                    onTap: () async {
                      final picked = await showCentliIconPicker(
                        ctx,
                        currentIconKey: iconKey,
                        entityName: ctrl.text.trim(),
                      );
                      if (picked != null) {
                        setLocal(() => iconKey = picked.iconKey);
                      }
                    },
                    child: Column(
                      children: [
                        CentliIconChip(
                          name: ctrl.text.trim().isEmpty ? '分类' : ctrl.text.trim(),
                          iconKey: iconKey,
                          size: 56,
                        ),
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          '点按选择图标',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                    onChanged: (_) => setLocal(() {}),
                    onSubmitted: (v) {
                      final name = v.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(
                        ctx,
                        _CategoryEditorResult(name: name, iconKey: iconKey),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(
                    ctx,
                    _CategoryEditorResult(name: name, iconKey: iconKey),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
  ctrl.dispose();
  return result;
}
