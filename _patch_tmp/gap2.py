# -*- coding: utf-8 -*-
from pathlib import Path
import sys
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
out = []
def log(s=""):
    out.append(s)

lib = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in (ROOT/"lib").rglob("*.dart"))
docs = {p.name: p.read_text(encoding="utf-8", errors="ignore") for p in (ROOT/"docs").glob("*.md")}

def any_in(*ns):
    return any(n in lib for n in ns)

checks = [
    ("Budget progress on Stats page", "Budget" in Path(ROOT/"lib/features/stats/stats_page.dart").read_text(encoding="utf-8", errors="ignore") or "budget" in Path(ROOT/"lib/features/stats/stats_page.dart").read_text(encoding="utf-8", errors="ignore").lower()),
    ("Excel import (docs: JSON only OK as P2 export; import Excel not required)", "xlsx" in Path(ROOT/"lib/data/export/import_service.dart").read_text(encoding="utf-8", errors="ignore").lower()),
    ("Biometric app lock", any_in("local_auth", "biometric", "Biometric")),
    ("Theme dark/light toggle beyond system", any_in("ThemeMode", "themeMode", "Brightness.dark")),
    ("iOS home widget", (ROOT/"ios").exists() and any("widget" in p.name.lower() for p in (ROOT/"ios").rglob("*") if p.is_file())),
    ("Soft-delete recycle / restore deleted txns UI", any_in("Recycle", "回收站", "deletedAt") and "DeletedTxn" in lib),
    ("Multi-ledger switcher beyond current_ledger", lib.count("LedgersPage")>0 or "切换账本" in lib or "SwitchLedger" in lib),
    ("Notification multi-currency $ € (P1.5)", "$" in Path(ROOT/"lib/platform/notifications/notification_parse.dart").read_text(encoding="utf-8", errors="ignore") if (ROOT/"lib/platform/notifications/notification_parse.dart").exists() else False),
    ("Cloud sync", any_in("firebase", "supabase", "icloud", "CloudSync")),
    ("Transfer FX in bookkeeping", "toAmountMinor" in lib and "fxRate" in lib),
]

log("Remaining / partial vs docs (short):")
# Always-list known doc ambitions that look unfinished
remaining = []

stats = Path(ROOT/"lib/features/stats/stats_page.dart").read_text(encoding="utf-8", errors="ignore")
if "budget" not in stats.lower() and "Budget" not in stats:
    remaining.append("Stats page: wireframes say show monthly budget progress — not wired on StatsPage")

imp = Path(ROOT/"lib/data/export/import_service.dart").read_text(encoding="utf-8", errors="ignore")
if "xlsx" not in imp.lower() and "excel" not in imp.lower():
    remaining.append("Excel import: docs/UI say JSON-only restore — Excel remains export/view-only (acceptable unless product wants Excel restore)")

sec = Path(ROOT/"lib/features/security").rglob("*.dart")
sec_t = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in sec)
if "biometric" not in sec_t.lower() and "local_auth" not in lib:
    remaining.append("App lock biometric (settings key app_lock_biometric exists in import skip list; full biometric UX may be thin/missing)")

# theme
if "ThemeMode" not in lib and "themeMode" not in lib:
    remaining.append("Explicit light/dark theme picker (plan mentions 浅色/深色; may rely on system only)")

# home widget ios
ios_widgets = list((ROOT/"ios").rglob("*Widget*")) if (ROOT/"ios").exists() else []
if not ios_widgets:
    remaining.append("iOS home widget (Android MVP documented; iOS not in MVP)")

# multi currency notif
np = ROOT/"lib/platform/notifications/notification_parse.dart"
if np.exists():
    npt = np.read_text(encoding="utf-8", errors="ignore")
    if "USD" not in npt and "$" not in npt:
        remaining.append("Notification amount regex multi-currency ($/€) — docs mark P1.5 extension")

# soft delete UI
if "回收" not in lib and "RecycleBin" not in lib:
    remaining.append("Soft-deleted txn browser/restore UI (export can include deleted; no recycle-bin page)")

# multi ledger management UI
if "账本管理" not in lib and "LedgersPage" not in lib:
    # me page might have ledger rename only
    remaining.append("Multi-ledger management UI (schema supports ledgers; product may be single-ledger MVP)")

# ignored pending history
if "ignored" in lib and "IgnoredPage" not in lib:
    remaining.append("Pending 'ignored' history hub (wireframe P2 optional)")

# README still placeholder
readme = (ROOT/"README.md").read_text(encoding="utf-8", errors="ignore")
if "xxxx" in readme:
    remaining.append("README still Gitee template placeholders (not product docs)")

# money_converter path in schema
if not list((ROOT/"lib").rglob("*money_converter*")):
    remaining.append("docs/schema optional money_converter.dart / daos/ layout — money helpers live in core/utils (doc drift only)")

# cloud
if not any(x in lib.lower() for x in ["firebase", "supabase", "cloud_sync"]):
    remaining.append("No cloud sync (out of local-first scope in plans — note only)")

for i, r in enumerate(remaining, 1):
    log(f"- {r}")

# Also peek wireframe P3 lines properly
log("\nFrom wireframes [P3] items status:")
wf = docs["Centli_pages_wireframes.md"]
for line in wf.splitlines():
    if "[P3]" in line or "`[P3]`" in line:
        log(f"  doc: {line.strip()[:140]}")

log("\nBudgets export/import: DONE (this change).")

Path(r"D:\Resource\Codebase\studyProject\Centli\docs\remaining_features_gap.md").write_text("\n".join(out)+"\n", encoding="utf-8")
print("\n".join(out))
