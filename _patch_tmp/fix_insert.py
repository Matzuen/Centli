from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\data\db\centli_database.dart")
t = p.read_text(encoding="utf-8")
old = """      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final t in txnRows) {
        await into(transactions).insert(t.toCompanion(true));
      }
"""
new = """      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final b in budgetRows) {
        await into(budgets).insert(b.toCompanion(true));
      }
      for (final t in txnRows) {
        await into(transactions).insert(t.toCompanion(true));
      }
"""
if "for (final b in budgetRows)" in t and "await into(budgets).insert(b.toCompanion(true))" in t:
    print("already present")
else:
    if old not in t:
        raise SystemExit("insert site not found")
    t = t.replace(old, new, 1)
    p.write_text(t, encoding="utf-8")
    print("insert loop added")

# verify
t = p.read_text(encoding="utf-8")
assert "await into(budgets).insert(b.toCompanion(true))" in t
print("verified")
