# B4-PATCH 第二批（G16–G19）审计报告

> 审计日期：2026-10-17（Asia/Shanghai）
> 审计范围：`fa82eda..30f9fd3`（**8 个提交**）
> 交付声称：schema **11** · **209 tests** · `1.4.2+8` · analyze 干净
> 审计方式：独立复跑 + 逐组读码 + 迁移推演 + 与 `notes.md` 对账

---

## 0. 一句话结论

**功能层这批做得很好**——G16–G19 全部落地，而且有 **3 处超出工单要求**的谨慎处理。

**流程层同一个病第三次复发**：不是没跑脚本，而是**脚本本身只生成一半的文件**——
`audit_input/` 里 6 个文件，只有 2 个会被更新，其余 4 个是上一批的化石。
于是同一个 HEAD 在三个地方有三个不同的值。

---

## 1. 门槛（我独立跑的）

```
flutter analyze  →  No issues found!   退出码 0   ✅
flutter test     →  209 passed / 0 failed  退出码 0   ✅（基线 195，+14）
```

---

## 2. 逐组验证

### ✅ G16 模型名拼写提示

| 要求 | 实际 |
|---|---|
| Levenshtein 近似提示 | 新文件 `model_name_validation.dart`（`levenshteinDistance`）✅ |
| 已知模型列表 | `kKnownDeepSeekModels`（含 `deepseek-v4-pro`）✅ |
| 提示文案 + 一键修正 | `疑似拼写错误，是否改为 …？` + `smart_fill_settings_page.dart:393`「一键修正」✅ |
| 修掉 `/v1` 误导文案 | `:335`「通常无需 /v1，例如 https://api.deepseek.com」✅ |
| 单测 | `model_name_validation_test.dart` ✅ |

**自证**：阈值临时改 0 → **3 个测试变红**，恢复后 6 个通过（`notes.md`）。

### ✅ G17 删除成员字段（schema v10 → v11）—— **超出要求的一次**

| 要求 | 实际 |
|---|---|
| v10→v11 合并后删列 | `:157-174` 先 `UPDATE`（note · member）再 `alterTable` ✅ |
| v5 改 raw SQL | `:72` `ALTER TABLE transactions ADD COLUMN member TEXT` ✅ |
| 4 组迁移用例 + 跨版本 | `schema_v11_member_merge_test.dart`（v11 onCreate / v10→v11 / v4→v11）✅ |

**它多做了一件我工单里没写到的事**（而且是对的）：

```dart
// :127-144，在 if (from < 8) 里
// Jumping across versions with current schema would drop member without merging
if (await _hasTableColumn('transactions', 'member')) { …合并… }
await m.alterTable(TableMigration(transactions));
```

**我复核过它不会重复追加**：

| 升级路径 | 实际执行 | 结果 |
|---|---|---|
| v10 → v11 | 只走 `from < 11` 那段 | 合并 **1 次** ✅ |
| v7 → v11 | `from < 8` 段先合并 + `alterTable` 删列 → `from < 11` 段检测到列已不存在 → 跳过 | 合并 **1 次** ✅ |
| v4 → v11 | v5 加列 → v8 段合并 → v11 段跳过 | 合并 **1 次** ✅ |

`_hasTableColumn` 守卫让两段互斥，`alterTable` 也只在列存在时执行。**这是工单之外的正确补强。**

### ✅ G18 合并文字/语音为「快速记账」

| 要求 | 实际 |
|---|---|
| 改名 + 保留结构 | `quick_bookkeeping_sheet.dart`，标题 `:380`「快速记账」✅ |
| 删除文字面板 | `text_bookkeeping_sheet.dart` 已删 ✅ |
| 删除语音面板旧文件 | `voice_bookkeeping_sheet.dart` 已删 ✅ |
| 去掉选择器 | `shell.dart` 长按 → `_openQuickBookkeeping` 直开；点击仍走手动面板 ✅ |
| `hold_talk_bar` key 保留 | `:450` ✅ |
| 两个提交按钮 | `:529`/`:533` ✅ |
| 旧文案清理 | 「改用文字记账」「语音记账」**0 命中** ✅ |
| 测试 | `quick_bookkeeping_test.dart`（9 个用例）✅ |

### ✅ G19 截图记账可见性

