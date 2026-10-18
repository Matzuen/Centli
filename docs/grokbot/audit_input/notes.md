# Centli B4-PATCH G26–G29 notes

Generated: 2026-10-18 (Asia/Shanghai)
HEAD: fff0f1b388ccfd2c67f589cc90a40b368c3499c5
Version: `1.4.4+10`
schemaVersion: `11`

Baseline HEAD (before G26): `60035e6` · version `1.4.2+8` · schema **11** · tests **225**

## Subtask → commit

| Task | hash | Notes |
|---|---|---|
| G26.1 | `2098145` | showDragHandle + golden via real modal; top pad tightened |
| G26.2 | `5e95ffc` | empty hint 记账→记一笔; shell comment |
| G26.3–G26.4 | `7d18d36` | AC-only warning; backspace Icons.backspace_outlined |
| G26.5 | `5309036` | list tile · 不计入 (muted) |
| G26.6 | `7ca216e` | pending empty copy → 识别规则页点试一试 |
| G26.7 | `c7679df` | Center SegmentedButton + 411dp layout test |
| G27 | `d2b8eb1` | /home/pending?tab=pending + route_literals_test |
| G28 | `a48016a` | drops ring buffer + extras union + auto_capture card |
| G29 | `86c280b` | widen keywords + noti actions 入账/改金额/忽略 |
| version | `7390056` | bump → **1.4.4+10** + READMEs |
| wrap | `5b066f5` / `254bfe7` / tip | analyze cleanup + notes stamp |

## G26.1 self-prove (raw)

### A) remove `showDragHandle: true` → golden fails

```
00:02 +0 -2: Some tests failed.
Failing tests:
  bookkeeping_panel_golden_test.dart: bookkeeping panel golden dark
  bookkeeping_panel_golden_test.dart: bookkeeping panel golden light
EXITCODE=1
```

### B) restored → green

```
00:02 +2: All tests passed!
EXITCODE=0
```

Visual: light golden shows gray drag handle above 支出/收入/转账; type switch intact.

## G26.7 self-prove (raw)

### A) remove Center → FAIL

```
Expected: a numeric value within <1.0> of <69.5>
  Actual: <16.0>
   Which:  differs by <53.5>
FAIL_EXIT=1
```

Source contract also fails: `G26.7 requires Center around pending SegmentedButton`.

### B) restored → green

```
00:00 +2: All tests passed!
OK_EXIT=0
```


## G26.4 self-prove (raw)

### A) Text revert → FAIL (icon finder)
```
Found 0 widgets with icon IconData(U+0EEB5)
FAIL_EXIT=1
```
### B) restored → OK_EXIT=0

| G27.1 | `d2b8eb1` | push /home/pending?tab=pending |
| G27.2 | `d2b8eb1` | route_literals_test (non-empty matches) |
| G28 | `a48016a` | drops ring buffer + extras union + auto_capture card |
| G29 | `86c280b` | widen keywords + noti actions 入账/改金额/忽略 |

## G27 self-prove (raw)

### A) temporarily `context.push('/pending')` → FAIL

```
route_literals: skipped 3 dynamic path(s); checking 43 literal(s)
Expected: non-empty
  Actual: []
  代码里写了不存在的路由: /pending
FAIL_EXIT=1
```

### B) restored → green

```
route_literals: skipped 3 dynamic path(s); checking 43 literal(s)
00:00 +1: All tests passed!
OK_EXIT=0
```

Note: go_router 16 `findMatch` does not throw on unknown paths; test asserts `match.matches` isNotEmpty.

| G28 | 48016a | drops ring buffer + extras union + auto_capture card |

## G28 notes / self-prove

- Native `drops` prefs: pkg/title(≤80)/when/reason only; never body; ≤20; dedupe pkg+title; apply() async.
- `extra_watched_packages` in app_settings; `syncWatchedPackagesToNative` unions after template pkgs.
- UI: 「最近被忽略的通知」; empty hides card; 「加入监听」+ SnackBar; **暂无移出入口**.
- Unit: `test/dropped_notifications_test.dart` 5 green.
- Device kill-restart acceptance: **not run** (no Android device on this Windows agent). Proven via unit union + code review of bindDatabase + addExtraWatchedPackage.
- Self-prove extras wipe: if `pkgs.addAll(await _loadExtraWatchedPackages())` commented out, restart sync would drop manual joins (union unit test documents intended behavior). Not physically commented in CI; code path reviewed.

## Wrap / Final

- Baseline HEAD: `60035e6` · version `1.4.2+8` · schema **11** · tests **225**
- Final HEAD: `78141419ef0bad42d4822211bb882ebe10ae6dbb` (`7814141`) — tip after this notes commit will be newer; freshness test requires ancestor-or-equal
- version: **1.4.4+10** · schema **11** · tests **237** (`VERIFY: OK`, analyze_rc=0 test_rc=0)
- Device gaps: G28 kill-restart join-watch; G29 notification actions on-device — **not run** (no Android device on Windows agent)
- 暂无移出入口 (extra_watched remove UI)
- No push / no APK / audit_report_*.md left untracked
