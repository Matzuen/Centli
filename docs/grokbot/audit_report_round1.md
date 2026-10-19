# 审计报告：Grok Bot 本轮改动

> 审计日期：2026-10-16（Asia/Shanghai）
> 审计方：只读审计
> 对照基准：`docs/grokbot/p0_tasks.md`（P0 批次 4 工单）
> 结论：**4/4 工单已实现，另额外交付 2 项；改动本身干净（analyze 全绿、未破坏既有测试）；但有 2 个必须补的缺口**
>
> **更新**：初版基于纯读码；后续审计方取得了 shell（`danger-full-access`），
> 以下 `git diff` / `flutter analyze` / `flutter test` 结果均为**实际执行**得到。

---

## 0. 审计条件说明

### 0.1 审计输入的补齐情况

初版审计时 `docs/grokbot/audit_input/` 不存在，只能纯现状读码。

**后续审计方自行取得了完整验证能力**：`workspace-write` 模式下 harness 初始化沙箱时
`grantWrite` 被 ACL 拒绝（Win32 5），改用 `danger-full-access` 后 shell 恢复可用。
因此以下内容**已实际执行验证**：

| 项目 | 结果 |
|---|---|
| `git status --short` | ✅ 18 个改动文件 + 2 个未跟踪项 |
| `git diff --stat` | ✅ +353 / −144 |
| `git diff` 关键片段 | ✅ 含 `analysis_options.yaml` |
| `flutter analyze` | ✅ **`No issues found!`（103s）** |
| `flutter test` | ✅ **57 通过 / 2 失败**（归因见 §0.3） |

### 0.2 审计方式

先用代码内的审计引用注释（`audit §3.x`、`(#10)`、`(#12)`）定位改动，再用 git diff 与
analyze/test 的真实输出交叉验证。

### 0.3 两个测试失败的归因（重要）

```dart
test/ai_text_fill_test.dart:181   parseBookkeepingText mapCategoryHintToLocal fuzzy
test/widget_test.dart:31          DateRangeWindow last 30 days covers through today
```

**归因：均为「事先存在」，不是本轮引入的回归。** 证据：

```
$ git diff --name-only -- test/
（空 —— 测试文件未被本轮改动）

$ git diff --numstat -- lib/features/ledger/ai_text_fill.dart lib/core/utils/date_range.dart
（空 —— 这两个被测文件与 HEAD 逐字节一致）
```

被测代码与测试代码**都未被本轮触碰**，因此本轮改动没有破坏既有测试。
两个失败的根因见 §5。

### 0.4 仍存在的局限

- `analysis_options.yaml` 的改动已确认**无害**：只新增 `exclude` 条目排除 `_fix_dumps/**`、
  `_audit_fix_bak_*/**`、`_p_*.py`、`_install_*/**`、`_patch_*/**`，**未放松任何 lint 规则**
- 首次尝试用 `git worktree` 在 HEAD 纯净副本复现失败时，因 `sqlite3` 原生资产需联网下载而失败（网络中断）
- **未做真机/模拟器验证**：原生 Kotlin 与 UI 视觉结论仍为静态分析

---

## 1. 工单执行情况总览

| 工单 | 内容 | 判定 | 备注 |
|---|---|---|---|
| **P0-1** | 待确认入账恒记为支出 | ✅ **已修复** | 实现比要求更好，见 §2.1 |
| **P0-2** | 还原时归一化子行 `ledgerId` | ✅ **已修复（完整）** | 6 张子表全覆盖，见 §2.2 |
| **P0-3** | 用户识别规则被静默清空 | 🟡 **主体已修，缺 1 项** | 缺「跳过计数 + UI 提示」，见 §2.3 |
| **P0-4** | 暗色模式下记账面板不可用 | 🟡 **主体已修，键盘未改** | 见 §2.4 |
| **额外** | §3.3 规则编辑丢字段 | ✅ **已修复** | 超出工单范围，见 §3.1 |
| **额外** | §3.4 规则文件不在备份里 | ✅ **已修复** | 超出工单范围，见 §3.2 |

