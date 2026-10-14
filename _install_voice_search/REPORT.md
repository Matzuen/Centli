# Centli — Voice fill + Stronger search (report)

Date: 2026-10-14 (Asia/Shanghai)

## Goal
1. Voice fill for bookkeeping: speech_to_text → existing AI text fill (`parseBookkeepingText`)
2. Stronger search: filters by type / category / account / date range beyond keyword
Constraint: local only, no Centli cloud

## Baseline (before)
- AI text fill (P3) already landed: `lib/features/ledger/ai_text_fill.dart` + expandable UI in `bookkeeping_sheet.dart`. Rule-based local NLP; no LLM.
- Search (P2) keyword-only: note / merchant / amount. Empty query cleared results.
- Reusable date UI: `DateRangeWindow` + `showCentliDateRangeSheet`.
- No speech dependency or mic permission.

## Implemented

### Voice → AI text fill
- NEW `lib/features/ledger/local_speech.dart` — facade, `onDevice: true`, prefers zh locale
- `bookkeeping_sheet.dart` — mic beside 填入; final transcript → `_aiTextCtrl` → `_applyAiTextFill()`
- `pubspec.yaml` — `speech_to_text: ^7.3.0` (resolved 7.5.0)
- Android `RECORD_AUDIO` + RecognitionService query; iOS mic + speech usage strings
- Privacy bullet for voice fill

Pipeline: mic → OS STT (on-device preferred) → text → existing parseBookkeepingText → form fields.

Caveat: if OS has no offline language pack, listen fails with SnackBar (no silent cloud fallback). Embedded Vosk/Whisper not added.

### Stronger search
- `searchTransactions` optional filters: type, categoryId, accountId, startMs, endMs; empty keyword OK when any filter set; account matches accountId OR toAccountId
- `search_page.dart` filter sheet + chips; reuses date range sheet

## Verification
- `flutter analyze` on touched ledger files: No issues
- `flutter test test/ai_text_fill_test.dart`: All 8 passed

## Follow-ups
- Device QA with offline Chinese STT pack (Android/iOS/Windows)
- Optional: listening UI polish, persist filters, embedded STT if OS on-device insufficient
