# B1 批次执行审计报告

> 审计日期：2026-10-17（Asia/Shanghai）
> 审计方：只读审计（本次已可独立复跑验证）
> 被审计范围：`5114635..HEAD`（4 个 commit）
> 参考工单：`BOT_TASKS_B1.md`

---

## 0. 结论摘要

| 工单 | 内容 | 结论 |
|---|---|---|
| **B1-1** | 记完账数字立刻变 + 区分加载态 | ✅ **正确** |
| **B1-2** | 收支方向回归修复 | ✅ **正确，回归已消除** |
| **B1-3** | 净资产订阅账户 + 未折算提示 | ✅ **正确，已独立实证** |
| **B1-4** | 本位币小数位换算 | ✅ **正确，未误改百分比** |

**4/4 通过。** 首次出现「4 个工单各自独立 commit」——上一轮"未提交导致回归"的教训**已落实**。

### 独立验证结果（审计方亲自执行，非转述）

```
flutter analyze  →  No issues found! (3.4s)
flutter test     →  87 passed / 0 failed   （基线 84，+3）
git log -S "type: txnType"  →  命中 403e7c6  ✅
```

---

## 1. 提交与产出核对

### 1.1 commit 真实性（本轮重点检查项）

| 工单 | commit | 说明 |
|---|---|---|
| B1-1 | `5a72b30` | `fix(home/stats): 流水变更后合计立刻刷新并区分加载态` |
| B1-2 | `403e7c6` | `fix(pending): 确认入账按分类写入收支方向` |
| B1-3 | `f6fd1dd` | `fix(home): 净资产随流水更新并提示未折算` |
| B1-4 | `50fe624` | `fix(home): 图表金额按本位币小数位换算` |

**4 个 commit 全部实际存在**，命名规范，一单一次提交。工作区干净（仅剩一个未跟踪的审计报告文件）。

### 1.2 ⚠️ 审计输入未更新（唯一的过程性问题）

`docs/grokbot/audit_input/` 下的文件**时间戳为 10-16 22:23**，而 B1 的提交在 **10-17 01:14~01:18**。
我读了 `notes.md`，它讲的是**工单 10～14（R2/R3 批次）**与文字/语音独立面板，
**完全没有提及 B1-1 ~ B1-4**。

**影响**：审计方无法凭它核对本轮意图，只能直接审计 commit。
**不扣分**（本轮代码本身经得起审计），**但请下批更新**：
`diff.patch` 应相对**基线 `5114635`** 生成，`notes.md` 应覆盖本批工单与 4 个 hash。

---

## 2. 逐工单审查

### 2.1 B1-1 ✅

**改动**：`database_provider.dart`（+11）、`home_page.dart`（+84）、`stats_page.dart`（+32）、新增测试。

**机制审查**：新增 `txnWriteSignalProvider`：

```dart
final txnWriteSignalProvider = StreamProvider.family<int, String>((ref, ledgerId) {
  var version = 0;
  return ref.watch(databaseProvider)
      .watchRecentTransactions(ledgerId, limit: 1)
      .map((_) => version++);
});
```

**这是工单给出的「备选方案（版本号）」，实现正确**：

- doc 注释里**主动写明了工单警告的那一句**：
  「Use as an invalidation signal only — never aggregate from the watched list;
  always re-query untruncated summaries」
- `limit: 1` 只取一行，**没有把截断列表当数据源** → 规避了工单里标注的最大陷阱
- 全部 8 个 provider 都 `await ref.watch(txnWriteSignalProvider(ledgerId).future)`：
  首页 4 个（`:32, :61, :85, :103`）+ 统计页 4 个（`:27, :51, :76, :94`）

**统计页下拉刷新**（工单明确要求）已加：`RefreshIndicator` 在 `:159`，
`onRefresh` 依次 `invalidate` 4 个 provider（含预算的 `ym` 推导）。

**加载态/空态区分**（工单 ③）：`_NetChangeChartCard` 与 `_CalendarCard` 都新增了
`failed` → 「加载失败，下拉重试」、`loading` → `CircularProgressIndicator`，
在 `valueOrNull == null` 时才判定为加载中，**不再把"未加载"渲染成 ¥0.00**。