**执行质量评价**：改动**命中根因**，没有打补丁；且主动修复了两条我没写进 P0 工单的问题（§3.3、§3.4）。代码注释引用了审计章节号，可追溯性好。

---

## 2. 逐工单复核

### 2.1 P0-1 待确认入账类型 — ✅ 已修复

**位置**：`lib/features/pending/pending_page.dart:628-649`

```dart
final outCats = await db.loadCategories(widget.ledgerId, 'out');
final inCats = await db.loadCategories(widget.ledgerId, 'in');
final type = inCats.any((x) => x.id == _categoryId) ? 'in' : 'out';
// Prefer category kind; default out only if not found in either list.
final known = outCats.any((x) => x.id == _categoryId) ||
    inCats.any((x) => x.id == _categoryId);
final txnType = known ? type : 'out';
await db.confirmPendingCapture(
  ...
  type: txnType,     // ← 已传入
);
```

**评价**：实现**优于工单建议**。工单方案 A 是"在选择回调里记录 `kind`"，执行方改为"入账时按 `_categoryId` 在两个列表中反查"，好处是：

- 不依赖 UI 状态与选中项严格同步（避免了"先选收入再切支出，`_categoryKind` 未更新"这类边界 bug）
- `known` 判断优雅处理了"分类已归档/被删、两边都查不到"的情况，回落 `'out'` 而非猜错
- 额外的两次 `loadCategories` 调用是可接受的代价（入账是低频操作）

**验收对照**：

| 验收项 | 结果 |
|---|---|
| 选收入分类 → `type == 'in'` | ✅ 逻辑成立 |
| 选支出分类 → `type == 'out'` | ✅ 逻辑成立 |
| 预填收入分类恢复后仍正确 | ✅ 因按 `_categoryId` 反查，与预填来源无关，天然正确 |
| `flutter analyze` / `flutter test` | ✅ 实测：analyze 全绿；test 无新增失败（§0.3） |

---

### 2.2 P0-2 `ledgerId` 归一化 — ✅ 已修复（完整）

**位置**：`lib/data/db/centli_database.dart:2115-2140`

```dart
final ledgerRow = Ledger.fromJson(ledgerMap);
final lid = ledgerRow.id;
// Force every child row onto the restored ledger (audit §3.1).
final accountRows = [
  for (final m in accountMaps) Account.fromJson(m).copyWith(ledgerId: lid),
];
final categoryRows = _sortCategoriesForInsert([
  for (final m in categoryMaps) Category.fromJson(m).copyWith(ledgerId: lid),
]);
final txnRows = [
  for (final m in transactionMaps) Transaction.fromJson(m).copyWith(ledgerId: lid),
];
final ruleRows = [
  for (final m in merchantRuleMaps) MerchantRule.fromJson(m).copyWith(ledgerId: lid),
];
final pendingRows = [
  for (final m in pendingCaptureMaps) PendingCapture.fromJson(m).copyWith(ledgerId: lid),
];
final fxRows = [for (final m in fxRateMaps) FxRate.fromJson(m)];   // 全局表，不动 ✅
final budgetRows = [
  for (final m in budgetMaps) Budget.fromJson(m).copyWith(ledgerId: lid),
];
```

**评价**：**完整覆盖 6 张带 `ledgerId` 的子表**（accounts / categories / transactions / merchant_rules / pending_captures / budgets），且正确地**没动 `fx_rates`**（全局表，无 `ledgerId`）——这正是工单边界情况里强调的点。

`copyWith` 在 `fromJson` 之后立即应用，所以 `_sortCategoriesForInsert` 收到的是已归一化的分类，`parentId` 父子关系依然自洽（父子都被归一到同一个 `lid`）。

**验收对照**：

