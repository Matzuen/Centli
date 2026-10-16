# -*- coding: utf-8 -*-
from pathlib import Path

path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')

old_reload = '''  Future<void> _reloadCategories() async {
    if (_ledgerId == null || _type == 'transfer') return;
    final db = ref.read(databaseProvider);
    final cats =
        await db.loadCategories(_ledgerId!, _type == 'in' ? 'in' : 'out');
    setState(() {
      _categories = cats;
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
    });
  }'''

new_reload = '''  Future<void> _reloadCategories({bool resetSelection = false}) async {
    if (_ledgerId == null || _type == 'transfer') return;
    final db = ref.read(databaseProvider);
    final cats =
        await db.loadCategories(_ledgerId!, _type == 'in' ? 'in' : 'out');
    setState(() {
      _categories = cats;
      if (resetSelection ||
          _categoryId == null ||
          !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
  }'''

if old_reload not in text:
    raise SystemExit('reloadCategories block not found')
text = text.replace(old_reload, new_reload, 1)

# Type switch should reset selection to first of new kind
old_type = '''                          onSelectionChanged: (s) {
                            setState(() => _type = s.first);
                            _reloadCategories();
                          },'''
new_type = '''                          onSelectionChanged: (s) {
                            setState(() => _type = s.first);
                            _reloadCategories(resetSelection: true);
                          },'''
if old_type not in text:
    raise SystemExit('type selection block not found')
text = text.replace(old_type, new_type, 1)

old_pick = '''  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _categories,
      selectedId: _categoryId,
    );
    if (!mounted) return;
    // Picker pops without id when user opens 管理 — reload categories.
    await _reloadCategories();
    if (id != null && mounted) {
      setState(() => _categoryId = id);
    }
  }'''

new_pick = '''  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _categories,
      selectedId: _categoryId,
    );
    if (!mounted) return;
    if (id != null) {
      setState(() => _categoryId = id);
      return;
    }
    // Dismiss or 管理: refresh tree, keep selection when still valid.
    await _reloadCategories();
  }'''

if old_pick not in text:
    raise SystemExit('pickCategory block not found')
text = text.replace(old_pick, new_pick, 1)

# Soften modal sheet background to blend with Centli gradient chrome
old_sheet = '''  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => BookkeepingSheet(existing: existing),
  );'''

new_sheet = '''  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => BookkeepingSheet(existing: existing),
  );'''

if old_sheet not in text:
    print('WARN: sheet shape not updated')
else:
    text = text.replace(old_sheet, new_sheet, 1)

path.write_text(text, encoding='utf-8', newline='\n')
print('reload/pick fixes applied')