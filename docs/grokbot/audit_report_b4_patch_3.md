# B4-PATCH 第三批（G20–G23）审计报告

> 审计日期：2026-10-17（Asia/Shanghai）
> 范围：`30f9fd3..1dd14b3`（**6 个提交**）
> 交付声称：`1.4.2+8` · schema **11** · **224 tests** · analyze 干净
> 结论：**G20–G23 全部按规格完成**，剩 1 处"声称 vs 实际"不符 + 1 处我方文档矛盾

---

## 0. 门槛（我独立跑的）

```
flutter analyze  →  No issues found!        退出码 0   ✅
flutter test     →  224 passed / 0 failed   退出码 0   ✅（209 → 224，+15）
```

---

## 1. G20 小组件冷启动 —— ✅ 完成

| 要求 | 实际 |
|---|---|
| 忽略平台默认路由 | `router.dart:45` `overridePlatformDefaultLocation: true` ✅ |
| `/` → `/splash` | `:51-52` ✅ |
| 友好错误页 | `:48` `errorBuilder → _UnknownRoutePage` ✅ |
| 不泄露异常 | 全仓 `GoException` **只在注释里**，页面文本为「页面不存在 / 这个地址打不开，回首页继续记账」+ 按钮 `context.go('/home')` ✅ |
| 冷启动深链暂存 + splash 消费 | `lib/app/deep_link.dart`：`resolveInitialDeepLink` / `take()`，复用 `routeForUri` ✅ |
| 单测 | `test/deep_link_test.dart`（含 `createRouter` 初始 path == `/splash` 断言）✅ |

**它主动声明未做的**：没改 `MainActivity` 的 EXTRA 路径（工单标为可选 E）——
notes 里写明了"Flutter override + PendingDeepLink 已覆盖冷启动 data URI"。**合规且诚实。**

---

## 2. G21 日历去重 + 当天小窗 + 趋势正负着色 —— ✅ 完成

| 要求 | 实际 |
|---|---|
| 日历 tab 只剩两块 | `calRecent` 现在只作为 `monthTxns: calRecent`（`:458`）传给小窗；**内联第三块列表已删** ✅ |
| 点某天弹小窗 | `:490 showModalBottomSheet`，`:587` 空态「这天没有记录」，`:600` 关闭后清空高亮 ✅ |
| 小窗「+」补记 | `:526` tooltip「补记」→ `showBookkeepingSheet(initialHappenAt: day)` ✅ |
| **保存后小窗自动回来** | `:534` `if (saved == true)` → 等 80ms → **显式重读 `_rangeTxProvider(...).future`** → 重开小窗 ✅ |
| 面板预填日期 | `bookkeeping_sheet.dart`：`initialHappenAt` 贯通 `:18/:30/:39/:43`，`:73` `seed`；`existing` 优先、否则「该日 + **当前时分**」✅ |
| 趋势图正负着色 | `:347` 正段 `incomeGreen`、`:382` 负段 `expenseRed`，用 `FlSpot.nullSpot` 断开 ✅ |
| 0 基准线 + 含 0 刻度 | `isZero = v.abs() < yInterval*0.01`（`:189`）线宽 1.6；`minY/maxY` 强制含 0（`:161-162`）✅ |
| **口径锁** | notes：`dailyNetMajor('CNY', 10000, 3000) == 70`，且**故意换成 `out-in` 测试会不同意** ✅ |

**超出要求的一处**：重开小窗前**显式重读一次流水**（而不是依赖 provider 刷新），
避开了"小窗重开时数据还没更新"的时序竞争。工单没要求这么细。

---

## 3. G22 全页面去重 —— ✅ 完成

| 要求 | 实际 |
|---|---|
| 详情页「商户」行（真 bug） | `ledger_detail_page.dart` 中「商户」/`\u5546\u6237` **0 命中** ✅ |
| 净资产一致性守卫 | `test/net_worth_consistency_test.dart` ✅（notes：两个 provider 在 fixture 上一致） |
| G22.3 建议项 | 「另有 N 个分类预算」**已删**；统计页「净额」第三档 **跳过**，理由：日历已承载净额趋势，不再扩统计 UX → **合规**（工单允许降级但要求写理由）✅ |

