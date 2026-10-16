from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# ===== bookkeeping_sheet: #2 #6 #7 #35 =====
bp = ROOT / "lib/features/ledger/bookkeeping_sheet.dart"
b = bp.read_text(encoding="utf-8")

# Add _merchant field
if "String? _merchant;" not in b:
    old = "  String? _categoryId;\n  final _noteCtrl = TextEditingController();"
    new = "  String? _categoryId;\n  String? _merchant;\n  final _noteCtrl = TextEditingController();"
    if old not in b:
        raise SystemExit("categoryId field missing")
    b = b.replace(old, new, 1)

# _load: include archived accounts referenced by existing txn
old_load = """    final accounts = await db.loadActiveAccounts(ledgerId);
    final cats =
        await db.loadCategories(ledgerId, _type == 'in' ? 'in' : 'out');
    if (!mounted) return;
    final existing = widget.existing;
    setState(() {
      _ledgerId = ledgerId;
      _accounts = accounts;
      if (existing != null) {
        _type = existing.type;
        _amountText = fromMinor(existing.currency, existing.amountMinor)
            .toStringAsFixed(currencyDecimals[existing.currency] ?? 2);
        // trim trailing zeros from whole amounts
        if (_amountText.contains('.')) {
          _amountText = _amountText.replaceFirst(RegExp(r'\\.?0+$'), '');
          if (_amountText.isEmpty) _amountText = '0';
        }
        _accountId = existing.accountId;
        _toAccountId = existing.toAccountId;
        _categoryId = existing.categoryId;
        _noteCtrl.text = existing.note ?? '';"""

new_load = """    var accounts = await db.loadActiveAccounts(ledgerId);
    final existing = widget.existing;
    if (existing != null) {
      final need = <String>{
        existing.accountId,
        if (existing.toAccountId != null) existing.toAccountId!,
      };
      final have = {for (final a in accounts) a.id};
      for (final id in need) {
        if (!have.contains(id)) {
          final a = await db.getAccount(id);
          if (a != null) accounts = [...accounts, a];
        }
      }
    }
    final cats =
        await db.loadCategories(ledgerId, _type == 'in' ? 'in' : 'out');
    if (!mounted) return;
    setState(() {
      _ledgerId = ledgerId;
      _accounts = accounts;
      if (existing != null) {
        _type = existing.type;
        _amountText = fromMinor(existing.currency, existing.amountMinor)
            .toStringAsFixed(currencyDecimals[existing.currency] ?? 2);
        // trim trailing zeros from whole amounts
        if (_amountText.contains('.')) {
          _amountText = _amountText.replaceFirst(RegExp(r'\\.?0+$'), '');
          if (_amountText.isEmpty) _amountText = '0';
        }
        _accountId = existing.accountId;
        _toAccountId = existing.toAccountId;
        _categoryId = existing.categoryId;
        _merchant = existing.merchant;
        _noteCtrl.text = existing.note ?? '';"""

if old_load not in b:
    raise SystemExit("load block missing")
b = b.replace(old_load, new_load, 1)

# #7 FX dialog dispose on cancel
old_fx = """    if (ok != true) return;
    setState(() {
      _useToAmount = useTo;
      if (useTo) {
        _toAmountText = toCtrl.text.trim().isEmpty ? '0' : toCtrl.text.trim();
        _fxRateText = null;
      } else {
        _fxRateText = rateCtrl.text.trim();
        _toAmountText = '0';
      }
    });
    toCtrl.dispose();
    rateCtrl.dispose();
    await _save(skipCrossPrompt: true, keepOpen: keepOpen);
  }"""

new_fx = """    try {
      if (ok != true) return;
      setState(() {
        _useToAmount = useTo;
        if (useTo) {
          _toAmountText = toCtrl.text.trim().isEmpty ? '0' : toCtrl.text.trim();
          _fxRateText = null;
        } else {
          _fxRateText = rateCtrl.text.trim();
          _toAmountText = '0';
        }
      });
      await _save(skipCrossPrompt: true, keepOpen: keepOpen);
    } finally {
      toCtrl.dispose();
      rateCtrl.dispose();
    }
  }"""

if old_fx not in b:
    raise SystemExit("fx dispose block missing")
b = b.replace(old_fx, new_fx, 1)

# save: pass merchant
old_save_note = """      final note =
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final toAcc = _type == 'transfer' ? _toAccountId : null;
      final cat = _type == 'transfer' ? null : _categoryId;
      if (widget.existing != null) {
        await db.updateManualTransaction(
          id: widget.existing!.id,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          note: note,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      } else {
        await db.insertManualTransaction(
          ledgerId: _ledgerId!,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          note: note,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      }"""

new_save_note = """      final note =
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final merchant =
          (_merchant ?? '').trim().isEmpty ? null : _merchant!.trim();
      final toAcc = _type == 'transfer' ? _toAccountId : null;
      final cat = _type == 'transfer' ? null : _categoryId;
      if (widget.existing != null) {
        await db.updateManualTransaction(
          id: widget.existing!.id,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          merchant: merchant,
          note: note,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      } else {
        await db.insertManualTransaction(
          ledgerId: _ledgerId!,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          merchant: merchant,
          note: note,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      }"""

if old_save_note not in b:
    raise SystemExit("save block missing")
b = b.replace(old_save_note, new_save_note, 1)