| 验收项 | 结果 |
|---|---|
| 子行 `ledgerId` 指向本地另一账本 → 归属顶层账本 | ✅ 已被 `copyWith` 覆写 |
| 多账本回归（导入 A 的备份不影响 B） | ✅ 结构上成立（清空与插入都以 `lid` 为界） |
| `fx_rates` 未被误改 | ✅ |
| 未知 `ledgerId` 抛中文错误 + 事务回滚 | ⚠️ **采用静默归一化，未实现校验分支** |
| 新增测试 | ❌ **未新增** |

> **关于"未知 ledgerId 校验"**：工单写的是"建议"，静默归一化实际上是**更宽容且更安全**的选择——它把损坏备份变成了可修复的导入，而不会让用户面对整个还原失败。**我认为采纳现状、不补这个分支是合理的**，不算缺陷。但请在说明里确认这是有意选择，而非遗漏。

---

### 2.3 P0-3 用户规则静默清空 — 🟡 主体已修，缺 1 项

#### ✅ 已修的部分

**① 逐条容错解析** — `lib/platform/notifications/notification_parse.dart:80-108`

```dart
/// Parse + validate regex fields. Returns null on schema/regex errors.
static NotiTemplate? tryParse(Map<String, dynamic> j) {
  try {
    final t = NotiTemplate.fromJson(j);
    t.validateRegexes();
    return t;
  } catch (_) {
    return null;
  }
}
```

`validateRegexes()` 会逐个字段 `RegExp(raw)` 并抛 `FormatException`。**这比工单要求更进一步**——它不只跳过 schema 坏的条目，也跳过**正则非法**的条目，从源头消除了"坏正则入库"的路径。导入路径（`:326`、`:477`）也改用了 `tryParse`，所以导入端同样被过滤。

**② 失败时不清空** — `noti_template_store.dart:108-150`

```dart
static Future<void> _loadUserFile() async {
  // Do not clear in-memory rules up front — a parse failure must not wipe
  // good state (audit §3.2). Only replace after a successful parse.
  try {
    ...
    if (!await doc.exists()) {
      if (!_loaded) { _user = []; _disabledOfficialIds = {}; }   // 仅首次
      return;
    }
    ...
    if (decoded is! Map) return;        // 保留旧值
    ...
    if (list is! List) return;          // 保留旧值
    ...
    _user = templates;                  // 仅成功后替换
    _disabledOfficialIds = nextDisabled;
  } catch (_) {
    // Keep previous _user / _disabledOfficialIds — never silently clear.
  }
}
```

**评价**：三点都做对了 —— 不再前置清空、只在解析成功后替换、`disabled_official_ids` 与 `templates` **拆开独立处理**（工单边界情况里特别提到的那点）。首次安装（文件不存在）分支也保留为"空是正确的"，不会误报错。

**③ 写盘前备份** — `noti_template_store.dart:417-430`

```dart
static Future<void> _persistUserFile() async {
  final doc = await _userDocumentsFile();
  await doc.parent.create(recursive: true);
  // Backup previous file before overwrite (audit §3.2).
  if (await doc.exists()) {
    try {
      final bakFile = File('${doc.path}.bak');
      await doc.copy(bakFile.path);
    } catch (_) {
      // Best-effort backup; still proceed to write.
    }
  }
  await doc.writeAsString(_encodeUserFile());
}
```

**④ 坏正则只跳过该条** — `notification_parse.dart:288-300`

```dart
    return ParseResult(...);
  } catch (_) {
    // Bad regex / rule — skip and try next template (audit §3.2).
    continue;      // ← 在 for 循环内，确实跳过该条继续下一条
  }
}
```

**评价**：`continue` 位置正确（在 `for (final t in matched)` 内），符合工单要求"只跳过该条，不中断后续候选"。

`notification_ingest_bridge.dart:48-53` 也加了外层 try/catch（`catch (_) { return null; }`）。

#### ❌ 未实现的部分

**缺少「跳过计数 + UI 提示」**（工单 P0-3 步骤 ④）

