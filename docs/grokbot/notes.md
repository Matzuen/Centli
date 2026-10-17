# Centli B4 execution notes

Baseline (work-order): commit `a1869f1` · schema v7 · tests 150
Start HEAD: `e0c3d5f` (B3 finished; did not reset)
Stash kept: `stash@{0}: pre-r2-workdir-auto-accounting-wip`

## Subtask → commit

| Subtask | Commit | Notes |
|---------|--------|-------|
| T0A-1 | `7e79f08` | Strict tabs; watchPendingOk/Confirmed; remove watchAllCaptures |
| T0A-2 | `633b376` | Badge by status first |
| T0A-3 | `ce7ffa5` | showSelectedIcon:false, compact, no scroll |
| T0A-4 | `08e81ad` | pending_tabs_test partition/badge/320dp |
| T0A-5 | `184db92` | legacy tab=all alias documented |
| T0B-1 | `a5b8a2a` | kDirections += repay |
| T0B-2 | `c5f0688` | alipay_repay_zh Dart/JSON/native (shared commit with 3/4) |
| T0B-3 | `c5f0688` | reminder excludes |
| T0B-4 | `c5f0688` | kAmountRegexYuan |
| T0B-2..4 tests | `85e69f4` | notification_parse_test group |
| T0B-5 | (pending) | repay exclude stats |
| T0B-6 | (pending) | dedupe test |

## T0A answers (§6.2)

1. Filters: pending=`status=pending AND parseOk=1`; parse_failed=`pending AND parseOk=0`; ignored=`ignored`; confirmed=`status NOT IN (pending,ignored)`
2. confirmed+parseOk=0 → 已入账 (pendingCaptureBadgeLabel); tested
3. SegmentedButton at 320dp content width: Size(288.0, 40.0); width stable across tabs

## T0B answers (§6.2)

5. Huabei sample → ok=true, direction=repay, amountMinor=1254, templateId=alipay_repay_zh; tests `待还 reminder is excluded` / `应还 reminder is excluded`
6. Primary amountRegex then kAmountRegexYuan; 10月/ISO null; 实付¥16.93，0.5元红包 → 1693
7. repay confirm includeInStat=0 → expense unchanged; include=1 → +amount (repay_stats_test)

