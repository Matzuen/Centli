# B4 审计报告 · 以「纯粹、单一、好用」为标准

> 审计日期：2026-10-17（Asia/Shanghai）
> 审计范围：`e0c3d5f..49e85c1`（**22 个提交**，B4）
> 基线：`a1869f1` · schema v7 · 150 tests
> 交付声称：schema v10 · **182 tests** · analyze 干净
> 审计方式：独立复跑 + 读码 + **变异测试**（故意破坏以验证锁是否有效）+ 真实文案探针

---

## 0. 一句话结论

**功能几乎全达标，我亲手做的验证全部通过；但完成门槛没达到——`flutter analyze` 在 HEAD 上是红的，而报告声称干净。**

| 维度 | 评价 |
|---|---|
| 功能正确性 | ⭐⭐⭐⭐⭐ 10 个任务组全部落地，我实测的每一项都通过 |
| 验证诚实度 | ⭐⭐⭐⭐☆ 主动标注"DeepSeek 未联网验证"，但 **analyze 记录与 HEAD 不符** |
| 完成门槛 | ⭐⭐☆☆☆ **`flutter analyze` 2 个问题**，工单要求是 `No issues found!` |
| 工程质量 | ⭐⭐⭐⭐☆ 测试从 150 → 182；减法做得干净 |
| 工作区卫生 | ⭐⭐⭐☆☆ `tools/` 留了约 **150 个**一次性脚本 |

---

## 1. 我独立验证通过的部分（逐项给了证据）

### 1.1 T0A 待确认页分栏 —— ✅ 达标

我读码 + 跑测试确认：

| 分栏 | 实际过滤条件 |
|---|---|
| 待确认 | `status='pending' AND parseOk=1` |
| 解析失败 | `status='pending' AND parseOk=0` |
| 已忽略 | `status='ignored'` |
| 已入账 | `status NOT IN ('pending','ignored')` |

- 徽标已改为 **status 优先**（`pendingCaptureBadgeLabel`，`:20-28`）
- 遗留 `tab=all` 正确映射到 `confirmed`（`:38`）
- `test/pending_tabs_test.dart` **真的断言了不变量**：
  - 四个集合两两不相交（`:95-98`）
  - **并集 == 全部行**（`:117-118`）
  - **未知状态归入已入账**（`weirdId`，`:98`）—— 这条正是我要求的"不丢数据"
  - 320dp 下无溢出 **且四个分段等宽**（`:213-237`）

### 1.2 T0B 还款通知 —— ✅ 达标（我用你的原话实测）

| 输入 | 结果 |
|---|---|
| `10月花呗账单还清啦，从银行卡还款12.54元，本月账单已还清` | **ok=true · dir=repay · amt=1254 · tpl=alipay_repay_zh** ✅ |
| `本月待还 1234.56 元，请于 10 月 8 日前还款` | **ok=false**（正确排除）✅ |
| `花呗还款成功 ¥88.80` | repay · 8880 ✅ |
| `向 星巴克 付款成功 ¥28.50` | out · 2850（回归未坏）✅ |

**三处同步齐全**（这是最容易偷懒的地方，它做全了）：
- Dart 内置模板 ✅
- `assets/noti_templates.json` `version: 7` + `alipay_repay_zh` ✅
- 原生 `MUST_ALIPAY` 加了 `还款|还清`，`EXCLUDE` 加了 `待还|应还|请于|即将到期` ✅

**「元」后缀兜底生效**：`还款12.54元` 无 ¥ 也提出 1254。

### 1.3 T1 删商户列 —— ✅ 达标，**最危险的一环守住了**

我特别担心"删了 merchant 列，自动分类规则悄悄失效"。结果：

- `transactions` 与 `pending_captures` **都没有 merchant 列**（`PRAGMA table_info` 有测试断言）
- `composeNote` 按约定 `商户 · 备注`
- **规则仍然能学**：`pending_page.dart:964` 传 `merchantForRule: parsedForRule.merchant`（内存里的解析结果）
- `test/schema_v8_merchant_note_test.dart` **真的断言了行为**：确认「星巴克」后，第二次抓到星巴克 → `suggestedCategoryId == cat.id` ✅
- `merchant_rules` 表保留 ✅
- 孤儿方法 `listMerchantSuggestions` **已删** ✅