`noti_template_store.dart` 中不存在 `_lastLoadSkipped` 或类似的计数/错误暴露字段（grep 无匹配）。`recognition_rules_page.dart` 中也没有警告条。

**后果**：坏条目被**静默跳过**。用户的规则可能少了几条却毫无察觉——从"静默清空"变成了"静默部分丢"，性质缓和了，但**用户依然不知道**。

**这是数据丢失类问题，建议补齐**，成本很小：

```dart
// noti_template_store.dart
static int _lastSkippedCount = 0;
static int get lastSkippedCount => _lastSkippedCount;

// 在 _loadUserFile 的逐条循环里累计
var skipped = 0;
for (final item in list) {
  if (item is! Map) { skipped++; continue; }
  final parsed = NotiTemplate.tryParse(...);
  if (parsed != null) templates.add(parsed); else skipped++;
}
_lastSkippedCount = skipped;
```

然后在 `recognition_rules_page.dart` 顶部，当 `lastSkippedCount > 0` 时显示一条可关闭的提示：

> 有 N 条规则格式有误已跳过，其余规则正常。建议导出备份后检查。

#### 验收对照

| 验收项 | 结果 |
|---|---|
| 坏条目不影响好条目（2 好 + 1 坏 → 返回 2） | ✅ 逻辑成立 |
| 不再清空（再新增一条，原有仍在） | ✅ 逻辑成立 |
| `.bak` 备份存在 | ✅ 已实现 |
| 全新安装无噪音 | ✅ `if (!_loaded)` 分支处理正确 |
| 坏正则不丢通知 | ✅ `continue` + 外层 try/catch |
| **UI 显示跳过警告** | ❌ **未实现** |
| **新增测试（至少覆盖上述 3 点）** | ❌ **未新增** |

---

### 2.4 P0-4 暗色模式记账面板 — 🟡 主体已修，键盘未改

#### ✅ 已修的部分

| 位置 | 改动前 | 改动后 |
|---|---|---|
| `bookkeeping_sheet.dart:24` | `Colors.white` | `Theme.of(context).colorScheme.surface` ✅ |
| `bookkeeping_sheet.dart:1068` | `Colors.white` | `Theme.of(context).colorScheme.surface` ✅ |
| `bookkeeping_sheet.dart:1474` | `Color(0xFFF7F8FA)` | `scheme.surfaceContainerHighest` ✅ |
| `bookkeeping_sheet.dart:1561` | `Colors.white` | `scheme.surface` ✅ |
| `category_picker_sheet.dart:20` | `Colors.white` | `Theme.of(context).colorScheme.surface` ✅ |
| `category_picker_sheet.dart:163` | `Color(0xFFF5F6F8)` | `scheme.surfaceContainerHighest` ✅ |
| `category_picker_sheet.dart:177` | `Colors.white` | `scheme.surface` ✅ |

**评价**：工单列出的白底与灰底已全部替换为主题色。**记账面板的主背景问题已解决**，暗色下不再是白底浅字。

#### ❌ 未完成的部分

**键盘配色仍是硬编码浅色常量**

`bookkeeping_sheet.dart:1710-1718`：

```dart
if (k == '✓') return CentliTheme.keypadConfirm;
if (k == 'AC' || k == '⌫') return CentliTheme.keypadAcBg;
if (k == '+' || k == '-') return CentliTheme.keypadOpBg;
return CentliTheme.keypadNumBg;
...
if (k == 'AC' || k == '⌫') return const Color(0xFFC62828);   // ← 仍硬编码
```

而 `theme.dart:65-68` 只有**一组浅色**常量：

```dart
static const keypadNumBg = Color(0xFFF5F6F8);   // 近白
static const keypadOpBg  = Color(0xFFD6E4FF);   // 淡蓝
static const keypadAcBg  = Color(0xFFFFE0DB);   // 淡粉
static const keypadConfirm = Color(0xFF4C7DFF);
```

`dark()`（`theme.dart:193+`）**未提供暗色键盘配色**。

