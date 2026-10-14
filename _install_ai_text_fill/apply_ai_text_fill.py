# -*- coding: utf-8 -*-
"""Install P3 AI text fill into Centli tree."""
import base64, pathlib, re, sys

ROOT = pathlib.Path(r"D:\Resource\Codebase\studyProject\Centli")
HERE = pathlib.Path(__file__).resolve().parent

def write_bytes(rel: str, data: bytes):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print("wrote", path, path.stat().st_size)

# Payload files next to this script
for name, rel in [
    ("ai_text_fill.dart", r"lib\features\ledger\ai_text_fill.dart"),
    ("ai_text_fill_test.dart", r"test\ai_text_fill_test.dart"),
]:
    write_bytes(rel, (HERE / name).read_bytes())

sheet = ROOT / r"lib\features\ledger\bookkeeping_sheet.dart"
text = sheet.read_text(encoding="utf-8")

if "ai_text_fill.dart" in text and "_applyAiTextFill" in text:
    print("bookkeeping_sheet already patched")
    sys.exit(0)

# --- import ---
if "import 'ai_text_fill.dart';" not in text:
    needle = "import '../../data/db/database_provider.dart';\n"
    if needle not in text:
        raise SystemExit("import anchor missing")
    text = text.replace(
        needle,
        needle + "import 'ai_text_fill.dart';\n",
        1,
    )

# --- state fields ---
state_anchor = "  final _noteCtrl = TextEditingController();\n"
if "_aiTextCtrl" not in text:
    if state_anchor not in text:
        raise SystemExit("state anchor missing")
    text = text.replace(
        state_anchor,
        state_anchor
        + "  final _aiTextCtrl = TextEditingController();\n"
        + "  bool _aiExpanded = false;\n"
        + "  int _fieldEpoch = 0;\n",
        1,
    )

# --- dispose ---
if "_aiTextCtrl.dispose()" not in text:
    text = text.replace(
        "    _noteCtrl.dispose();\n    super.dispose();",
        "    _noteCtrl.dispose();\n"
        "    _aiTextCtrl.dispose();\n"
        "    super.dispose();",
        1,
    )

# --- apply method before build ---
apply_method = r'''
  Future<void> _applyAiTextFill() async {
    final raw = _aiTextCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入记账话术')),
      );
      return;
    }
    if (_ledgerId == null) return;

    final db = ref.read(databaseProvider);
    final outCats = await db.loadCategories(_ledgerId!, 'out');
    final inCats = await db.loadCategories(_ledgerId!, 'in');
    final allCatNames = [
      ...outCats.map((c) => c.name),
      ...inCats.map((c) => c.name),
    ];
    final accountNames = _accounts.map((a) => a.name).toList();

    final parsed = parseBookkeepingText(
      raw,
      categoryNames: allCatNames,
      accountNames: accountNames,
    );
    if (!parsed.hasUsefulFill) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能识别，请换种说法或手动填写')),
      );
      return;
    }

    final nextType = parsed.type ?? _type;
    List<Category> cats = _categories;
    if (nextType != 'transfer') {
      cats = await db.loadCategories(
        _ledgerId!,
        nextType == 'in' ? 'in' : 'out',
      );
    }

    String? categoryId = _categoryId;
    if (parsed.categoryName != null && nextType != 'transfer') {
      Category? hit;
      for (final c in cats) {
        if (c.name == parsed.categoryName) {
          hit = c;
          break;
        }
      }
      hit ??= () {
        for (final c in cats) {
          if (c.name.contains(parsed.categoryName!) ||
              parsed.categoryName!.contains(c.name)) {
            return c;
          }
        }
        return null;
      }();
      if (hit != null) categoryId = hit.id;
    }

    // Merchant rule may override category for expense/income.
    if (parsed.merchant != null &&
        parsed.merchant!.trim().isNotEmpty &&
        nextType != 'transfer') {
      final key =
          parsed.merchant!.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final rule = await db.findMerchantRule(_ledgerId!, key);
      if (rule?.categoryId != null) {
        final id = rule!.categoryId!;
        if (cats.any((c) => c.id == id)) {
          categoryId = id;
        }
      }
      if (rule?.accountId != null) {
        final id = rule!.accountId!;
        if (_accounts.any((a) => a.id == id)) {
          // applied below via accountName override path
        }
      }
    }

    String? accountId = _accountId;
    String? toAccountId = _toAccountId;
    if (parsed.accountName != null) {
      for (final a in _accounts) {
        if (a.name == parsed.accountName) {
          accountId = a.id;
          break;
        }
      }
    }
    if (parsed.toAccountName != null) {
      for (final a in _accounts) {
        if (a.name == parsed.toAccountName) {
          toAccountId = a.id;
          break;
        }
      }
    }
    // Merchant-rule account if still default and rule has one.
    if (parsed.merchant != null && parsed.merchant!.trim().isNotEmpty) {
      final key =
          parsed.merchant!.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final rule = await db.findMerchantRule(_ledgerId!, key);
      if (rule?.accountId != null &&
          _accounts.any((a) => a.id == rule!.accountId)) {
        if (parsed.accountName == null) {
          accountId = rule!.accountId;
        }
      }
    }

    String amountText = _amountText;
    if (parsed.amount != null) {
      var s = parsed.amount!.toStringAsFixed(2);
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
      if (s.isEmpty) s = '0';
      amountText = s;
    }

    final noteParts = <String>[];
    if (parsed.merchant != null && parsed.merchant!.isNotEmpty) {
      noteParts.add(parsed.merchant!);
    }
    // Keep user phrase as note if they left note empty or wants the phrase.
    if (parsed.note != null && parsed.note!.isNotEmpty) {
      noteParts.add(parsed.note!);
    }
    final noteText = noteParts.isEmpty
        ? _noteCtrl.text
        : (parsed.merchant != null && parsed.note != null
            ? '${parsed.merchant} · ${parsed.note}'
            : noteParts.first);

    if (!mounted) return;
    setState(() {
      _type = nextType;
      _categories = cats;
      _categoryId = categoryId ?? (cats.isNotEmpty ? cats.first.id : null);
      _accountId = accountId;
      _toAccountId = toAccountId;
      _amountText = amountText;
      _noteCtrl.text = noteText;
      if (parsed.happenAt != null) {
        _happenAt = parsed.happenAt!;
      }
      _fieldEpoch++;
      _aiExpanded = false;
    });

    final summary =
        parsed.hits.isEmpty ? '已预填' : '已预填：${parsed.hits.join(' · ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

'''

