# -*- coding: utf-8 -*-
"""Compare docs feature intents vs lib implementation (heuristic)."""
from pathlib import Path
import re
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
lib_files = list((ROOT/"lib").rglob("*.dart"))
lib_text = "\n".join(f.read_text(encoding="utf-8", errors="ignore") for f in lib_files)
docs = {p.name: p.read_text(encoding="utf-8", errors="ignore") for p in (ROOT/"docs").glob("*.md")}

def has(*needles):
    return all(n in lib_text for n in needles)

# Feature checklist from wireframes + plans
features = [
    ("P0 Splash / onboarding", has("SplashPage", "OnboardingPage")),
    ("P0 Manual bookkeeping sheet", has("BookkeepingSheet")),
    ("P0 Ledger detail / txn list", has("LedgerDetailPage")),
    ("P0 Assets / accounts", has("AssetsPage", "AccountDetailPage")),
    ("P0 Me / settings shell", has("MePage")),
    ("P0 Categories CRUD", has("CategoriesPage")),
    ("P1 Pending captures + notification ingest", has("PendingPage", "NotificationIngestBridge")),
    ("P1 Auto-capture settings", has("AutoCapturePage")),
    ("P2 Stats", has("StatsPage")),
    ("P2 App lock / security", has("AppLockPage", "AppLockService")),
    ("P2 Hide amount", "hide_amount" in lib_text or "hideAmount" in lib_text),
    ("P2 Export JSON/Excel", has("ExportService", "ExportPage")),
    ("P2/P3 Import JSON restore", has("ImportService", "ImportPage")),
    ("P3 Budgets UI", has("BudgetPage", "upsertBudget")),
    ("P3 Budgets in export+import", "'budgets': budgetRows" in lib_text and "budgetMaps" in lib_text and "into(budgets).insert(b.toCompanion" in lib_text),
    ("P3 AI text fill", has("ai_text_fill") or "AiTextFill" in lib_text or "aiTextFill" in lib_text),
    ("P3 Voice / local speech", has("LocalSpeech") or "local_speech" in lib_text),
    ("P3 Home widget Android", has("CentliHomeWidgetSync") or "home_widget" in lib_text),
    ("P2+ FX rates page + remote", has("FxRatesPage", "FxRemoteService")),
    ("P2 Search", has("SearchPage")),
    ("Privacy / about / permission explain", has("PrivacyPolicyPage", "AboutPage", "PermissionExplainPage")),
]

print("=== Implemented (heuristic) ===")
for name, ok in features:
    print(("DONE" if ok else "GAP "), name)

# Doc-mentioned gaps / future
print("\n=== Doc signals (remaining / stretch) ===")
wire = docs.get("Centli_pages_wireframes.md", "")
plan = docs.get("android_auto_ledger_plan.md", "")
home = docs.get("centli_home_widget.md", "")
notif = docs.get("Centli_notification_parse.md", "")

# Extract [P3] lines and optional items
for label, text in [("wireframes", wire), ("auto_ledger", plan), ("home_widget", home), ("notif", notif)]:
    for line in text.splitlines():
        if re.search(r"\[P3\]|P1\.5|可选|后续|暂不|未做|占位", line):
            line = line.strip()
            if len(line) > 8:
                print(f"[{label}] {line[:120]}")