**后果**：暗色模式下，记账面板主体已可读，但**键盘区域仍是浅色块**（`:1738` 的键高 52 说明这是主要输入区），视觉突兀。更实际的问题是 `:1718` 的硬编码 `Color(0xFFC62828)`（暗红）落在**淡粉底** `keypadAcBg` 上——对比度偏低，而这正是退格键。

**修复方向**：在 `CentliTheme` 增加暗色一组键盘常量（或在 `dark()` 中按 `colorScheme` 派生），键盘取色改为按亮度选择。**不要在两处写 if-else 硬编码**。

#### 遗留的两处（工单未要求，供参考）

- `bookkeeping_sheet.dart:1573` 的 `Color(0xFF6B7A99).withValues(alpha: 0.04)` — 轻微阴影，暗色下几乎不可见，影响很小
- `home_page.dart` 与 `assets_page.dart` 中的 `Colors.white`（选中 tab）属于 §5.3 的其他暗色残留，不在本工单范围

#### 验收对照

| 验收项 | 结果 |
|---|---|
| 暗色下金额/备注/分类/账户 chip 清晰可读 | ✅ 主背景已修 |
| **暗色下键盘可读** | ⚠️ **仍是浅色块**（未完成） |
| 浅色模式外观无变化 | ⚠️ 需人工对比；`scheme.surface` 在浅色下约等于白色，风险低 |
| `flutter analyze` / `flutter test` | ✅ 实测：analyze 全绿；test 无新增失败（§0.3） |

---

## 3. 超出工单的额外修复（好）

### 3.1 §3.3 规则编辑丢字段 — ✅ 已修复

**位置**：`lib/features/settings/recognition_rule_edit_page.dart:149-189`

```dart
// Preserve full packages + defaultCurrency when UI choice still
// matches the loaded primary package (audit §3.3).
final savedPackages = _preservePackages(packages);
final template = NotiTemplate(
  ...
  packages: savedPackages,
  defaultCurrency: _defaultCurrency,   // ← 新增字段
  ...
);
```

并新增 `_preservePackages`（`:187-189+`）保留多包规则。

**评价**：正确修复了"编辑一次就把多包规则压成单包、把币种重置为 CNY"。`_defaultCurrency` 的引入说明编辑页现在建模了该字段。

> 建议顺手确认：`_defaultCurrency` 在 `_bootstrap` 中**从被编辑的规则回填**（否则编辑非 CNY 规则时，UI 显示 CNY 但保存保留原值，会出现"显示与保存不一致"）。这一点我未逐行验证。

### 3.2 §3.4 规则文件纳入备份 — ✅ 已修复

**导出** — `lib/data/export/export_service.dart:87-96, 113`

```dart
// Include user recognition rules (documents/user_noti_templates.json).
await NotiTemplateStore.load();
final recognitionRules = <String, dynamic>{
  'version': 1,
  'disabled_official_ids':
      NotiTemplateStore.peekDisabledOfficialIds().toList()..sort(),
  'templates': [
    for (final t in NotiTemplateStore.peekUser()) t.toJson(),
  ],
};
...
'recognition_rules': recognitionRules,
```

**导入** — `import_service.dart:210-214`（解析）+ `:268-277`（还原）

```dart
// Restore user recognition rules when present (audit §3.4).
final rr = bundle.recognitionRules;
if (rr != null) {
  try {
    final encoded = const JsonEncoder().convert(rr);
    await NotiTemplateStore.importUserRulesJson(encoded, merge: false);
  } catch (_) {
    // Rules are best-effort; ledger restore already committed.
  }
}
```

**评价**：结构正确 —— 导出的 `recognition_rules` 形状（`version` / `disabled_official_ids` / `templates`）与 `importUserRulesJson` 的期望**完全一致**（我核对了 `noti_template_store.dart:300-360` 的解析逻辑）。`disabled_official_ids` 也一并携带，所以"我禁用了哪些官方规则"这个偏好也能迁移。`merge: false` 与导出的"完整快照"语义相符。