### 1.4 T2 / T3 / T4 / T5 —— ✅ 达标

| 项 | 证据 |
|---|---|
| T2 订阅 | `lib/` 内 subscription 仅剩 `StreamSubscription` 无关命中；目录已删；v9 `deleteTable`；历史 v<7 的建表被 v<9 删掉，全新安装不会有 |
| T3 删 OCR | `mlkit/BillOcrService/bill_ocr` **全仓 0 命中** |
| T3 默认配置 | `kDefaultLlmBaseUrl='https://api.deepseek.com'`、`kDefaultLlmModel='deepseek-flash'` |
| **T3 请求体** | `system` 纯字符串；`user` 是数组含 `image_url`；**`detail: 'original'`**；`response_format: json_object` —— **与 DeepSeek 官方文档逐条一致** |
| T4 语音 | `Listener` 实现，文案「按住 说话」/「松开 结束」/「松开 取消」 |
| T5 资产分类 | `asset_types` 表 + `seedDefaultAssetTypes` + `asset_types_page.dart` 管理页 |

### 1.5 T6 golden —— ⚠️ 大幅改善，且**锁确实有效**（我做了变异测试）

改对了：
- 字体来自**仓库内** `test/golden/fonts/NotoSansSC.ttf`（不是 Windows 路径）✅
- 容器是 `Align(bottomCenter) + Material(圆角 24)` ✅

**我做的变异测试**（这是唯一能证明"锁没坏"的办法）：

| 变异 | 结果 |
|---|---|
| 键高 54 → 48 | **0.177% > 0.05% 阈值 → 测试失败** ✅ 锁有效 |
| 圆角 24 → 12 | 未变红 —— 但这是**我的探针选错了**：Material 底色与 Scaffold 背景同为白色，圆角视觉上不可见 |

**结论：golden 现在能抓真实布局漂移。** 对比 B3 那个"全是黑方块"的版本，这是实质进步。

---

## 2. 问题清单（按严重度）

### 🔴 P0：完成门槛没达到，且记录与 HEAD 不符

```
flutter analyze  →  2 issues found!   （退出码 1）
```

| # | 位置 | 问题 |
|---|---|---|
| 1 | `test/golden/bookkeeping_panel_golden_test.dart:11` | `unnecessary_import`（`dart:typed_data`） |
| 2 | 同文件 `:17` | `unused_element_parameter`（`maxDiffPercent` 从未被显式传入） |

**但 `analyze.txt` 写的 `No issues found!`，`notes.md` 第 5 行和第 75 行也各写了一次。**

**根因我能直接指出来**：它的最后一个代码提交 `5b7e604`（加 0.05% 容差）之后**没有重跑 analyze**，
就把更早的干净结果当成了最终结论。`analyze.txt` 时间 13:14，而 `5b7e604` 的内容就在 HEAD 里。

> **这不是能力问题，是纪律问题。** 工单 §6.3 明写"`flutter analyze` → `No issues found!`"是完成门槛。
> 一个红门槛 + 一份"干净"的报告，比一个红门槛更糟——因为下次我会信这份报告。

### 🟠 P1：golden 的图标全是方块（□），图标回归检测不到

我打开 golden 看了（1080×2400）：文字是真实中文字体，**但所有图标都是 □**。

原因：只加载了 `NotoSansSC`，**没加载 MaterialIcons**。
后果：**任何图标改动/丢失都不会让 golden 变红**——包括 B3 那套 324 个图标的目录若出问题也测不到。

工单 T6-1 只说"加载固定字体"，**没有明确要求图标字体**——这一条责任在我，属于契约不完整。

另外 golden 右上角带 **debug banner**（`MaterialApp` 默认 `debugShowCheckedModeBanner: true`），
一是污染基线，二是将来关掉它会无故引起 golden 变更。

### 🟠 P2：16.9 MB 字体入库

`test/golden/fonts/NotoSansSC.ttf` = **16.9 MB**，进了 git。
它自己披露了这点（notes 第 69 行），算诚实。但为一个 golden 测试把仓库撑大 17MB 并不划算——
中文字体应该做 **subset**（只保留面板用到的字符）或改用小体积字体。

### 🟡 P3：0.05% 容差的安全余量只有 3.5 倍

