# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(f"NOT FOUND: {label}")
    return text.replace(old, new, 1)

p = ROOT / "lib/data/export/import_service.dart"
t = p.read_text(encoding="utf-8")

if "required this.budgets," not in t.split("class ImportBundle")[1][:600]:
    t = must_replace(t, """    required this.fxRates,
    required this.settings,
  });

  final Map<String, dynamic> raw;
  final int exportVersion;
  final int schemaVersion;
  final String? exportedAt;
  final String? appVersion;
  final Map<String, dynamic> ledger;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> merchantRules;
  final List<Map<String, dynamic>> pendingCaptures;
  final List<Map<String, dynamic>> fxRates;
  final Map<String, String> settings;
""", """    required this.fxRates,
    required this.budgets,
    required this.settings,
  });

  final Map<String, dynamic> raw;
  final int exportVersion;
  final int schemaVersion;
  final String? exportedAt;
  final String? appVersion;
  final Map<String, dynamic> ledger;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> merchantRules;
  final List<Map<String, dynamic>> pendingCaptures;
  final List<Map<String, dynamic>> fxRates;
  final List<Map<String, dynamic>> budgets;
  final Map<String, String> settings;
""", "ImportBundle fields")

if "required this.budgets," not in t.split("class ImportResult")[1][:500]:
    t = must_replace(t, """class ImportResult {
  const ImportResult({
    required this.ledgerId,
    required this.ledgerName,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.settingsWritten,
  });

  final String ledgerId;
  final String ledgerName;
  final int accounts;
  final int categories;
  final int transactions;
  final int merchantRules;
  final int pendingCaptures;
  final int fxRates;
  final int settingsWritten;
}
""", """class ImportResult {
  const ImportResult({
    required this.ledgerId,
    required this.ledgerName,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.budgets,
    required this.settingsWritten,
  });

  final String ledgerId;
  final String ledgerName;
  final int accounts;
  final int categories;
  final int transactions;
  final int merchantRules;
  final int pendingCaptures;
  final int fxRates;
  final int budgets;
  final int settingsWritten;
}
""", "ImportResult")

if "map['budgets']" not in t:
    t = must_replace(t, """    final fx = _asMapList(map['fx_rates'], 'fx_rates')
        .map(_normalizeFx)
        .toList();

    final settings = <String, String>{};
""", """    final fx = _asMapList(map['fx_rates'], 'fx_rates')
        .map(_normalizeFx)
        .toList();
    final budgetRows = _asMapList(map['budgets'], 'budgets')
        .map(_normalizeBudget)
        .toList();

    final settings = <String, String>{};
""", "parse budgets")

if "Budget.fromJson(b)" not in t:
    t = must_replace(t, """      for (final f in fx) {
        FxRate.fromJson(f);
      }
    } catch (e) {
""", """      for (final f in fx) {
        FxRate.fromJson(f);
      }
      for (final b in budgetRows) {
        Budget.fromJson(b);
      }
    } catch (e) {
""", "dry-run Budget")

if "budgets: budgetRows," not in t:
    t = must_replace(t, """      fxRates: fx,
      settings: settings,
    );
""", """      fxRates: fx,
      budgets: budgetRows,
      settings: settings,
    );
""", "ImportBundle return")

if "budgetMaps: bundle.budgets," not in t:
    t = must_replace(t, """      fxRateMaps: bundle.fxRates,
      settingsMap: bundle.settings,
""", """      fxRateMaps: bundle.fxRates,
      budgetMaps: bundle.budgets,
      settingsMap: bundle.settings,
""", "restore budgetMaps")

if "budgets: stats.budgets," not in t:
    t = must_replace(t, """      fxRates: stats.fxRates,
      settingsWritten: stats.settingsWritten,
""", """      fxRates: stats.fxRates,
      budgets: stats.budgets,
      settingsWritten: stats.settingsWritten,
""", "ImportResult budgets")

if "static Map<String, dynamic> _normalizeBudget" not in t:
    t = must_replace(t, """  static Map<String, dynamic> _normalizeFx(Map<String, dynamic> m) {
    m.putIfAbsent('updatedAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }
}
""", """  static Map<String, dynamic> _normalizeFx(Map<String, dynamic> m) {
    m.putIfAbsent('updatedAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }

  static Map<String, dynamic> _normalizeBudget(Map<String, dynamic> m) {
    m.putIfAbsent('categoryId', () => '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    m.putIfAbsent('createdAt', () => ts);
    m.putIfAbsent('updatedAt', () => ts);
    return m;
  }
}
""", "_normalizeBudget")

p.write_text(t, encoding="utf-8")
print("IMPORT OK")
