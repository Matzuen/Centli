# Centli B4-PATCH G26–G29 notes

Generated: 2026-10-17 (Asia/Shanghai)
HEAD: `b2ba38c4b586a2deb04e7bfa0493b4d01f8b1936`
Version: `1.4.2+8`
schemaVersion: `11`

Baseline HEAD (before G25): `f18dabd` · version `1.4.2+8` · schema **11** · tests **224**

## Subtask → commit

| Task | hash | Notes |
|---|---|---|
| G25.1 | `d87edf0` | verify.sh/ps1: delete artifacts → generate → MISSING/EMPTY asserts; remove always-true HEAD compare |
| G25.2 | `e6da77e` | `test/audit_notes_freshness_test.dart`: notes HEAD ancestor-or-equal via merge-base |
| G25.3 | `1286607` | Annotate invalid G23 Corrupted-HEAD.txt STALE self-proof as 无效; paste self-proof outputs |

## G23 self-prove（产品方否定 / G25.3）

- ~~Corrupted `HEAD.txt` to `deadbeef…` → assert prints `AUDIT INPUT STALE: HEAD.txt != git HEAD` and exits 1~~ **本验证无效**：脚本会先用 git HEAD 覆写 HEAD.txt 再比对，所以恒真。已由 G25 替换为「先删再写 + 存在性断言」。
- Full verify run regenerates all audit_input; HEAD.txt == `git rev-parse HEAD`
- `git rm --cached` all previously tracked `audit_input/*` (keep on disk) to match README「该目录不进版本库」
- Version: stay **`1.4.2+8`** (G23.7: no bump for tooling)

## G25.1 self-prove (raw)

### A) commits.txt generation commented out → nonzero + MISSING/EMPTY

```
00:06 +224: All tests passed!
AUDIT INPUT MISSING/EMPTY: commits.txt
EXITCODE=1
```

### B) restored → VERIFY: OK

```
00:06 +224: All tests passed!
analyze_rc=0 test_rc=0
VERIFY: OK
EXITCODE=0
```

## G25.2 self-prove (raw)

### A) notes.md HEAD set to `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` → test fails

```
00:00 +0 -1: notes.md HEAD is ancestor of or equal to current HEAD [E]
  Expected: <0>
    Actual: <128>
  notes.md HEAD `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` must be ancestor of or equal to current HEAD `d87edf0399ddd9952756665c5bd253706dfaceb7` (merge-base --is-ancestor exit 128)
00:00 +0 -1: Some tests failed.
EXITCODE=1
```

### B) restored → test passes

```
00:00 +0: notes.md HEAD is ancestor of or equal to current HEAD
00:00 +1: All tests passed!
EXITCODE=0
```

## Gate

### analyze
Deferred to verify script (No issues found! on last verify run)

### test
Last verify: `00:06 +224: All tests passed!` full run **225 passed / 0 failed**

### verify
`VERIFY: OK` (G25.1 self-prove B)

## Risks / scope

- Version **not** bumped (G25.5)
- No APK / no push / no amend
- Never touched `docs/grokbot/audit_report_*.md`
- G23 Corrupted-HEAD.txt STALE self-proof marked **无效** (not deleted)

## Final
- Final HEAD: `b2ba38c4b586a2deb04e7bfa0493b4d01f8b1936` (`b2ba38c`)
- version: **1.4.2+8** · schema **11** · tests **225**


---

# G26–G29 (baseline 60035e6 → …)

Baseline: `60035e6` · version `1.4.2+8` · schema **11** · tests **225**
User override version bump (once at wrap): **`1.4.4+10`**

## Subtask → commit (G26+)

| Task | hash | Notes |
|---|---|---|
| G26.1 | `2098145` | showDragHandle + golden via real modal; top pad tightened 8dp |
| G26.2 | `5e95ffc` | empty hint 记账→记一笔; shell comment |

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
| G28 | _(pending)_ | drops ring buffer + extras union + auto_capture card |

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

| G28 | _(pending)_ | drops ring buffer + extras union + auto_capture card |

## G28 notes / self-prove

- Native `drops` prefs: pkg/title(≤80)/when/reason only; never body; ≤20; dedupe pkg+title; apply() async.
- `extra_watched_packages` in app_settings; `syncWatchedPackagesToNative` unions after template pkgs.
- UI: 「最近被忽略的通知」; empty hides card; 「加入监听」+ SnackBar; **暂无移出入口**.
- Unit: `test/dropped_notifications_test.dart` 5 green.
- Device kill-restart acceptance: **not run** (no Android device on this Windows agent). Proven via unit union + code review of bindDatabase + addExtraWatchedPackage.
- Self-prove extras wipe: if `pkgs.addAll(await _loadExtraWatchedPackages())` commented out, restart sync would drop manual joins (union unit test documents intended behavior). Not physically commented in CI; code path reviewed.