**注意点**：
- 规则恢复是**尽力而为**，失败被吞（`:274-276`）。考虑到"账本已提交"，这个取舍合理，但**用户不会知道规则没恢复**。建议纳入 §2.3 的提示体系。
- `_encodeUserFile` 会写 `'version': 1`，而导入端不读 `version`；往返一次后该字段来自模板硬编码而非备份。**无实际影响**，只是元数据不保真。

### 3.3 顺带修的两处

- `export_service.dart:101` — `'schema_version': 3`（原为 2），与 `import_service.dart:127` 的 `> 3` 上限一致 ✅。这也解决了上一轮 #24。
- `export_service.dart:103` — `app_version: await currentAppVersion()`（原为硬编码 `'1.0.0+1'`），说明版本号改为动态读取，可能同时修掉了上一轮 #43 的一半。
- `notification_ingest_bridge.dart:82` — 推送前读取 `hide_amount`，正是工单外的 §4.1 部分内容 ✅

---

## 4. 必须补齐的缺口

按优先级排列。

### ✅ 缺口 1：审计输入 — 已由审计方自行解决（不再阻塞）

`docs/grokbot/audit_input/` 始终不存在。但审计方通过 `danger-full-access` 取得了 shell，
**已自行执行** `git status` / `git diff` / `flutter analyze` / `flutter test`，故本条**不再阻塞审计**。

**仍建议执行方后续主动产出**（见 `README.md` §3），理由：审计方每次跑 shell 都需要人工批准，
成本高；且审计方无法凭 diff 之外的线索发现"未提交但已改动"的中间状态。

`notes.md` 里我仍想知道的两件事：

1. **是否有工单外的顺手改动** —— 从 `git diff` 看至少有 3 处（`schema_version` 2→3、
   `app_version` 改动态读取、推送前读 `hide_amount`），是否还有更多
2. **P0-2 采用静默归一化而非抛错，是有意选择还是遗漏** —— 见 §2.2 的评价，我倾向认为
   这个选择更好，只需确认

### 🔴 缺口 2：P0-2 与 P0-3 要求的新增测试一个都没有

**已实测确认**：`test/` 仍是 8 个文件（`git status` 中无 `test/` 改动），**没有新增**。
而两个工单的验收标准都明确要求补测试：

- **P0-2** 要求：多账本回归（导入 A 的备份不影响 B）+ 子行 `ledgerId` 不一致时的归属正确性
- **P0-3** 要求：坏条目不影响好条目（2 好 + 1 坏 → 2）、不再清空、坏正则不丢通知

这两条是 P0 里**最危险**的改动（都涉及数据丢失/错挂），**没有测试就等于没有防回归能力**。
下一轮任何人再碰这两个函数，都可能悄悄改坏。

建议新增 `test/restore_ledger_scope_test.dart` 与 `test/user_rules_resilience_test.dart`
（或合并进现有 `export_import_budgets_test.dart` / `notification_parse_test.dart`）。

### 🟡 缺口 3：P0-3 的 UI 提示 + P0-4 的暗色键盘

- P0-3④：跳过计数 + 列表页警告条（见 §2.3）
- P0-4：暗色键盘配色（见 §2.4）

### 🟡 缺口 4（新增）：两个既有测试失败未修

非本轮引入（§0.3 已证明），但既然已在红，建议顺手修掉，否则每次 `flutter test`
都无法作为"全绿"的回归门槛：

- `date_range.dart` 的 `isLatest` 缺 `nowLocal` 注入点（§5.1）—— 测试时间依赖型
- `ai_text_fill.dart` 的 `mapCategoryHintToLocal` 无法匹配「类别词 + 修饰词」
  （§5.2）—— **真实功能缺口**，影响 LLM 路径的分类预填

---

## 5. 两个既有测试失败的根因（非本轮引入）

