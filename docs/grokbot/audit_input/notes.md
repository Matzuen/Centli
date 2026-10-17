# Centli B4-PATCH G20–G23 notes

Baseline HEAD (before this batch): `30f9fd3` · version `1.4.2+8` · schema **11** · tests **209**

## Subtask → commit

| Task | hash | Notes |
|---|---|---|
| G20 | `a14a465` | overridePlatformDefaultLocation + PendingDeepLink + `/` redirect + errorBuilder; E Android EXTRA skipped (A–D sufficient) |
| G21 | `de8040f` | calendar day sheet + bookkeeping initialHappenAt; trend colorBySign + zero baseline; dailyNetMajor tests |
| G22 | `8c12769` | drop ledger-detail 「商户」; net_worth_consistency_test; intentional-dupes table; deleted low-value stats budget hint |
| G23 | `7129c2d` | verify.sh/ps1 write HEAD/status/commits/diff_stat + STALE assert; untrack audit_input; fix duplicate version bullet |

## G20 self-prove

- `test/deep_link_test.dart`: centli://home → /home; pending → /home/pending; `/` → null; createRouter RIP path == `/splash`
- Did **not** change Android MainActivity EXTRA path (E optional); Flutter override + PendingDeepLink cover cold-start data URI

## G21 self-prove

- `dailyNetMajor('CNY', 10000, 3000) == 70`; swapped `out-in` disagrees (test locks polarity)
- `niceTrendYInterval` snaps to 1/2/5×10^n
- Calendar tab: only `_CalendarCard` + `_DailyTrendCard` (third SoftCard removed)

## G22 self-prove

- `ledger_detail_page.dart` 「商户」/ `\u5546\u6237` count = 0; note only under 「备注」
- `homeNetWorthProvider` and `assetsNetWorthProvider` agree on fixture (100000-20000-2500+800)
- G22.3: deleted 「另有 N 个分类预算」; **skipped** adding stats 「净额」 third tab (calendar already owns net trend; expanding stats UX not required)

## G23 self-prove

- Corrupted `HEAD.txt` to `deadbeef…` → assert prints `AUDIT INPUT STALE: HEAD.txt != git HEAD` and exits 1
- Full verify run regenerates all audit_input; HEAD.txt == `git rev-parse HEAD`
- `git rm --cached` all previously tracked `audit_input/*` (keep on disk) to match README「该目录不进版本库」
- Version: stay **`1.4.2+8`** (G23.7: no bump for tooling)

## Gate

### analyze
`
Analyzing Centli...
No issues found! (ran in 4.2s)
`
exit 0

### test (tail)
`
00:06 +224: All tests passed!
`
exit 0 -> **224 passed / 0 failed**, VERIFY: OK

### HEAD
HEAD.txt matches \git rev-parse HEAD\ after verify.



## Risks / scope

- Version **not** bumped (same batch as G16–G19)
- No APK / no push
- G22.3 net-tab on stats: skipped (documented)
- fixtures README (G23.5): degraded / skipped