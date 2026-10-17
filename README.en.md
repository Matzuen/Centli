# Centli

Local-first personal bookkeeping (**Chinese UI only**): **clear every bill**.

> Canonical docs are in Chinese: see [`README.md`](README.md) and [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md).

- Flutter · Drift (SQLite) · Riverpod · go_router
- Version: `1.4.2+8`
- Currency display: `CNY · 人民币`
- Bottom nav (5 tabs): 首页 / 统计 / 记账 / 资产 / 我的

## Features

- Home: summary + net-worth chart; calendar cells show daily in/out
- Manual transactions (expense / income / transfer); chip row + category picker; amount keypad with `+ − × ÷`
- Separate text / voice bookkeeping sheets; long-press center tab for shortcuts
- Transaction tags (list / detail / search / import-export)
- Multi-ledger, accounts, category tree; icons from assets or 1–2 hanzi fallback
- Stats: income + expense; monthly budgets
- Android pending auto-capture from WeChat/Alipay **payment** notifications only
- Recognition rules: official read-only + user CRUD + try-parse + import/export
- Smart fill: local rules + optional LLM
- FX rates; hide amounts; app lock; theme light/dark/system
- Local backup only: full **JSON** restore (`schema_version: 4`); **Excel** human export + best-effort import (no cloud)
- Android home widget (MVP); no iOS widget yet

## Run / release APK

```bash
flutter pub get
flutter run
dart run build_runner build --delete-conflicting-outputs   # after schema changes
flutter test
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

Windows: enable Developer Mode for Flutter symlinks. Prefer hot restart for UI work.

## Backup

Prefer JSON (`format: centli-export`). Excel import is best-effort (no fx/settings sheets). See Chinese README for details.

## Docs

- `docs/Centli_schema.md`
- `docs/Centli_pages_wireframes.md`
- `docs/recognition_rules.md`
- `docs/remaining_features_gap.md`
- `docs/RELEASE_NOTES.md` (Chinese release notes for stores / GitHub Releases)

## Changelog

> **Versioning** (since 2026-10-17): the minor digit is the **batch number**, so work order
> batch 4 ships as `1.4.x`. There is no `1.2` / `1.3` because those batches were never
> released under this scheme. Fixes within a batch bump the patch digit
> (`1.4.1` → `1.4.2`); the build number increments by 1 on every release.

### 1.4.2 (2026-10-17)
- Fix misleading smart-fill API base URL hint (DeepSeek usually needs no /v1)
- Near-miss DeepSeek model names get a one-tap typo fix hint
- Drop the member field (legacy values merged into note)
- Merge text + voice bookkeeping into Quick Bookkeeping (long-press bottom 「记一笔」)
- Screenshot bookkeeping entry on home (scanner icon) and inside the quick sheet

### 1.4.1 (2026-10-17)
- B4: custom asset types; DeepSeek vision for screenshot booking; hold-to-talk voice; pending tab split + repay notifications; drop subscriptions
- B4-PATCH: stricter goldens + MaterialIcons; smart-fill error detail & test connection; single-source version guard
- Bookkeeping panel: type switcher + single chip row; remove currency chip, txn templates, and member chip
- Tighter home calendar cells; remove one-shot scripts

### 1.1.3 (2026-10-17)
- Bookkeeping panel: remove member chip

### 1.1.2 (2026-10-17)
- Fix pending-page tab data loss; capture credit/Huabei repayment notifications
- Golden tests: strict compare + MaterialIcons; remove one-shot scripts
- Surface LLM vision HTTP error details; smart-fill test connection; migrate stale gpt models
- Tighter calendar cell row height; remove txn templates; panel type switcher + chip row (layout)
