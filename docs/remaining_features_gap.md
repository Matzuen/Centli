# Remaining unfinished features vs docs (short)

Updated 2026-10-14 after gap batch (Excel restore, theme, recycle, ledgers, ignored hub, README).

## Done in this batch

- **Excel restore** — best-effort `.xlsx` import from Centli export sheets; UI accepts JSON + xlsx; limitations documented in import UI / `ImportService.excelRestoreLimitations`. Prefer JSON for lossless backup.
- **Theme picker** — `theme_mode` setting + `themeModeProvider`; Me → 主题 (system / light / dark).
- **Soft-delete recycle UI** — `RecycleBinPage` (`/me/recycle`): undelete / purge / purge all.
- **Multi-ledger manager** — `LedgersPage` (`/me/ledgers`): create with defaults, switch current, archive/unarchive, edit.
- **Pending ignored history hub** — Pending tab `ignored` + clear ignored + unignore to pending; Me shortcut `/home/pending?tab=ignored`.
- **README** — real product docs (`README.md` / `README.en.md`), not Gitee template.

## Still open / skipped

- **iOS home widget** — skipped (Android MVP only).
- **Notification multi-currency (P1.5)** — skipped unless easy; still CNY-centric MVP.
- **Schema doc layout drift** — optional paths in docs only.
- **Cloud sync** — out of scope by design.

## Earlier (still true)

- Budgets in JSON/Excel export + import restore (`schema_version: 2`).
- AI voice/text fill, budget page, stats progress — present.