我实测"键高 54→48"产生 **0.177%** 差异，阈值 **0.05%**。
也就是说，**比这更小的改动（约 1–2dp 级）可能被容差吞掉**。

容差本身是合理做法（并行跑时抗锯齿会抖），但它**掩盖了一个更深的问题**：
golden 在并行下会抖，说明渲染不确定性没消除。正确解法是让 golden 串行跑
（`--concurrency=1` 或独立 tag 单独跑），而不是放宽阈值。

### 🟡 P4：遗留过期注释

`recurring_wizard_page.dart:14` 还写着：

```dart
/// Optional prefill from subscription link (T2-5).
```

订阅模块（T2-5）**已经整块删除**，这个注释指向一个不存在的功能。
删干净应该包括注释——否则下一个人（或下一批的 Bot）会去找那个"subscription link"。

### 🟡 P5：`tools/` 下约 150 个临时脚本

它用 Python 脚本批量改写 Dart 文件（`_patch_t0a1_page.py`、`_patch_t1_ui.py`…），
这些文件全留在 `tools/` 里。

- **好消息**：`.gitignore` 已覆盖（`git check-ignore` 确认），不会进提交
- **坏消息**：150 个文件堆在一个**被跟踪的目录**里；而且这正好解释了 P0——
  **脚本改文件之后没有重新验证**，是这类工作方式的典型后果

**建议**：收尾时清掉，并把"用脚本改代码后必须重跑 analyze + test"写进 `docs/grokbot/README.md`。

### 🟢 可接受项（降级按工单允许）

- **T1-5 孤儿方法扫描 SKIPPED** —— 工单降级顺序第 2 位允许放弃
- **目视未做** —— notes 第 70 行主动承认
- **DeepSeek 真实调用未联网验证** —— 主动标注了，这是对的做法

---

## 3. 以「纯粹、单一、好用」再评一次

这一批是**减法批**，方向完全正确：

| 变动 | 对"纯粹"的贡献 |
|---|---|
| 删订阅 | −1 张表、−2 个页面、−1 个入口，并消除了"同一笔花费两个数字"的双口径 |
| 删 OCR | −1 个原生依赖、APK 变小；识别统一到一个引擎 |
| 删 merchant 列 | −1 个字段、−1 套建议逻辑，商户并入备注 |
| 新增 asset_types | **+1**，但这是你明确要的能力，且替代了原来硬编码的 4 组 |
| 新增 repay 方向 | **+1**，但它是修 bug 的必要产物，不是新模块 |

**净变化是负的（更小了）**，这对"纯粹"是加分。

### 但有一个我必须提醒的后果

**删掉 OCR 之后，截图记账 100% 依赖 DeepSeek 联网，而这一批从未真实调用过。**

这意味着：
- 网络不通 → 截图记账不可用
- token 没配好 / 套餐不含 `deepseek-flash` → 截图记账不可用
- 代码正确 ≠ 能用

**所以在你验收时，"发一张账单截图看能不能出结果"是必须做的一步**，
而不是看测试全绿就放心。

---

## 4. 建议：这批要不要放行

**功能上可以放行**，10 个任务组我逐项验证过。

**但 P0 必须先修**——它只要 2 分钟：

```dart
// test/golden/bookkeeping_panel_golden_test.dart:11
- import 'dart:typed_data';        // 删掉（services.dart 已提供）
// :17  把 maxDiffPercent 从构造参数改成常量字段，或让调用处显式传入
```

修完重跑 `flutter analyze`，把真实输出贴进 `notes.md`。**不要**再让报告和 HEAD 不一致。

### 建议同批顺手处理（都很小）

| 项 | 成本 |
|---|---|
| golden 加载 MaterialIcons 字体 | 小（加一次 `FontLoader`） |
| golden 关掉 debug banner | 极小 |
| 删 `recurring_wizard_page.dart:14` 的过期注释 | 极小 |
| 清掉 `tools/` 下的一次性脚本 | 极小 |
| golden 改串行跑，把容差收回 0 | 小 |
| 字体子集化（16.9MB → 几百 KB） | 中 |

---

## 5. 我没验证的部分（不要当成已验证）

诚实声明，以下我只做了**读码**，没有真机或真实网络：

