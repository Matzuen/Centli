# Centli

Local-first personal bookkeeping (**Chinese UI only**): **clear every bill**.

- Flutter · Drift (SQLite) · Riverpod · go_router
- Version: `1.1.0+3`
- Currency display: `CNY · 人民币`
- Bottom nav (5 tabs): 首页 / 统计 / 记账 / 资产 / 我的

## Features

- Manual transactions (expense / income / transfer); bookkeeping sheet with chips + Finch-style category picker
- Multi-ledger, accounts, category tree; icons from assets or 1–2 hanzi fallback
- Stats: income + expense; monthly budgets
- Android pending auto-capture from WeChat/Alipay **payment** notifications only
- Recognition rules: official read-only + user CRUD + try-parse + import/export
- Smart fill: local rules + optional LLM
- FX rates; hide amounts; app lock; theme light/dark/system
- Local backup only: full **JSON** restore; **Excel** human export + best-effort import (no cloud)
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
