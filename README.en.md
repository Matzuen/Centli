# Centli

Local-first personal bookkeeping (**Chinese UI only**): **clear every bill**.

> Canonical docs are in Chinese: see [`README.md`](README.md) and [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md).

- Flutter · Drift (SQLite) · Riverpod · go_router
- Version: `2.0.3+41`
- Currency display: `CNY · 人民币`
- Bottom nav (5 tabs): 首页 / 统计 / 记账 / 资产 / 我的

## Features

- Home: summary + net-worth chart; calendar cells show daily in/out; the calendar tab's 「每日收支」 plots one point per day (that day's net income − expense; days without bills are 0) as a single line, green above zero and red below
- Manual transactions (expense / income / transfer); chip row + category picker; amount keypad with `+ − × ÷`
- Separate text quick-entry sheet (long-press the center tab); voice was removed
- Transaction tags (list / detail / search / import-export)
- Multi-ledger, accounts, category tree; icons from assets or 1–2 hanzi fallback
- Stats: range (month / year / custom), category donut + legend (name + amount; hold a slice to see the percentage), summary and per-account tables; category drill-down; monthly budgets
- Bill detail: **保存** (save) + delete in the app bar; amount, account, category, type, time, tags, note and the include-in-stats/budget switches are each **tap-to-edit** (picks persist immediately, amount waits for 保存); only the edited columns are written, provenance is preserved
- Android pending auto-capture from WeChat/Alipay **transaction** notifications (payment, debit, income, refund, repayment); **no ongoing notification**: after the UI is swiped away (or the process is killed) the listener is restored by system rebinding plus a 15-minute periodic job; capture-first design — false positives are filtered in 待确认
- Recognition rules v8: loose "must contain" (any transaction word), trimmed exclusions (chat / OTP / login / reminders / you-initiated transfers stay out); `assets/noti_templates.json` mirrors the builtins and is covered by tests
- Recognition rules: official read-only + user CRUD + try-parse (step-by-step reason) + import/export
- AI enhance: local rules + optional LLM (also powers screenshot balance recognition)
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
> **2.0.0** starts a new major line: the UI and icon set were overhauled, auto-capture
> now keeps itself alive without an ongoing notification, and aggregates moved into SQL.

### 2.0.3 (2026-10-21)

- Payment overlay for quick confirm (amount / direction / note / categories)
- Pending notification actions: Confirm (overlay), Detail (in-app), Ignore (no duplicate system actions)
- Quick Settings tile to toggle auto-capture; hard-rebind NLS after process swipe-away
- Built-in rules v11: 2 templates (WeChat/Alipay); title gate + body decides in/out; refund/repay as tags
- Amount regex aligned so dates like `10-17` are not parsed as ¥10
- App lock skips overlay / full-screen intent; new app icon
- Content-fingerprint dedupe for consecutive WeChat/Alipay payments

### 2.0.2 (2026-10-20)

UI
- **Glassmorphism**: cards are translucent with a 1px highlight border (no backdrop blur — it bought nothing over a smooth gradient and cost real GPU time); **dialogs and bottom sheets frost their own surface**, so the blur samples what is behind the panel and the page itself stays sharp
- every dialog now goes through `CentliGlassDialog` (45 `AlertDialog` call sites); the gradient background covers all sub-pages
- chart Y-axis labels use `k` / `m` compaction chosen per axis, so two neighbouring stops can no longer render the same text

Notification capture
- keep-alive without an ongoing notification: the foreground service is gone; system rebinding plus a 15-minute `JobScheduler` job (persisted across reboots) restore the listener, with one inexact alarm as a short-term retry. The auto-capture page gained a 后台复活任务 self-check and a re-schedule entry
- parsing is **AI first**: when AI is off, times out or fails it falls back to local rules; AI verdicts are written back as `app-direction-scene` capture rules and `app-排除` exclude rules, so the same scene is served locally next time without another call
- AI is split into three independent gates (text fill / AI notification parse / AI asset scan), all off by default
- distilled rules stay bounded: capture rules auto-merge the least-active siblings within an app and direction, and rules idle for 90 days can be purged from the rules page
- the notification 入账 action no longer writes a bill directly; it opens the app and its confirm sheet, and home gained a 待确认 badge
- fix: the native receiver queried the dropped `merchant` column, so 入账 failed silently