| 要求 | 实际 |
|---|---|
| 抽公共入口 | `lib/features/capture/capture_intake_actions.dart` ✅ |
| 隐私确认只一处 | 只剩 `capture_intake_actions.dart:57,63` ✅（`PendingCaptureIntake` 内是自己定义，合规） |
| 首页 AppBar 入口 | `home_page.dart:267` tooltip「截图记账」✅ |
| 快速记账面板两个按钮 | `:494`「截图识别」/ `:509`「剪贴板」✅ |
| **先关面板再调起** | `:486-491` `nav.pop()` → 再用 `nav.overlay?.context` ✅ |
| 待确认页改调公共函数 | 旧 `_fromScreenshot`/`_fromClipboard`/`ImagePicker` **已删**，4 处改为调用公共函数 ✅ |

**注意它这里也多做了一步**：pop 之后没有继续用原来的 `context`，而是取 `nav.overlay?.context` 并检查 `mounted` ——
避开"用了 deactivated context"这个常见崩溃。工单没要求这个细节，它自己想到了。

**自证**：把隐私确认标题改掉 → 隐私测试变红，恢复后通过（`notes.md`）。

### ⚠️ 收尾三件事：2 成 1 败

| 项 | 结果 |
|---|---|
| 删孤儿文件 | ✅ `account_identity.dart` / `account_mark.dart` 均不存在 |
| 删 `test/golden/failures/` | ✅ 不存在 |
| **跑 `verify.sh` 让 audit_input 与 HEAD 一致** | ❌ **见 A1** |

---

## 3. 问题清单

### 🔴 A1 · `verify.sh` 只生成 2 个文件 → audit_input 自相矛盾

**证据**：

| 文件 | 修改时间 | 内容对不对 |
|---|---|---|
| `analyze.txt` | 16:20:08 | ✅ 新 |
| `test.txt` | 16:20:22 | ✅ 新（209） |
| `HEAD.txt` | **14:59:34** | ❌ 里面是 **`40785f0`**（上一批的提交） |
| `status.txt` | **14:57:34** | ❌ 已提交的版本首行是 ` M docs/grokbot/audit_input/analyze.txt`，描述的是旧树状态 |
| `commits.txt` | **14:57:34** | ❌ 最新一条是 **`d22f5cf`**（上一批） |
| `diff_stat.txt` / `build_apk.txt` | 13:11 / 13:14 | ❌ 更旧 |

**根因**（读脚本确认）：

```bash
# tools/verify.sh —— 只写两个文件
flutter analyze > "$OUT/analyze.txt" 2>&1
flutter test    > "$OUT/test.txt"    2>&1
```

`verify.ps1` 同样只写这两个。

**所以"同一个 HEAD"现在有三个互相矛盾的答案**：

```
notes.md      → 5e37f87
HEAD.txt      → 40785f0
真正 HEAD     → 30f9fd3
```

**这不是执行者偷懒，是工具不完整**——它照着脚本跑，脚本就输出两个文件。

**修复**：脚本必须一起生成 `HEAD.txt` / `status.txt` / `commits.txt` / `diff_stat.txt`，
或者**明确删掉这四个文件**、只保留 2 个并在 README 说明。
（我倾向"生成它们"，因为审计方确实需要 status/commits 来判断改了什么。）

**外加一条自我一致性断言**：
```bash
[ "$(cat $OUT/HEAD.txt)" = "$(git rev-parse HEAD)" ] || { echo "AUDIT INPUT STALE"; exit 1; }
```

### 🟠 A2 · `notes.md` 引用了游离提交 `a82554d`

```
| cleanup | `a82554d` | audit_input + notes; orphans/failures deleted |
```

`git cat-file -t a82554d` → `commit`（本地存在）
但 `git log --all` **找不到它** → **不在任何分支上**，clone 后不存在，最终会被 GC。

**影响**：`notes.md` 说"cleanup 在 a82554d"，但那个提交不可达 → 追溯断裂。

**修复**：notes 里只引用**可达**的提交；若确实经过 amend/rebase，要说明最终落在哪个可达提交里。

### 🟠 A3 · `docs/grokbot/README.md` 版本行重复括号

