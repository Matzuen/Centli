# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
text = """# Remaining unfinished features vs docs (short)

Generated 2026-10-14 after implementing budgets in export/import.

## Just finished
- Budgets in JSON export (`budgets` array, `schema_version: 2`)
- Budgets Excel sheet + summary count
- Import parse/normalize/dry-run + restore re-insert (was wipe-only before)
- Import/export UI counts; tests in `test/export_import_budgets_test.dart`

## Still open / partial (vs docs & plans)

- **Excel restore** — UI/docs: import is JSON-only; Excel stays human-view export.
- **Theme picker** — `CentliTheme.dark()` exists but app uses `ThemeMode.system` only (no in-app light/dark toggle).
- **iOS home widget** — Android MVP in `docs/centli_home_widget.md`; no iOS widget target called out as done.
- **Notification multi-currency (P1.5)** — parse docs mention `$` / `€` extension beyond CNY-centric MVP.
- **Soft-delete recycle UI** — export can include deleted txns; no recycle-bin / undelete page.
- **Multi-ledger management** — schema supports many ledgers; product UX is largely single current-ledger MVP (no dedicated ledgers manager).
- **Pending “ignored” history hub** — wireframe optional P2; ignore exists, dedicated hub thin/absent.
- **README** — still Gitee template (`xxxx` placeholders), not product documentation.
- **Schema doc layout drift** — optional `daos/` / `money_converter.dart` paths not mirrored; money lives in `core/utils` (doc-only).
- **Cloud sync** — not in local-first scope; absent by design.

## P3 wireframe items (status)
- AI voice/text fill — present in codebase (`ai_text_fill`, `local_speech`).
- Budget page + stats progress — present (`BudgetPage`, `_StatsBudgetSection`).
- Budgets backup/restore — **done** (this change).

## Explicitly out of scope / note
- No cloud backup/sync in current plans.
"""
Path(ROOT/"docs/remaining_features_gap.md").write_text(text, encoding="utf-8")
print("wrote remaining_features_gap.md")