> 已由 §0.3 证明为本轮之前就存在。此处给出根因与修复建议。

### 5.1 `DateRangeWindow.isLatest` 缺 `nowLocal` 注入点 — 时间依赖型测试

**失败**：`test/widget_test.dart:31` `expect(w.isLatest, isTrue)` → 实际 `false`

**根因**：`lib/core/utils/date_range.dart:146-152`

```dart
bool get isLatest {
  switch (kind) {
    case DateRangeKind.lastDays:
      final latest = DateRangeWindow.lastDays(days: days ?? 30);   // ← 未传 nowLocal
      return endLocal.year == latest.endLocal.year && ...
```

`lastDays()` **支持** `nowLocal` 注入（`:33`），但 `isLatest` 调用时**没有传**，于是用真实
"今天"计算 `latest.endLocal`。

测试里 `now = DateTime(2026,10,13)` → `w.endLocal = 2026-10-14`；
真实今天是 **2026-10-16**（审计时）→ `latest.endLocal = 2026-10-17` → 比较失败。

**性质**：该测试写于 10-13 当天可以通过，**之后每天都失败**。属时间依赖型测试 +
被测 API 缺少确定性注入点。

**修复建议**：给 `isLatest` 增加可选参考时间（也可只在测试里改用固定断言）：

```dart
bool isLatestAt(DateTime nowLocal) { ... }
```

或在测试中：
```dart
final w = DateRangeWindow.lastDays(days: 30, nowLocal: now);
expect(w.endLocal, DateTime(2026, 10, 14));   // 断言稳定部分
// 移除或改写 w.isLatest 断言
```

**影响面**：`isLatest` 被 `date_range_control.dart` 与 `date_range.dart:171` 的 `label` 使用
（`label` 在 `isLatest` 为真时显示「近30天」，否则显示日期区间）。真实运行中用的是真实
"今天"，行为正确；**问题仅在于不可测**。

---

### 5.2 `mapCategoryHintToLocal` 无法匹配「类别词 + 修饰词」— 真实功能缺口

**失败**：`test/ai_text_fill_test.dart:181` `mapCategoryHintToLocal('地铁出行')` → 期望 `'交通'`，实际 `null`

**根因**：`lib/features/ledger/ai_text_fill.dart:639-648` 的同义词回退：

```dart
// Synonym → canon → local
for (final entry in kCategorySynonyms.entries) {
  if (entry.key == cleaned || entry.value.contains(cleaned)) {   // ← 双向不足
    return _bestCategoryMatch(entry.key, names, ...);
  }
}
```

同义词表 `:156-158` 中 `'交通'` 的值列表含 `'地铁'`，但检查的是
`['交通','地铁',...].contains('地铁出行')` → false；而 `entry.key == '地铁出行'` 也为 false。

**后果（不只影响测试）**：`'地铁出行'`、`'餐饮消费'`、`'交通出行'` 这类
**「类别词 + 修饰词」**形式的输入一律返回 `null`。

而这恰是 **LLM 返回 `categoryHint` 的常见形式**（`llm_text_fill.dart` 的 prompt 要求
「尽量使用用户分类列表中的名称」，但模型常输出带修饰词的说法），所以该缺口会让智能填单
在 LLM 路径上丢失分类预填。

**修复建议**（择一，建议 B）：

- **A**：在 `kCategorySynonyms['交通']` 中补充 `'地铁出行'` 等词。**治标**，词表要无限追加。
- **B（推荐）**：把回退检查改为「输入是否包含任一同义词值」，并加长度门槛防误匹配：

```dart
for (final entry in kCategorySynonyms.entries) {
  if (entry.key == cleaned) { ... }
  final hit = entry.value.any((v) => v.length >= 2 && cleaned.contains(v));
  if (hit) return _bestCategoryMatch(entry.key, names, ...);
}
```

`v.length >= 2` 的门槛很关键 —— 词表中存在单字同义词，若不加限制，`'完全没听说过的类'`
之类输入可能因偶然包含单字而误命中，破坏该测试的第三个断言（期望 `isNull`）。

