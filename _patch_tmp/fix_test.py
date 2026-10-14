from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\test\export_import_budgets_test.dart")
t = p.read_text(encoding="utf-8")
t = t.replace("import 'package:drift/drift.dart';\n", "")
old = """    final result = await svc.restore(bundle);
    expect(result.budgets, 2);
    final rows = await db.loadBudgetsForExport('led1');
    expect(rows, hasLength(2));
    expect(rows.map((e) => e.amountMinor).toSet(), {500000, 100000});
"""
new = """    final result = await svc.restore(bundle);
    expect(result.budgets, 2);
    final all = await db.select(db.budgets).get();
    // ignore: avoid_print
    print('all budgets=${all.length} $all');
    expect(all, hasLength(2));
    final rows = await db.loadBudgetsForExport('led1');
    expect(rows, hasLength(2));
    expect(rows.map((e) => e.amountMinor).toSet(), {500000, 100000});
"""
if old not in t:
    raise SystemExit('block missing: ' + repr(t[t.find('svc.restore'):t.find('svc.restore')+400]))
p.write_text(t.replace(old, new, 1), encoding="utf-8")
print('updated')