Other
- fix: bill-list amounts overflowed at large text scales (`Flexible(flex: 0)` received unbounded width)

### 2.0.1 (2026-10-19)

- Stats legend drops the percentage: one line of 「name + amount」 at 13pt/regular weight, laid out as a vertically centred column (scrolls when taller than the ring) so it lines up with the donut
- Asset analysis now matches the stats card: a fixed 120pt donut plus legend, the ring centre showing 合计 and the net worth, and **holding a slice** floats 「name amount (percent%)」 above the ring until you release
- The asset legend shows name + percent only; the amount moved to the float and the ring centre, so 「amount (percent)」 can no longer be squeezed
- The assets hint (找不到账户？可到「已归档」查看) moved from under the tab bar to between the analysis card and the account groups
- Fixed the asset legend overflowing at large text scales: the percent is width-capped and ellipsizes, so 200% text no longer paints the yellow/black stripes

### 2.0.0 (2026-10-19)

UI
- New multicolour icon set under `assets/icons/` (banks, brands, payments, food, electronics, home, life, office, misc); brand and bank marks keep their own colours, other icons use a soft grey pad with a theme-coloured glyph
- 12 groups of near-duplicate icons were merged (`fire_simple`→`fire`, `local_taxi`→`taxi`, `tag_simple`→`tag`, …); old keys alias to the new ones so existing categories keep their icons
- Home summary card gained a **monthly budget strip** (used / left / over); the net-worth card shows total assets left and liabilities right
- Home pending area split into a "ready to confirm" carousel plus a separate banner for parse failures
- Dialogs, menus and text fields share one radius/palette (inputs 14, menus 16)
- Stats legend and summary tables re-laid out — the name takes its own width, the three money columns split the rest, and narrow screens shrink the font instead of truncating; hold a donut slice to see its detail above the ring

Auto-capture
- **Keep-alive**: originally a foreground keeper (`CentliCaptureKeeper`); since 2.0.2 it is system rebinding plus a periodic job, with no ongoing notification
- Native side honours `matchOn=title` and falls back to the bundled templates when Flutter has not synced yet, so a cold start can still book
- Native writes straight into the pending table instead of waiting for the Flutter engine

Performance
- Home / stats / assets aggregates moved into **SQL** (grouped by type, category and day) instead of folding the whole table in memory
- Recurring runs dedupe with one `IN` query instead of N per-occurrence lookups; account and category reads are cached
- Notification regexes are **compiled once and cached**; the home-widget sync is debounced by 700 ms
- Overview mode no longer also subscribes to the calendar month, so one refresh does not scan twice

Fixes
- The bill-list amount column overflowed the row at large text scales (`flex: 0` gave it unbounded width); it now hugs its content, caps at 55% of the row and ellipsizes beyond that

### 1.10.5 (2026-10-18)

- Fixed uneven home card spacing: the empty pending section rendered as a zero-height widget but kept the gaps on both sides, making overview→chart 32pt while chart→bills was 16pt
- The pending block (gap included) is now rendered conditionally; all card gaps are a uniform 16pt, with tests for both the empty and non-empty cases

### 1.10.4 (2026-10-18)

- Moved the home net-worth card up 8pt (segment-control gap 8 → 4, list top inset 4 → 0)

### 1.10.3 (2026-10-18)

- Fixed 3 layout overflows on 320dp screens / large text: the home delta amount, bill-list amounts like ¥1,234,567.89, and the assets row's balance at 200% text scale
- Added a narrow-screen smoke test: 13 pages render at 320dp, plus 3 pages at 200% text scale

### 1.10.2 (2026-10-18)

- Moved the last/max/min summary onto the same row as the 「净资产变化」 title, freeing a row for the plot
- Removed the bill-list button from the chart card header; only the stats shortcut remains

### 1.10.1 (2026-10-18)

- Y-axis allows 6–7 stops: 7 preferred, falling back to 6 when 7 would stretch the axis beyond ~2.5x the data span
- Fixed float tails in labels and gave flat series a band so the line is not glued to the axis

### 1.10.0 (2026-10-18)

- The net-worth chart Y axis now always renders 7 evenly spaced stops (it used to cap at 5, and often showed only 4)
- Step is derived from a 7-way split of the data range (1/2/2.5/5 × 10ⁿ), anchored at zero so 0 lands on a grid line

### 1.9.8 (2026-10-18)

