import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/widgets/centli_icon.dart';
import '../../data/db/centli_database.dart';
import '../../core/widgets/glass.dart';

/// Finch-style category picker: left parent list + right subcategory icon grid.
///
/// Uses Centli's existing category tree (`parentId`) and [CentliIconChip] assets.
Future<String?> showCategoryPickerSheet(
  BuildContext context, {
  required List<Category> categories,
  String? selectedId,
}) {
  return showGlassSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CategoryPickerBody(
      categories: categories,
      selectedId: selectedId,
    ),
  );
}

class _CategoryPickerBody extends StatefulWidget {
  const _CategoryPickerBody({
    required this.categories,
    this.selectedId,
  });

  final List<Category> categories;
  final String? selectedId;

  @override
  State<_CategoryPickerBody> createState() => _CategoryPickerBodyState();
}

class _CategoryPickerBodyState extends State<_CategoryPickerBody> {
  late String? _parentId;
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _parentId = _initialParentId();
  }

  List<Category> get _roots {
    final roots = widget.categories
        .where((c) => c.parentId == null || c.parentId!.isEmpty)
        .toList();
    // Orphan children (parent missing) appear as roots so they stay reachable.
    final rootIds = {for (final r in roots) r.id};
    for (final c in widget.categories) {
      final p = c.parentId;
      if (p != null && p.isNotEmpty && !rootIds.contains(p) && !rootIds.contains(c.id)) {
        roots.add(c);
        rootIds.add(c.id);
      }
    }
    return roots;
  }

  List<Category> _childrenOf(String parentId) {
    return widget.categories
        .where((c) => c.parentId == parentId)
        .toList();
  }

  String? _initialParentId() {
    final roots = _roots;
    if (roots.isEmpty) return null;
    final sel = widget.selectedId;
    if (sel != null) {
      for (final c in widget.categories) {
        if (c.id != sel) continue;
        final p = c.parentId;
        if (p != null && p.isNotEmpty) {
          // Prefer real parent if present in roots.
          if (roots.any((r) => r.id == p)) return p;
        }
        return c.id;
      }
    }
    return roots.first.id;
  }

  List<Category> get _gridItems {
    final pid = _parentId;
    if (pid == null) return const [];
    final kids = _childrenOf(pid);
    if (kids.isNotEmpty) return kids;
    // Leaf parent: show itself.
    return widget.categories.where((c) => c.id == pid).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final roots = _roots;

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
                Text(
                  '选择分类',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await context.push('/me/categories');
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
            child: roots.isEmpty
                ? Center(
                    child: Text(
                      '暂无分类',
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
                            itemCount: roots.length,
                            itemBuilder: (context, i) {
                              final root = roots[i];
                              final selected = root.id == _parentId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: selected
                                      ? scheme.surface
                                      : Colors.transparent,
                                  elevation: selected ? 1.5 : 0,
                                  shadowColor: scheme.shadow
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () =>
                                        setState(() => _parentId = root.id),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        root.name,
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
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: _gridItems.length,
                            itemBuilder: (context, i) {
                              final c = _gridItems[i];
                              final selected = c.id == _selectedId;
                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(context, c.id),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? CentliTheme.softBlue
                                            .withValues(alpha: 0.10)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CentliIconChip(
                                        name: c.name,
                                        kind: c.kind,
                                        iconKey: c.icon,
                                        size: 44,
                                        roundedSquare: true,
                                      ),
                                      const SizedBox(height: CentliSpacing.item),
                                      Text(
                                        c.name,
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
