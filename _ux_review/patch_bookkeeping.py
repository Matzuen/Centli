# -*- coding: utf-8 -*-
from pathlib import Path

path = Path(r'D:\Resource\Codebase\studyProject\Centli\lib\features\ledger\bookkeeping_sheet.dart')
text = path.read_text(encoding='utf-8')

# 1) Add import
old_import = "import 'local_speech.dart';"
new_import = "import 'local_speech.dart';\nimport 'category_picker_sheet.dart';"
if "category_picker_sheet.dart" not in text:
    if old_import not in text:
        raise SystemExit('import anchor missing')
    text = text.replace(old_import, new_import, 1)

# 2) Helper methods to insert before Widget build
helpers = r'''
  Category? _categoryById(String? id) {
    if (id == null || _categories.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _pickCategory() async {
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
  }

  Future<void> _pickAccount({required bool toAccount}) async {
    final current = toAccount ? _toAccountId : _accountId;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _AccountPickerSheet(
          accounts: _accounts,
          selectedId: current,
          title: toAccount ? '\u9009\u62e9\u8f6c\u5165\u8d26\u6237' : '\u9009\u62e9\u8d26\u6237',
        );
      },
    );
    if (id == null || !mounted) return;
    setState(() {
      if (toAccount) {
        _toAccountId = id;
      } else {
        _accountId = id;
      }
    });
  }

'''

anchor_build = '  Widget build(BuildContext context) {'
if '_pickCategory()' not in text:
    if anchor_build not in text:
        raise SystemExit('build anchor missing')
    text = text.replace(anchor_build, helpers + anchor_build, 1)

# 3) Replace amount + remark + category chips + account dropdowns + date row
start_marker = '''                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      if (_amountHasOperator)'''

end_marker = '''                const Spacer(),
                _Keypad('''

start = text.find(start_marker)
end = text.find(end_marker)
if start < 0 or end < 0 or end <= start:
    raise SystemExit(f'UI replace markers missing start={start} end={end}')

new_ui = r'''                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (_amountHasOperator)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              _amountText,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        Text(
                          formatMinor(
                            _currency,
                            toMinor(
                              _currency,
                              _evalAmount(_amountText) ?? 0,
                            ),
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currencyLabel(_currency),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        label: _happenAtLabel,
                        onTap: _pickHappenAt,
                      ),
                      if (_type != 'transfer') ...[
                        Builder(
                          builder: (context) {
                            final cat = _categoryById(_categoryId);
                            return _MetaChip(
                              leading: cat == null
                                  ? null
                                  : CentliIconChip(
                                      name: cat.name,
                                      kind: cat.kind,
                                      iconKey: cat.icon,
                                      size: 22,
                                    ),
                              icon: cat == null
                                  ? Icons.category_outlined
                                  : null,
                              label: cat?.name ?? '\u5206\u7c7b',
                              onTap: _pickCategory,
                            );
                          },
                        ),
                        Builder(
                          builder: (context) {
                            final acc = _accountById(_accountId);
                            return _MetaChip(
                              leading: acc == null
                                  ? null
                                  : CentliIconChip(
                                      name: acc.name,
                                      kind: 'account',
                                      iconKey: acc.icon,
                                      size: 22,
                                    ),
                              icon: acc == null
                                  ? Icons.account_balance_wallet_outlined
                                  : null,
                              label: acc == null
                                  ? '\u8d26\u6237'
                                  : '${acc.name} \u00b7 ${currencyLabel(acc.currency)}',
                              onTap: () => _pickAccount(toAccount: false),
                            );
                          },
                        ),
                      ] else ...[
                        Builder(
                          builder: (context) {
                            final acc = _accountById(_accountId);
                            return _MetaChip(
                              leading: acc == null
                                  ? null
                                  : CentliIconChip(
                                      name: acc.name,
                                      kind: 'account',
                                      iconKey: acc.icon,
                                      size: 22,
                                    ),
                              icon: Icons.south_west_rounded,
                              label: acc == null
                                  ? '\u8f6c\u51fa'
                                  : '\u8f6c\u51fa \u00b7 ${acc.name}',
                              onTap: () => _pickAccount(toAccount: false),
                            );
                          },
                        ),
                        Builder(
                          builder: (context) {
                            final acc = _accountById(_toAccountId);
                            return _MetaChip(
                              leading: acc == null
                                  ? null
                                  : CentliIconChip(
                                      name: acc.name,
                                      kind: 'account',
                                      iconKey: acc.icon,
                                      size: 22,
                                    ),
                              icon: Icons.north_east_rounded,
                              label: acc == null
                                  ? '\u8f6c\u5165'
                                  : '\u8f6c\u5165 \u00b7 ${acc.name}',
                              onTap: () => _pickAccount(toAccount: true),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                if (_type == 'transfer' && _isCrossCurrency)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      '\u8de8\u5e01\uff1a\u4fdd\u5b58\u65f6\u4f1a\u8be2\u95ee\u5bf9\u65b9\u91d1\u989d/\u6c47\u7387',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      hintText: '\u5907\u6ce8',
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F8FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E8EC)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E8EC)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                _Keypad('''

text = text[:start] + new_ui + text[end + len(end_marker):]
# wait - end_marker includes Spacer and _Keypad( — new_ui already ends with those.
# Fix: end should point AT end_marker start, and new_ui includes end_marker content.
# Currently: text[end + len(end_marker):] skips the marker — good since new_ui has it.

# 4) Insert widget classes before _Keypad
widgets = r'''
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE6E8EC)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6B7A99).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({
    required this.accounts,
    required this.title,
    this.selectedId,
  });

  final List<Account> accounts;
  final String title;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 8),
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
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final a = accounts[i];
                final selected = a.id == selectedId;
                return ListTile(
                  leading: CentliIconChip(
                    name: a.name,
                    kind: 'account',
                    iconKey: a.icon,
                    size: 40,
                  ),
                  title: Text(
                    a.name,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(currencyLabel(a.currency)),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: CentliTheme.softBlue)
                      : null,
                  onTap: () => Navigator.pop(context, a.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

'''

keypad_cls = 'class _Keypad extends StatelessWidget'
if 'class _MetaChip extends StatelessWidget' not in text:
    if keypad_cls not in text:
        raise SystemExit('keypad class missing')
    text = text.replace(keypad_cls, widgets + keypad_cls, 1)

# Fix _reloadCategories: after manage categories, don't force-reset selected id when
# still present. Existing behavior resets to first — leave as-is for type switch,
# but _pickCategory already calls reload then sets id.

path.write_text(text, encoding='utf-8', newline='\n')
print('patched', path)
print('has MetaChip', 'class _MetaChip' in text)
print('has category import', 'category_picker_sheet' in text)
print('has currencyLabel chip', 'currencyLabel(_currency)' in text)
print('old ChoiceChip gone?', 'ChoiceChip(' not in text)
print('old DropdownButton?', 'DropdownButtonFormField' not in text)