- Removed the overview card footer line (「近30天涨跌 · 本位币 CNY…」); the card now ends with the assets/liabilities columns

### 1.9.7 (2026-10-18)

- Pulled the net-worth chart caption closer to the title (4 → 2) and to the plot (8 → 4)

### 1.9.6 (2026-10-18)

- The pie button on the net-worth chart now switches to the Stats tab instead of pushing Stats on top of Home (bottom nav stays in sync)

### 1.9.5 (2026-10-18)

- Fixed the bill-list button on the net-worth chart jumping to a non-existent page (the search page is registered at `/home/search`, the button pushed `/search`)
- Added a router guard test that checks every `push/go` target against the paths declared in `router.dart`

### 1.9.4 (2026-10-18)

- Tightened the home overview rhythm: 16pt between overview card / net-worth chart / bill list, and the chart plot trimmed from 132 to 112 so the card no longer looks padded top and bottom

### 1.9.3 (2026-10-18)

- Smoother lines: any two points now draw a curve (few points used to fall back to straight segments), smoothness raised to 0.35 with over-shoot prevention
- Vertex dots removed — the curve carries the trend; hovering shows a single dot on the current day

### 1.9.2 (2026-10-18)

- Fixed the net-worth chart tooltip being clipped at the right edge (hovering the last day showed a half bubble); the tooltip now clamps inside the chart with a 6pt margin

### 1.9.1 (2026-10-18)

- Unified spacing: every soft card now uses a 16pt inner padding (was a mix of 12/14/16/18/20/24) and page roots share one inset (16 / 8 / 16 / 32-or-120)
- Vertical gaps collapsed onto four tokens — dense 4, item 8, section 12, sectionLoose 16 — replacing 172 scattered numbers

### 1.9.0 (2026-10-18)

- Home 「待确认」 is now a swipeable card carousel (next card peeks in); each card shows channel · time, colour-coded amount, note and guessed category, with 忽略 / 入账 actions
- Booking happens right on the home page: tapping 入账 opens a confirm sheet prefilled with the amount and suggested category, editable before submitting; the carousel advances automatically
- The pending page's 调整 button now reuses the same sheet

### 1.8.1 (2026-10-18)

- Editing an account now sets the **current amount** (prefilled with the live balance); saving records a 「余额校正」 that moves the balance to the typed value without touching the opening balance or the stats
- Renaming / retyping / changing the icon no longer touches the opening balance (and no longer asks for confirmation)

### 1.8.0 (2026-10-18)

- Notification rules v9 match the **title only**: any Alipay / WeChat title containing a pay / transaction / receive / refund / transfer / repayment word is parsed; the body is no longer filtered (it is only used to extract the amount and merchant)
- Reminder / OTP titles are still skipped (repayment reminders, 待还 / 应还 / 账单日, verification codes, login alerts, chat)
- Direction priority: receive → refund → repay → transfer → pay
- After upgrading, run 我的 → 自动记账 → 解析模板 → 检查模板更新 (bundled version 8 → 9)

### 1.7.2 (2026-10-18)

- Asset-analysis legend never truncates the amount: the name ellipsizes, the amount + percent stay whole (「¥-87.89（−11.5%）」 instead of 「-11.5...」)
- Group headers push the sum fully to the right
- Account rows drop the chevron so the amount sits at the row edge (tap still opens the account)
- Only liability types use the red in the analysis ring

### 1.7.1 (2026-10-18)

- Added breathing room between the stats ring and its legend (fixed 132pt ring column + 20pt gap); still fits 320dp phones

### 1.7.0 (2026-10-18)

- Asset analysis now groups by **account type** (bank / online / credit card / investment / loan / wallet) instead of individual accounts, with 0% types kept and empty types dropped
- One-line legend: name + amount + percent (e.g. 「钱包 −200.00（−24.6%）」); the denominator is the sum of absolute balances, so liability types show a negative percent in red
- 「净资产」 on the overview card is now a caption above the big number

### 1.6.2 (2026-10-18)

- Stats legend is now a single line per category: name + amount (percent), e.g. 「娱乐 ¥15.89（2%）」; ring/legend split re-balanced to 4:7 so amounts fit on narrow phones

### 1.6.1 (2026-10-18)

- Net-worth chart Y axis shows every stop again (the short-card rule that kept only the first and last label is gone), with edge labels aligned so they are not clipped