if "_applyAiTextFill" not in text:
    marker = "  @override\n  Widget build(BuildContext context) {"
    if marker not in text:
        raise SystemExit("build marker missing")
    text = text.replace(marker, apply_method + marker, 1)

# --- UI block: insert after type SegmentedButton row ---
ui_block = r'''
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _aiExpanded = !_aiExpanded),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '智能填单',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: scheme.primary),
                                ),
                              ),
                              Text(
                                '话术预填 · 本地规则',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                              Icon(
                                _aiExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_aiExpanded) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _aiTextCtrl,
                                minLines: 1,
                                maxLines: 3,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _applyAiTextFill(),
                                decoration: const InputDecoration(
                                  hintText: '例：午餐花了28.5 / 昨天支付宝地铁4元',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : _applyAiTextFill,
                              child: const Text('填入'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
'''

# Insert UI after the type/close Padding block that ends before amount Padding
anchor_ui = """                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      if (_amountHasOperator)
"""

if "智能填单" not in text:
    if anchor_ui not in text:
        raise SystemExit("UI anchor missing")
    text = text.replace(anchor_ui, ui_block + "\n" + anchor_ui, 1)

# --- Key dropdowns so AI fill refreshes selection ---
# Replace initialValue account dropdowns with key+value pattern carefully.
# Flutter 3.33+ uses initialValue; force rebuild via Key(_fieldEpoch).

def add_epoch_key(block_start: str) -> None:
    global text
    # Find DropdownButtonFormField after a marker and inject key if missing nearby
    pass

# Inject keys on the three DropdownButtonFormField widgets
text2 = text
# Pattern: DropdownButtonFormField<String>(\n                             initialValue:
old_dd = "DropdownButtonFormField<String>(\n                            initialValue:"
new_dd = (
    "DropdownButtonFormField<String>(\n"
    "                            key: ValueKey('dd-$_fieldEpoch-' +\n"
    "                                '${_accountId}_${_toAccountId}_$_type'),\n"
    "                            initialValue:"
)
# Only first occurrence might be too few — replace all
if "key: ValueKey('dd-" not in text2 and old_dd in text2:
    text2 = text2.replace(old_dd, new_dd)

text = text2

sheet.write_text(text, encoding="utf-8")
print("patched bookkeeping_sheet.dart", sheet.stat().st_size)
print("done")