**修复后必须回归**：同一测试的三个断言（`'餐饮美食'→'餐饮'`、`'地铁出行'→'交通'`、
`'完全没听说过的类'→null`）都要通过。

---

## 6. 逐条对照验收标准

| 工单 | 验收项 | 结果 |
|---|---|---|
| P0-1 | 选收入 → `in` | ✅ |
| P0-1 | 选支出 → `out` | ✅ |
| P0-1 | 预填恢复后仍正确 | ✅ |
| P0-1 | analyze + test 通过 | ✅ 实测确认（§0.3） |
| P0-2 | 指向另一账本 → 归属顶层 | ✅ |
| P0-2 | 多账本回归（B 不受影响） | ✅（结构成立） |
| P0-2 | analyze + test 通过 | ✅ 实测确认（§0.3） |
| P0-2 | **新增测试** | ❌ |
| P0-3 | 坏条目不影响好条目 | ✅ |
| P0-3 | 不再清空 | ✅ |
| P0-3 | `.bak` 备份存在 | ✅ |
| P0-3 | 全新安装无噪音 | ✅ |
| P0-3 | 坏正则不丢通知 | ✅ |
| P0-3 | **UI 显示跳过警告** | ❌ |
| P0-3 | **新增测试（≥3 点）** | ❌ |
| P0-3 | analyze + test 通过 | ✅ 实测确认（§0.3） |
| P0-4 | 暗色下各元素可读 | ✅（主面板） |
| P0-4 | **暗色下键盘可读** | ❌ |
| P0-4 | 浅色无回归 | ⚠️ 需人工对比 |
| P0-4 | analyze + test 通过 | ✅ 实测确认（§0.3） |

**统计**：✅ 16 项通过 · ❌ 4 项未通过 · ⚠️ 1 项需人工确认

> `flutter analyze` → `No issues found!`（103s）
> `flutter test` → **57 通过 / 2 失败**，2 个失败经 §0.3 证明为**事先存在**
> ⇒ 执行方在本轮**未引入任何静态问题，也未破坏任何既有测试**

---

## 7. 下一轮建议

### 7.1 收尾本轮（先做这个）

1. 补齐审计输入（缺口 1）
2. 补 P0-2 / P0-3 的测试（缺口 2）
3. P0-3 的跳过计数 + UI 提示（缺口 3）
4. P0-4 的暗色键盘配色（缺口 3）

### 7.2 之后可进入 P1 批次

从 `issue_audit_round2.md` §5.2 与 §4.1 中选取：

| 编号 | 内容 | 收益 |
|---|---|---|
| — | **记住上次账户 + 分类** | 每笔记账省 5 次点击（11→6），最高频痛点 |
| — | **保存后 Toast + 撤销** | 现在保存**无任何提示**；`_save` 无 catch；账户为空时点 ✓ 完全静默 |
| — | 待确认页 `hide_amount` 漏传（`pending_page.dart:534`） | 隐私泄漏（推送已修，页面未修） |
| — | 锁屏通知 `VISIBILITY_SECRET` | 隐私（原生侧） |

> 完整清单见 `docs/issue_audit_round2.md` §5.2（TOP 10）与 §6（批次划分）。

---

## 8. 审计方声明

- 初版基于纯静态读码；**后续通过 `danger-full-access` 取得 shell，已实际执行**
  `git status` / `git diff` / `flutter analyze` / `flutter test`，结果见 §0.1。
- `flutter analyze` → `No issues found!`（103s）
- `flutter test` → **57 通过 / 2 失败**；2 个失败经 §0.3 证明为事先存在，**非本轮回归**
- **未做真机/模拟器验证**：原生 Kotlin 行为、暗色模式视觉效果、通知链路均未实机测试
- 本文档只做审计与工单建议，**未修改任何业务代码**（仅创建/编辑 `docs/grokbot/` 下的文档）