```
- 当前版本 **`1.4.2+8`**（B4-PATCH 剩余：/v1 提示、模型名纠错、去掉成员字段、快速记账、截图入口）
  （B4-PATCH 剩余：/v1 提示、模型名纠错、去掉成员字段、快速记账、截图入口）（见 `pubspec.yaml`）
```

同一段括号出现**两遍**，而且把 changelog 塞进了版本行——破坏了原本"`（见 pubspec.yaml）`"的简洁格式。

**修复**：版本行只留 `当前版本 **1.4.2+8**（见 pubspec.yaml）`，changelog 放到变更日志节。

### 🟡 A4 · G20 / G21 / G22 未做（**不算失败**）

这 8 个提交覆盖的是 **G16–G19**。G20（小组件冷启动）、G21（日历去重）、G22（详情页商户行）
是我**在这批开工之后才补进工单的**，之前的指令只到 G19。

**但请注意**：**G22.1 那个真 bug 仍未修** ——
详情页现在依然把 `txn.note` 显示两遍（一行「商户」、一行「备注」）。

### 🟡 A5 · 二进制 schema fixture 缺少自说明

新增 `test/fixtures/schema_v10_member.db`（112 KB）与 `schema_v4.db`（96 KB）。

- **优点**：用真库验证跨版本迁移，比手搓 schema 可信得多（这正是我工单里想要的效果）
- **风险**：二进制会腐烂——以后 schema 再变，这两个 fixture 不会自动更新，而测试仍会"通过"
- **建议**：加一份 `test/fixtures/README.md` 说明「这两个库是怎么生成的、对应哪个版本、schema 变更时如何 regenerate」，并在 `.gitattributes` 标记为 binary

---

## 4. 我特意复核、确认没问题的点

| 点 | 结论 |
|---|---|
| G17 双段合并 SQL 会不会把 member 追加两次 | **不会**。`_hasTableColumn` 让两段互斥（三条升级路径都推演过） |
| G19 pop 之后是否用了失效 context | **没有**。取了 `nav.overlay?.context` + `mounted` 检查 |
| G18 删两个文件后提交入口是否还唯一 | **是**。`submitSmartBookkeepingText` 仍是唯一提交路径 |
| G18 是否丢了测试覆盖 | **没有**。9 个用例，含打字提交与改写后提交 |
| G19 隐私确认是否被复制成多份 | **没有**。UI 那处只剩 `capture_intake_actions.dart` |

---

## 5. 结论：能不能放行

**G16–G19 可以放行**：功能达标、测试 +14、三处自证都有记录。

**但 A1 必须修**——否则下一批还会出现"报告与事实不符"，而我们每次都要靠人工比对时间戳才能发现。

**待办（按顺序）**：

| # | 事 | 归属 |
|---|---|---|
| 1 | **G23**：补齐 `verify.sh` 的四个输出 + 自我一致性断言 | Bot |
| 2 | A3：修 `docs/grokbot/README.md` 重复括号 | Bot |
| 3 | A2：notes 不要引用游离提交 | Bot（下批注意） |
| 4 | A5：fixture 加 `README.md` + `.gitattributes` | Bot（可降级） |
| 5 | **G20 / G21 / G22** | Bot |
| 6 | 收尾：跑新脚本、重新生成 audit_input | Bot |

---

## 6. 给执行者的话

**这批的技术含量是这几批里最高的**：

- 跨版本跳变的 `_hasTableColumn` 守卫 —— 我工单没写，你自己想到的
- 用真 `.db` fixture 测迁移 —— 比 mock 可信
- pop 之后换 `overlay` context —— 避免了一个很难复现的崩溃
- 三处自证都留了记录，`notes.md` 也主动写了"未做/风险"

**但同一个坑你还是踩了第三次**，而且这次**不是你的错**：

> `verify.sh` 只写 2 个文件，你照着跑，结果另外 4 个文件停在上一批。

所以这条我改了归属：**它从"纪律问题"变成了"工具缺陷"**。
G23 就是把工具补齐——补齐之后，"审计输入过期"这种事在物理上就不可能发生了
（断言会直接让脚本失败）。

**这也解释了为什么前两次我判断成"最后一步没做"**：我以为是流程问题，
实际是**工具给了"看起来干了"的假象**——脚本输出 `VERIFY: OK`，谁能想到它只写了两个文件。