### 1.6.0 (2026-10-18)

- Stats rebuilt as four cards: range (month / year / custom with dotted date header), category donut + legend (expense / income / all), summary (counts / income / expense / balance), and per-account table marked 「不包含转账数据」 (transfers excluded)
- Removed the stats daily-trend line (duplicate of the home calendar chart) and the duplicate budget progress bar

### 1.5.1 (2026-10-18)

- Overview card re-laid out to the design: ledger name, large net worth with period change, then assets / liabilities columns each carrying month + lifetime income or expense
- Net-worth chart card gained two header actions (bill list, category share)
- Y axis now shows fixed even stops (4–5, derived from the 1/2/5 ladder and guaranteed to cover the data)
- Hovering highlights only the nearest day (dashed line + hollow dot)

### 1.5.0 (2026-10-18)

- **Voice bookkeeping removed** — long-pressing the center tab now opens a text quick-entry panel only; microphone and recording permissions dropped from both platforms
- **Bookkeeping memory** — the panel reuses your last account/category (per direction); a note such as 「午饭」 recalls the category you filed it under (exact or longest fragment, up to 300 entries)
- **Duplicate as new bill** — the detail page can pre-fill a new bill from the current one (account / category / tags / note; amount cleared)
- **Explicit save only** — the detail page writes nothing until 保存; leaving with unsaved edits asks first
- **Home summary card** — ledger name / net worth + period change / assets · liabilities / month income · month expense / total income · total expense
- **Search** — quick category / account / date chips; space-separated keywords are ANDed; hits are highlighted; active keywords and filters are shown as removable chips
- **Recycle bin** — rows show category, account and note; the detail sheet lists every field with restore / delete-forever
- **Errors** — network / database / permission failures are distinguished, with a retry button and the raw error behind 「详情」
- **Empty states** — stats, assets and search now explain what to do next instead of showing blank cards
- **Pending page** — the six app-bar actions collapse into a 更多 menu

### 1.4.5 (2026-10-18)

- Home calendar trend: two sign-split lines replaced by **one per-day in/out line** — each point is that day's net (13th −1, 14th −71, 16th +633; no bills = 0), colour switching at the zero axis
- Fix the touch tooltip showing two days at once (「15 0.00」 above 「16 +633」): no more synthetic zero-crossing points; the popup labels only the day nearest the pointer
- Bill detail: 「保存」 replaces the edit icon; every row (amount, account, category, type, time, tags, note, include switches) is tap-to-edit and saves on selection; amount commits on 保存
- Row edits update only the changed fields (source / dedupe key / FX kept); fix a controller-disposed-during-dialog-animation crash
- Bill detail: empty tags stay empty (no placeholder dash); account / category show names instead of IDs
- Notification rules v8: "must contain" relaxed to any transaction word; exclusions trimmed (sent-away receipts and red-packet/discount payments are captured now; 收益/权益 到账 still excluded); 「收到 XXX 的 66 元转账」 pattern added
- New regression tests: 14 capture cases + 9 exclusion cases, plus assets/builtin rule parity

### 1.4.4 (2026-10-18)

- Bookkeeping sheet: drag handle; backspace icon with normal (non-warning) colors
- Empty-home hint uses 「记一笔」; list shows 「不计入」 for excluded stats
- Pending tabs centered; screenshot 「查看」 opens `/home/pending?tab=pending`
- Auto-capture: 「最近被忽略的通知」 with join-watch (persists across restart)
- Wider payment keywords; pending notification actions: confirm / edit amount / ignore

### 1.4.2 (2026-10-17)
- Fix misleading smart-fill API base URL hint (DeepSeek usually needs no /v1)
- Near-miss DeepSeek model names get a one-tap typo fix hint
- Drop the member field (legacy values merged into note)
- Merge text + voice bookkeeping into Quick Bookkeeping (long-press bottom 「记一笔」)
- Screenshot bookkeeping entry on home (scanner icon) and inside the quick sheet
- Fix home-widget cold start 「Page Not Found」 by overriding platform default route and handing off after splash
- Unknown routes show a friendly page instead of raw GoException
- Calendar tab drops the duplicate txn list; tap a day for a sheet with that days ledger and quick bookkeeping
- Daily trend colors by sign (income green / expense red) with a zero baseline
- Drop mistaken merchant row on ledger detail (note shown once); net-worth consistency guard across home and assets

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
