# B4-PATCH remaining notes (G16–G19)

Generated: 2026-10-17 (Asia/Shanghai)
HEAD: `5e37f87235f70efc46f3bb1a3dc91d017d35e891`
Version: `1.4.2+8`
schemaVersion: `11`

## Gate (raw verify outputs only)

### analyze (`docs/grokbot/audit_input/analyze.txt`)

```
Analyzing Centli...
No issues found! (ran in 4.4s)
```

exit code: `0` (verify analyze_rc=0)

### test (`docs/grokbot/audit_input/test.txt`)

```
00:09 +205: D:/Resource/Codebase/studyProject/Centli/test/widget_test.dart: money JPY has 0 decimals
00:09 +206: D:/Resource/Codebase/studyProject/Centli/test/widget_test.dart: money hide amount
00:09 +207: D:/Resource/Codebase/studyProject/Centli/test/widget_test.dart: DateRangeWindow last 30 days covers through today
00:09 +208: D:/Resource/Codebase/studyProject/Centli/test/widget_test.dart: DateRangeWindow prev shifts window back
00:09 +209: All tests passed!
```

exit code: `0` (verify test_rc=0) -> **209 passed / 0 failed**, VERIFY: OK

## Subtask -> commit

| Task | hash | Notes |
|---|---|---|
| G16 | `69d55bc` | model name typo hint (Levenshtein≤2) + /v1 helperText; self-proof threshold 0 → 3 failed |
| G17 | `833bd86` | drop member column, merge into note; schema v10→v11; v5 raw SQL; fixtures later |
| G18 | `6f8f74f` | QuickBookkeepingSheet; delete text sheet; long-press opens quick directly |
| G19 | `29207ee` | capture_intake_actions; home AppBar + quick sheet screenshot/clipboard; consent one place |
| bump | `22e53a8` | 1.4.2+8 + README x3 |
| analyze fix | `eacf161` | schema_v11 test fixtures (no sqlite3 dep); drop unused import |
| cleanup | `a82554d` | audit_input + notes; orphans/failures deleted |

## G16 self-prove

- Temp `kDeepSeekTypoMaxDistance = 0` → 3 tests failed (typo / one-tap / connection hint); restored → 6 passed

## G17

- Member merge separator ` · ` (U+00B7), order note · member
- v8 alterTable would drop member on long jumps → pre-merge when column exists before v8 alter; v11 guarded by `_hasTableColumn`
- schema_v11 tests use `test/fixtures/schema_v10_member.db` + `schema_v4.db`

## G18

- Title 快速记账; long-press → showQuickBookkeepingSheet; short-press manual unchanged
- Tests: 9 in quick_bookkeeping_test.dart (physics + hold + title + type/edit + submit units)

## G19

- Consent dialog title only in capture_intake_actions.dart
- Self-prove: rename consent title → privacy test failed; restored

## Cleanup

- Deleted untracked orphans: `account_identity.dart`, `account_mark.dart` (zero refs)
- Deleted `test/golden/failures/`
- Did not touch `docs/grokbot/audit_report_*.md`