**测试质量**：`test/home_stats_refresh_test.dart` 是**真实异步测试**——
订阅 3 个 provider → 插入一笔流水 → **不调用 invalidate** → 轮询等待重新产出
→ 断言 `expenseMinor == 2500` 且 `totalMinor` 变化。这正是工单要求的形式。

**小问题（不阻塞）**：

1. **新增了测试用别名**（`homeRangeBaseProvider` 等 8 个 public 别名）以暴露私有 provider 给测试。
   这是为可测性做的妥协，可接受；但生产代码里出现仅测试用途的符号值得留意。
2. `_NetChangeChartCard` 里的 `SizedBox(height: 160)` 是硬编码高度（既有风格，非新增问题）。
3. 每个 provider 各自订阅一次 signal → 8 个订阅都在每次写入时触发。
   `limit: 1` 让它很便宜，**性能实测已证明可接受**（3000 笔冷启动 38ms），不作为问题。

### 2.2 B1-2 ✅（回归已消除）

**改动**：`pending_page.dart`（+9）、新增 `test/pending_confirm_type_test.dart`。

```dart
final inCats = widget.categories.where((x) => x.kind == 'in');
final outCats = widget.categories.where((x) => x.kind == 'out');
final known = outCats.any((x) => x.id == _categoryId) ||
    inCats.any((x) => x.id == _categoryId);
final txnType = !known
    ? 'out' // deleted/archived category → fallback expense
    : (inCats.any((x) => x.id == _categoryId) ? 'in' : 'out');
...
type: txnType,
```

**这比工单建议的实现更好**：工单建议"按 `categoryId` 在两个列表里反查"，
并提醒"若 `_PendingCard` 能读到父级列表就直接读、不要再查库"。
实现**正好用了 `widget.categories`（父级已加载）**，一次库查询都没多打。

边界处理正确：分类已删/归档 → 回落 `'out'` 且**不抛错**。

**回归自查（工单强制项）**：

```
$ git log --oneline -S "type: txnType"
403e7c6 fix(pending): 确认入账按分类写入收支方向
```

✅ **命中** —— 证明该修复**这次真的进了 commit**，回归不会再发生。

**测试质量**：`test/pending_confirm_type_test.dart` 两段——
② 是真实 DB 断言（收入分类 → `type == 'in'`，且覆盖 `'deleted-cat-id'` → `'out'` 兜底）；
① 是**源码文本检查**（`src.contains('type: txnType')`），属弱断言。
两者结合对"防回归"够用，但①单独看没有行为价值，**记录备查**。

### 2.3 B1-3 ✅（已独立实证）

**改动**：`home_page.dart`（+12）。

```dart
await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
// Opening balance lives on accounts — refresh when accounts change.
await ref.watch(_homeAccountsProvider(args.ledgerId).future);
```

**关键点核实**：`_homeAccountsProvider` 内部是 `watchActiveAccounts`（`home_page.dart:72`），
确实是 **`accounts` 表的漂移流** → 满足工单"至少要让首页净资产跟随 `accounts` 变化"的要求。

**审计方独立实证**（自写探针，非依赖 Bot 的测试）：
只改 `accounts` 表（`updateAccount(openingBalanceMinor: ...)`，**不写任何 transaction**）：

```
✅ 期初余额改动已触发重算：0 → 1234567
```

**这条路以前是坏的**，现在确认通了。

「未折算」提示已补（`:662-671`），使用 `nw.hasUnconverted` + `unconvertedByCcy`
—— 正是工单指出的"已有数据但全项目无 UI 引用"的那部分，**没有新造算法**。
且**尊重 `hide_amount`**（`formatMinor(..., hide: hide)`），隐藏金额时不会泄露。

**小问题**：

1. 提示文本用了硬编码 `fontSize: 12`，未走 `textTheme`（工单 8 已建立刻度）。小瑕疵。
2. 我在工单里要求的"首页与资产页净资产**数值一致**"**未验证**——
   两者都基于 `accountBalances`，理论上一致，但**建议后续补一个对比测试**。
   （本轮不作为阻塞项。）

### 2.4 B1-4 ✅

**改动**：`home_page.dart` 4 处 `/ 100.0` → `fromMinor(base, ...)`：