# smart fill: keep merchant separate, do not dump into note
old_smart = """      // Note = leftover remark only. Merchant is separate (shown in hits / rules).
      // If leftover empty but merchant present, put merchant into note for visibility
      // in the single note field (manual insert has no dedicated merchant UI).
      final leftover = parsed.note?.trim();
      final String noteText;
      if (leftover != null && leftover.isNotEmpty) {
        noteText = leftover;
      } else if (parsed.merchant != null && parsed.merchant!.trim().isNotEmpty) {
        noteText = parsed.merchant!.trim();
      } else {
        noteText = '';
      }

      if (!mounted) return;
      setState(() {
        _type = nextType;
        _categories = cats;
        if (nextType == 'transfer') {
          _categoryId = null;
        } else if (categoryResolved) {
          _categoryId = categoryId;
        } else {
          // Unset rather than wrong guess (e.g. always first = food).
          _categoryId = null;
        }
        _accountId = accountId;
        _toAccountId = toAccountId;
        _amountText = amountText;
        _noteCtrl.text = noteText;"""

# Comment may have Chinese garble - match more loosely
import re
m = re.search(
    r"      // Note = leftover remark only\..*?\n      final leftover = parsed\.note\?\.trim\(\);\n"
    r"      final String noteText;\n"
    r"      if \(leftover != null && leftover\.isNotEmpty\) \{\n"
    r"        noteText = leftover;\n"
    r"      \} else if \(parsed\.merchant != null && parsed\.merchant!\.trim\(\)\.isNotEmpty\) \{\n"
    r"        noteText = parsed\.merchant!\.trim\(\);\n"
    r"      \} else \{\n"
    r"        noteText = '';\n"
    r"      \}\n"
    r"\n"
    r"      if \(!mounted\) return;\n"
    r"      setState\(\(\) \{\n"
    r"        _type = nextType;\n"
    r"        _categories = cats;\n"
    r"        if \(nextType == 'transfer'\) \{\n"
    r"          _categoryId = null;\n"
    r"        \} else if \(categoryResolved\) \{\n"
    r"          _categoryId = categoryId;\n"
    r"        \} else \{\n"
    r"          // Unset rather than wrong guess.*\n"
    r"          _categoryId = null;\n"
    r"        \}\n"
    r"        _accountId = accountId;\n"
    r"        _toAccountId = toAccountId;\n"
    r"        _amountText = amountText;\n"
    r"        _noteCtrl\.text = noteText;",
    b,
    re.S,
)
if not m:
    raise SystemExit("smart fill note block missing")

new_smart = """      // Note = leftover remark only. Merchant is stored on its own column.
      final leftover = parsed.note?.trim();
      final noteText = (leftover != null && leftover.isNotEmpty) ? leftover : '';
      final merchantText = parsed.merchant?.trim();

      if (!mounted) return;
      setState(() {
        _type = nextType;
        _categories = cats;
        if (nextType == 'transfer') {
          _categoryId = null;
        } else if (categoryResolved) {
          _categoryId = categoryId;
        } else {
          // Unset rather than wrong guess.
          _categoryId = null;
        }
        _accountId = accountId;
        _toAccountId = toAccountId;
        _amountText = amountText;
        _merchant = (merchantText != null && merchantText.isNotEmpty)
            ? merchantText
            : null;
        _noteCtrl.text = noteText;"""
b = b[:m.start()] + new_smart + b[m.end():]

# clear merchant on keepOpen
if "_noteCtrl.clear();" in b and "_merchant = null;" not in b:
    b = b.replace(
        "          _noteCtrl.clear();\n          _happenAt = DateTime.now();",
        "          _noteCtrl.clear();\n          _merchant = null;\n          _happenAt = DateTime.now();",
        1,
    )

# Unique ValueKeys for dropdowns (#6/#35)
b = b.replace(
    "key: ValueKey('dd-$_fieldEpoch-${_accountId}_${_toAccountId}_$_type'),\n                            initialValue: _accountId,\n                            items: [\n                              for (final a in _accounts)\n                                DropdownMenuItem(\n                                  value: a.id,\n                                  child: Text('${a.name} (${a.currency})'),\n                                ),\n                            ],\n                            onChanged: (v) => setState(() => _accountId = v),\n                            decoration: const InputDecoration(\n                              isDense: true,\n                              border: OutlineInputBorder(),\n                            ),\n                          ),\n                        ),\n                      ],\n                    ),\n                  ),\n                  Padding(\n                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),\n                    child: Row(\n                      children: [\n                        SizedBox(\n                          width: 56,\n                          child: Text('\\u8f6c\\u5165'",
    "KEY_TRANSFER_FROM_PLACEHOLDER",
    1,
)

# Simpler approach: replace the three identical keys with unique ones in order
keys = [
    "ValueKey('dd-from-$_fieldEpoch-$_type')",
    "ValueKey('dd-to-$_fieldEpoch-$_type')",
    "ValueKey('dd-acc-$_fieldEpoch-$_type')",
]
old_key = "ValueKey('dd-$_fieldEpoch-${_accountId}_${_toAccountId}_$_type')"
count = b.count(old_key)
print("duplicate ValueKey count", count)
if count >= 3:
    for k in keys:
        b = b.replace(old_key, k, 1)
elif count > 0:
    # replace all remaining uniquely by index
    i = 0
    while old_key in b and i < len(keys):
        b = b.replace(old_key, keys[i], 1)
        i += 1

# Clamp initialValue for account dropdowns when id not in items (safety)
# Replace initialValue: _accountId, with a safe expression - too broad.
# Instead ensure archived accounts are in list (done above).

bp.write_text(b, encoding="utf-8", newline="\n")
print("wrote bookkeeping_sheet")
