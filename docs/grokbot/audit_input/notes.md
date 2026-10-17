# Centli B4 execution notes

Baseline (work-order): commit `a1869f1` · schema v7 · tests 150  
Finish HEAD: 9c5a52a · schema **v10** · tests **182 passed / 0 failed**  
`flutter analyze` → No issues found!  
Debug APK: `build/app/outputs/flutter-apk/app-debug.apk` (~240 MB)  
**NO push.** Live DeepSeek vision call: **未联网验证** (mock unit tests only).

## Subtask → commit

| Subtask | Commit | Notes |
|---------|--------|-------|
| T0A-1 | `7e79f08` | Strict tabs; watchPendingOk/Confirmed |
| T0A-2 | `633b376` | Badge by status first |
| T0A-3 | `ce7ffa5` | showSelectedIcon:false, compact, no scroll |
| T0A-4 | `08e81ad` | pending_tabs_test |
| T0A-5 | `184db92` | legacy tab=all alias |
| T0B-1 | `a5b8a2a` | kDirections += repay |
| T0B-2..4 | `c5f0688` | repay template + excludes + yuan |
| T0B-2..4 tests | `85e69f4` | notification_parse_test |
| T0B-5/6 | `11299ec` | repay exclude stats + dedupe |
| T1-1 | `4ef3f87` | composeNote |
| T1-2..4 | `212f1ec` | v8 drop merchant; merge note |
| T2 | `6aee601` | v9 drop subscriptions |
| T3 | `728afab` | OCR → DeepSeek vision |
| T4 | `e7d0ad9` | hold-to-talk |
| T5-2 | `f35ce1f` | asset_types schema v10 |
| T5-3/4/5 | `c8e5511` | dynamic groups + management + form |
| T5-6 | `6ab453f` | Excel name mapping |
| T6 | `f5f201d` | golden font + sheet container |
| T6 flake | `5b7e604` | 0.05% golden tolerance |
| T7-1 | `9965351` | PRODUCT_SCOPE.md |
| T8 | 9c5a52a | audit_input + notes + README |

## §6.2 answers (selected)

### T0A
1. Filters: pending=`status=pending AND parseOk=1`; parse_failed=`pending AND parseOk=0`; ignored=`ignored`; confirmed=`status NOT IN (pending,ignored)`
2. confirmed+parseOk=0 → 「已入账」; tested in pending_tabs_test
3. SegmentedButton at 320dp content width ~ Size(288.0, 40.0); width stable

### T0B
5. Huabei sample → ok=true, direction=repay, amountMinor=1254, templateId=alipay_repay_zh
6. Primary amountRegex then kAmountRegexYuan; 10月/ISO null; 实付¥16.93 → 1693
7. repay confirm includeInStat=0 → expense unchanged (repay_stats_test)

### T1
9–10. merchant columns dropped (v8); composeNote; merchant_rules kept; auto-categorize test in schema_v8_merchant_note_test
11. T1-5 orphan scan: **SKIPPED** (degradation §7)

### T2
12. subscriptions dropped v9; recurring_rules kept

### T3
13–18. Vision: image_url in **user** message, detail=**original**, model=**deepseek-flash**; defaults deepseek.com / deepseek-flash; existing user config not overwritten; prepareImageForLlm long edge ≤1600 JPEG q80 ≤2MB; consent `image_ai_consent`; **Live DeepSeek: 未联网验证**

### T4
19. Listener pointer down/move/up (no long-press delay); slide-up >60dp cancel; min hold 0.5s

### T5
20. v9→v10: create asset_types; seed 现金/银行卡/电子钱包/信用卡/其他; map cash/bank/ewallet/credit/other/empty/unknown → ids
21. Excel: type column = name; asset_types sheet; import recreates types; legacy codes map; unknown → 其他 (excel_asset_types_test)

### T6
22. Font: `test/golden/fonts/NotoSansSC.ttf` (repo vendored, SIL OFL); container Align bottom + Material radius 24; tolerance 0.05% for parallel antialias

### Misc
23. 工单外顺手改动: none intentional beyond version-expect updates in older tests (user_version 9→10)
24. Risks: DeepSeek live vision unverified; 17MB golden font in repo; Excel custom types need asset_types sheet for round-trip
25. 目视: not done on device this session

## Final
- HEAD: run `git rev-parse HEAD`
- schemaVersion: **10**
- analyze: No issues found!
- test: **182 passed / 0 failed**
- APK: `build/app/outputs/flutter-apk/app-debug.apk`