1. **DeepSeek 视觉真实调用** —— 未联网（它也没做）
2. **语音按住说话的真机手感** —— 手势阈值 60dp、0.5s 最短时长只在单测里验过
3. **资产分类管理页的实机交互** —— 读码确认存在，未点击
4. **Excel 往返** —— 有 `excel_asset_types_test`，但我没拿真实备份文件试

---

---

## 5.1 补充实证（2026-10-17 15:26 · 用户真机）

> **本节替换 §5 第 1 项的结论。原文写"未联网验证"，现已实证通过。**

| 项 | 结果 |
|---|---|
| 操作 | 把模型名 `deekseek-flash` 改成 `deepseek-flash`，在真机上识别一张账单截图 |
| 结果 | **识别成功，并生成了待确认条目** ✅ |
| 结论 | **T3（删 OCR → DeepSeek 视觉）端到端可用** |

**由此关闭的风险**：本报告 §5 第 1 项「DeepSeek 视觉真实调用 —— 未联网」。

### 复盘：那一个小时其实花在哪

```
B4 交付视觉代码（mock 测试全绿）
  → 真机报「HTTP 400」（无信息）        ← 代码把服务端原因丢了
  → 审计定位并要求透出原始错误（G11）
  → 真机再测，错误自己说出原因
  → 一分钟定位：模型名多了一个 e（deek-seek）
```

**三个可验证的教训**：

1. **能自解释的错误 > 漂亮的友好提示**。`HTTP 400` 浪费一小时；
   `HTTP 400 · Model Not Exist` 一分钟解决。
2. **"不覆盖用户已保存配置"会制造陈旧配置陷阱**（这是我当时的决策）。
   代码已改成"DeepSeek 域名 + 旧 gpt 模型名 → 自动迁移"，但它**没覆盖手填的错误名**——
   所以还需要 G16.2 的拼写近似提示。
3. **设置页文案本身也是 bug 来源**：`需包含 /v1` 是错的（DeepSeek 不需要 /v1），
   它会诱导用户去"修"一个本来正确的值 → G16.1。

### 仍未验证（截至本节）

- 语音「按住说话」真机手感
- 资产分类管理页实机交互
- Excel 自定义分类往返

---

## 6. 给执行者的话

**这一批的技术执行明显在进步**：
- T0A 的分栏不变量测试（并集 == 全部行）是**我没要求到那么细，它自己做对了**
- T1 最危险的"规则还能不能学"守住了，而且**有行为测试**
- T0B 三处同步一个没漏，`元` 后缀兜底和"待还排除"两条都做了

**但有一件事必须改**：

> **不要用"更早的干净结果"充当"当前状态的结论"。**

这次是 `analyze`。上次 B3 是"商户输入框被删了但在报告里才说"。同一个模式：
**状态变了，验证没跟上。**

具体到操作层面：你既然用脚本改文件，那**每个脚本跑完就该重跑一次 analyze**，
或者至少在最后一个代码提交后**必跑一次**并在 `notes.md` 里贴原始输出。
`analyze.txt` 应该由这条命令直接生成，而不是事后手写。

---

## 7. 附：任务达成表

| 任务 | 结果 | 我的验证方式 |
|---|---|---|
| T0A 待确认页 bug | ✅ | 读码 + 读测试断言 |
| T0B 还款通知 | ✅ | **真实文案探针实测** |
| T1 删 merchant 列 | ✅ | 读码 + 读测试 + 检查规则链路 |
| T2 删订阅 | ✅ | grep + 迁移代码 |
| T3 删 OCR / DeepSeek 视觉 | ✅（代码）/ ⚠️（未联网） | grep + 请求体逐字段核对官方文档 |
| T4 语音按住说话 | ✅（代码） | grep 交互文案与手势实现 |
| T5 资产自定义分类 | ✅ | 读表/迁移/管理页/T5-6 测试 |
| T6 golden 修复 | ⚠️ 部分 | **变异测试**（确认锁有效）+ 看图（图标 tofu） |
| T7 功能面冻结 | ✅ | `PRODUCT_SCOPE.md` 存在 |
| T8 收尾 | ⚠️ | 审计输入存在但 **analyze 记录过期** |
| 测试数 | 150 → **182** | 独立复跑 `All tests passed!` |
| analyze | ❌ **2 issues** | 独立复跑 |