---

## 4. G23 验证脚本 —— ✅ 完成（含自证）

| 要求 | 实际 |
|---|---|
| 生成 4 个新文件 | `verify.sh:19-22` `HEAD.txt` / `status.txt` / `commits.txt` / `diff_stat.txt` ✅ |
| STALE 断言 | `:25-29` HEAD 不匹配 → 打印 `AUDIT INPUT STALE` + `exit 1` ✅ |
| analyze/test 新鲜度断言 | `:36-37` ✅ |
| **自证** | notes：把 `HEAD.txt` 改成 `deadbeef…` → 断言触发并 `exit 1` ✅ |
| README 括号重复 | 已修，`:160` 只剩「当前版本 **1.4.2+8**（见 pubspec.yaml）」✅ |
| 三处版本同步 | `README.md` / `README.en.md` / `docs/grokbot/README.md` 全为 `1.4.2+8` ✅ |

`HEAD.txt` 当前内容 == `git rev-parse HEAD`（`1dd14b3`）✅

---

## 5. 遗留问题

### 🟠 B1 · G23.3「取消跟踪」声称与实际不符（**第三次同类问题**）

notes 写着：

> `git rm --cached` all previously tracked `audit_input/*` (keep on disk)
> to match README「该目录不进版本库」

**实际**：`git ls-files` 仍列出 **7 个文件**被跟踪：

```
HEAD.txt  analyze.txt  commits.txt  diff_stat.txt  notes.md  status.txt  test.txt
```

其中 3 个（`HEAD.txt` / `commits.txt` / `notes.md`）还是**未提交的修改状态**。

**但这锅要分一半给我**：工单自身矛盾——

- **G9** 要求「重新生成审计输入并**提交**」
- **G23.3** 要求「与 README 一致 → **不进版本库**」

执行者选了"提交"，于是与 README 措辞冲突。**两条指令互斥，是我写错。**

### 🟡 B2 · `notes.md` 的 `Final HEAD` 落后一个提交

未提交版写 `Final HEAD: 810be38`，实际 `1dd14b3`。
属于"文件里写自己所在提交哈希"的固有问题（先写后提交必落后）。

### 🟡 B3 · G23.5 fixture 自说明被降级

`test/fixtures/README.md` 与 `.gitattributes` 都**不存在**；notes 明确写了
「fixtures README (G23.5): degraded / skipped」。

**合规**（工单标了可降级），但风险仍在：两个 `.db`（112 KB / 96 KB）没有任何说明，
**schema 再变时测试可能"假绿"**。

---

## 6. 结论

**G20–G23 全部做完，可以放行。** 224 测试、analyze 干净、三处自证都有记录。

**剩下的是 3 件小事**，已写成 G24（都很短）：

1. 解决"audit_input 到底进不进库"的矛盾（**我给出取舍方案**）
2. 提交那 3 个未提交文件
3. fixture 自说明（可再次降级，但要在报告里留一句）

---

## 7. 这四批的总体评价

| 批次 | 主要问题 | 趋势 |
|---|---|---|
| B4 | 报告与 HEAD 不符（193 测试写成 182 那类） | — |
| B4-PATCH 一 | 守卫做对，但**最后没跑脚本** | 改善 |
| B4-PATCH 二 | 脚本只写 2 个文件（**工具缺陷**） | 根因转移 |
| **B4-PATCH 三** | **G20–G23 全达标，含 3 处自证与 1 处主动降级说明** | **明显改善** |

**"声称 vs 实际"的偏差在持续缩小**：从"整份报告口径不对" → "脚本只写一半文件" →
现在只剩"跟踪策略的口径不一致（而且一半是我的工单矛盾）"。

**技术层面它已经稳定**：跨版本迁移守卫、真库 fixture、deactivated context、
时序竞争处理——这些都是**主动**做的，不是被要求才做。
