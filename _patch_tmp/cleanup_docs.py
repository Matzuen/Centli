from pathlib import Path
# clean test debug
p = Path(r"D:\Resource\Codebase\studyProject\Centli\test\export_import_budgets_test.dart")
t = p.read_text(encoding="utf-8")
t = t.replace("""    final all = await db.select(db.budgets).get();
    // ignore: avoid_print
    print('all budgets=${all.length} $all');
    expect(all, hasLength(2));
    final rows = await db.loadBudgetsForExport('led1');
""", """    final rows = await db.loadBudgetsForExport('led1');
""")
p.write_text(t, encoding="utf-8")
print("test cleaned")

# update analysis doc status
ap = Path(r"D:\Resource\Codebase\studyProject\Centli\docs\budget_export_import_analysis.md")
a = ap.read_text(encoding="utf-8")
if not a.startswith("**Status: IMPLEMENTED"):
    a = "**Status: IMPLEMENTED** (2026-10-14) — JSON/Excel export + import restore include `budgets`.\n\n" + a
    ap.write_text(a, encoding="utf-8")
print("analysis marked")

# schema note
sp = Path(r"D:\Resource\Codebase\studyProject\Centli\docs\Centli_schema.md")
s = sp.read_text(encoding="utf-8")
if "export budgets" not in s and "导出含 budgets" not in s:
    # append to changelog if present
    marker = "| 2 | 新增 budgets"
    # find changelog lines - try several encodings/forms
    if "| 2 |" in s and "budgets" in s:
        # add a note after changelog table row for version 2
        note = "\n\n### 导出/导入（应用层）\n\n- `centli-export` JSON：`schema_version: 2` 起包含 `budgets` 数组（缺省则导入为空列表，兼容旧备份）。\n- Excel：`budgets` sheet；导入仍仅支持 JSON。\n- 还原：`restoreFromImportBundle` 清空后写回 budgets。\n"
        if "### 导出/导入" not in s:
            s = s.rstrip() + note
            sp.write_text(s, encoding="utf-8")
            print("schema note added")
        else:
            print("schema note exists")
    else:
        print("changelog marker odd; skip")
else:
    print("schema already notes export")