| 行 | 卡片 | 改法 |
|---|---|---|
| `:806` | `_NetChangeChartCard` | `fromMinor(base, netWorth...totalMinor ?? 0)` |
| `:817` | `_NetChangeChartCard` | `fromMinor(base, inV - outV)` |
| `:882` | `_CalendarCard` | `fromMinor(base, minor)` |
| `:1120` | `_DailyTrendCard` | `fromMinor(base, inV - outV)` |

**与统计页口径一致**（`stats_page.dart:762` 用的是 `fromMinor(baseCurrency, ...)`）。

**CNY 无回归**：`fromMinor(base, x)` 对 2 位小数币种 = `x / 100`，与旧值**逐位相同**。

**全仓复核（工单要求的排查）**：改后仅剩 1 处命中，正是工单标注**不能动**的那处：

```
assets_page.dart:483: final p = total <= 0 ? 0.0 : part * 100.0 / total;   ← 百分比，未被动 ✅
```

**未越界**：`money.dart` / `currencies.dart` / `centli_trend_chart.dart` 均未被改动。

> **JPY 未做真机目视**（Bot 在 notes 里也承认未做完整目视）。
> 但代码口径已正确，CNY 已证明无回归。

---

## 3. 越界与纪律检查

| 检查项 | 结果 |
|---|---|
| diff 是否只触及工单内文件 | ✅ 仅 4 个源文件 + 2 个新测试，**无无关重构** |
| 是否改动配色/主题 | ✅ 未改 |
| 是否放松 lint / 用 `// ignore:` | ✅ 无 |
| 是否为通过而改测试断言 | ✅ 无（新测试是新增，非修改） |
| 是否改动自动记账链路 | ✅ 未改（工单禁止） |
| 是否有工单外顺手改动 | ⚠️ 轻微，见下 |

### 轻微越界（可接受，记录备查）

1. **B1-1 混入了 B1-3 的种子**：`_netWorthHomeProvider` 的信号订阅
   （`await ref.watch(txnWriteSignalProvider(...))`）出现在 `5a72b30`（B1-1），
   而 B1-3 的 commit 只补了 `accounts` 订阅。
   严格说这违反了"一单一提交"，**但两者的差异可以清晰分辨**，不影响审计。
2. **新增 8 个 public 测试别名**（见 2.1 小问题 1）。
3. `stats_page.dart:178-184` 的 `padding:` 缩进未对齐 —— **不扣分**：
   经查全仓 100 个文件里 90 个都"未经 `dart format`"（含大量本轮未触碰的旧文件），
   说明**本项目本就不使用 `dart format`**，非本次引入。

---

## 4. 待办（下一批，非阻塞）

来自本轮审查，建议并入 B2：

| # | 项 | 原因 |
|---|---|---|
| 1 | **补一个"首页与资产页净资产一致"的对比测试** | 工单 B1-3 要求"数值一致"，本轮未验证 |
| 2 | 未折算提示走 `textTheme` 而非硬编码 `fontSize: 12` | 设计系统一致性（工单 8 的延续） |
| 3 | 移除或标注 8 个测试专用 public 别名 | 生产代码整洁性 |
| 4 | `pending_confirm_type_test.dart` 的源码文本断言可替换为纯行为断言 | 弱断言，行为价值低 |
| 5 | **审计输入需按批更新**（相对基线 `5114635`） | 本轮唯一的过程性问题 |

---

## 5. 给执行者的话

**本批做得很好。** 三点特别值得肯定：

1. **4 个工单各自独立 commit** —— 上一轮最严重的流程问题（修复未提交 → 被覆盖 → 静默回归）**已彻底解决**。
2. **B1-1 选了备选方案，并主动在 doc 注释里写明了工单警告的那句话**
   （"never aggregate from the watched list"）—— 说明**工单被真正读懂了**，不是机械执行。
3. **B1-2 的实现优于工单建议**（用父级已加载列表，省掉两次库查询）。

**下批请改进一点**：`docs/grokbot/audit_input/` 要**按批重新生成**，相对基线 `5114635`。
本轮它仍停留在 R2/R3 批次，导致审计方只能直接读 commit（虽然这轮代码经得起直接审计）。

**下一步**：出 B2 工单（退款可记录 · `include_in_budget` 加 UI · 预算「未折算」提示），
并把上面 §4 的 5 项并入。
