# Centli（厘记）— 第二轮审计与优化清单

> 审计日期：2026-10-16（Asia/Shanghai，第二轮）
> 上一轮基线：[`docs/issue_audit.md`](./issue_audit.md)（52 项，未修改）
> 本轮方式：**纯静态读码**（read / glob / grep）+ 三路并行审计
> 本轮结论：已修 16 项 / 半修 5 项 / 仍存在 10 项 / 新增 12 项

---

## 0. 本轮范围与限制

### 0.1 限制（与上一轮相同的阻塞）

**shell 仍不可用**。每次 `pwsh` 均返回：

```
Error: SetNamedSecurityInfoW failed (Win32 5): grantWrite(D:\Resource\Codebase\studyProject\Centli)
```

因此**未运行 `flutter analyze` / `flutter test` / 任何构建**。全部结论来自读码；运行时行为推断标注为「⚠️ 推测」。

> 这意味着：本轮所有"已修复"判定均基于**代码已改**，未经运行时验证。建议恢复 shell 后跑一次 `flutter analyze` + `flutter test` 复核。

### 0.2 状态标记

| 标记 | 含义 |
|---|---|
| ✅ 已修复 | 已读当前代码确认修复正确 |
| 🟡 半修复 | 部分修好，但存在残留缺口（需继续处理） |
| ❌ 仍存在 | 本轮核实仍未修 |
| 🆕 新增 | 本轮新发现（含新功能引入的缺陷） |
| ⚠️ 推测 | 未运行验证 |

### 0.3 本轮已复核的文件

`lib/data/db/centli_database.dart`、`lib/data/export/import_service.dart`、
`lib/platform/notifications/noti_template_store.dart`、`notification_parse.dart`、
`notification_listener_io.dart`、`notification_ingest_bridge.dart`、
`lib/features/ledger/bookkeeping_sheet.dart`、`lib/features/pending/pending_page.dart`、
`lib/features/settings/permission_explain_page.dart`、`recognition_rules_page.dart`、
`recognition_rule_edit_page.dart`、`lib/features/assets/assets_page.dart`、
`lib/features/home/home_page.dart`、`lib/app/theme.dart`、`lib/app/router.dart`、
`android/.../NativeCaptureIngest.kt`、`CentliNotificationListener.kt`、`MainActivity.kt`、
`ios/Runner/AppDelegate.swift`

### 0.4 未复核（本轮可能仍有遗漏）

`android/app/build.gradle`、`ios/Runner/Info.plist`（仅由子代理间接核实 scheme）、
`windows/`、`web/`、`core/widgets/` 中的 `category_visuals.dart` / `centli_icon.dart` /
`icon_picker_sheet.dart` / `date_range_control.dart`、`features/settings/` 的
`export_page` / `import_page` / `fx_rates_page` / `recycle_bin_page` / `ledgers_page` /
`categories_page` / `budget_page` / `auto_capture_page` 内部逻辑、
`features/assets/account_detail_page.dart` 主体、`stats/stats_page.dart` 图表渲染段、
`stats/category_drill_page.dart`、`ledger/search_page.dart` 筛选实现

---

## 1. ✅ 已修复（16 项，确认无需再动）

| 原编号 | 问题 | 当前修复方式 | 证据 |
|---|---|---|---|
| #1 | 还原清空**所有**账本 | 改为按 `lid` 作用域清空 | `centli_database.dart:2134-2140` |
| #2 | `merchant` 列无写入路径 | `insert/updateManualTransaction` 加参数并传值 | `centli_database.dart`、`bookkeeping_sheet.dart:549,564` |
| #4 | Excel 还原清空汇率且不恢复 | 新增 `replaceFxRates` 开关 | `centli_database.dart:2141-2143,2164-2168` |
| #5 | iOS handler 被 `supported` 短路 | 新增 `channelSupported`（Android+iOS）+ `bridgeReady` 握手 | `notification_listener_io.dart:28-29,128-148` |
| #6 | 编辑已归档账户流水必崩 | `_load` 把引用到的非活跃账户补进列表 | `bookkeeping_sheet.dart:93-107` |
| #7 | 跨币种弹窗控制器泄漏 | 改为 `try/finally` 释放 | `bookkeeping_sheet.dart:435-438` |
| #8 | JPY 在原生路径差 100 倍 | 原生加 `currencyDecimals`/`toMinor`；打印按小数位 | `NativeCaptureIngest.kt:189-197,269-273` |
| #9 | 金额正则把日期当金额 | 两侧都改为**必须**有币种码或符号；并跳过后随「月日号时分秒」 | `notification_parse.dart:162-163,399-403`；`NativeCaptureIngest.kt:185-187,203-211` |
| #10 | 原生队列「先删后发」 | `peekQueue`/`clearQueue` 分离 + `dartBridgeReady` 门禁 | `MainActivity.kt:187-200` |
| #12 | 权限页隐式开启采集 | 已移除强制置 true，只做 rebind | `permission_explain_page.dart:73-77` |
| #13 | 原生 `auto_capture_enabled` 默认值相反 | 已统一 | （子代理核实） |
| #22 | 外键未启用 | `beforeOpen` + `PRAGMA foreign_keys = ON` | `centli_database.dart:60-61` |
| #23 | 调试按钮进生产 | 已包 `if (kDebugMode)` | `pending_page.dart:93-95` |
| #24 | 导入 `schema_version` 上限 2 | 提到 3 | `import_service.dart:127` |
| #35 | 转账两下拉框重复 `ValueKey` | 结构性消失：整个文件已无 `DropdownButtonFormField`/`ValueKey`，改用 `_AccountPickerSheet`（普通 ListView） | `bookkeeping_sheet.dart:1607-1687` |
| #47 | 备份文件入库（7 个 `.bak_*`） | 已清理 | glob 确认 |

### 1.1 额外收获（超出上一轮建议）

- **`bridgeReady` 握手**：不仅修了 iOS，还顺带治掉了 #10 的竞态。Dart handler 绑定后才让原生 flush 队列——这正是建议的 ack 语义，而且原注释还标了 `(#10)`。
- **通道 handler 去重**：原先两份重复实现已合并为单一 `_onMethodCall`。
- **主题层重构**：新增 `CentliSpacing` 令牌（`theme.dart:5-49`）+ `CentliSoftCard` / `CentliGradientScaffold`；`dark()` 补上了 `inputDecorationTheme`（`theme.dart:165-177` / 深色补齐）。上一轮 #41 的"硬编码间距"部分基本解决。
- **`noti_template_store.dart` 架构重做**：官方/用户规则分离、`disabled_official_ids` 禁用集、合并顺序 `我的 ∪ (官方 − 已禁用)`、网络导入 HTTPS 强制 + client 正确释放（`:349-395`）。
- **`recognition_rules_page.dart` 新增「试一试」**：`explainNotificationParse` 带解释步骤，是很好的自助排障工具。

---

## 2. 🟡 半修复（5 项，需继续处理）

### 2.1 【高】#12 待确认入账恒记为支出 — 比原来更隐蔽

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/pending/pending_page.dart:452-458`、`:609-618`；`lib/data/db/centli_database.dart:1396` |
| 状态 | 🟡 半修复 |

分类列表已同时加载 `out` + `in`：

```dart
final out = await db.loadCategories(widget.ledgerId, 'out');
final inn = await db.loadCategories(widget.ledgerId, 'in');
return [...out, ...inn];
```

但入账调用**未传 `type:`**：

```dart
await ref.read(databaseProvider).confirmPendingCapture(
  pendingId: c.id,
  amountMinor: toMinor(ccy, major),
  currency: ccy,
  accountId: _accountId!,
  categoryId: _categoryId!,
  merchant: _merchantField.text.trim().isEmpty ? null : _merchantField.text.trim(),
);
```

而 `confirmPendingCapture` 的默认值是 `String type = 'out'`（`centli_database.dart:1396`），卡片上也没有收/支切换。

**后果**：选中「工资」入账，写入的仍是**支出**。修复前是"选不到收入分类"，修复后是"**选得到但静默记成支出**"——误导性更强。

**修复方向**：卡片加收/支切换（或按所选分类的 `kind` 自动推断），并把 `type` 传下去。若走自动推断更省事：选中分类的 `kind` 即 `out`/`in`。

---

### 2.2 #4 去重键不一致仍会在微信场景重复

| 项 | 内容 |
|---|---|
| 位置 | `notification_parse.dart:189,219-224` ↔ `NativeCaptureIngest.kt:245-253` |
| 状态 | 🟡 半修复（键格式已统一，语义仍未统一） |

键格式、时间桶、小写归一化现在两侧一致。但**商户提取**仍不同：

- 微信 `title == "微信支付"`：Dart 因 `merchantFromTitle: true` → `merchantRegex (.+?)(?:-微信支付|付款)` 匹配不上裸标题 → `merchant = "微信支付"`；Kotlin 的 `guessMerchant` 走通用分支 → `null` 或从正文取
- 非通用标题：Dart 从正文取商户，Kotlin 直接返回 title → 反向不一致

**后果**：两条路径都跑（`CentliNotificationListener.kt:74` 原生先写，`:80` 再通知 Dart），键不同 → **重复账单 + 重复推送**。

**修复方向**：把商户归一化逻辑抽成单一事实来源（至少统一"裸 `微信支付` 标题"这一类的处理），或让原生侧对已有 `dedupe` 之外的兜底键再做一次模糊匹配。

---

### 2.3 #3 iOS：深链已通，但分享入口仍缺

| 项 | 内容 |
|---|---|
| 位置 | `ios/Runner/AppDelegate.swift`、`ios/Runner/SceneDelegate.swift`、`ios/Runner/Info.plist:75-85`、`ios/Runner.xcodeproj/project.pbxproj` |
| 状态 | 🟡 半修复 |

已修好：`bindPendingIntake` 不再被 `supported` 短路、`SceneDelegate` 转发 `openURLContexts`、`Info.plist` 声明了 `centli` scheme → **`centli://pending` 深链现在可用**。

仍缺：
- **没有 iOS Share Extension target**（`project.pbxproj` 中 `appex|ShareExtension` 零匹配）→ **iOS 分享菜单路径不存在**
- 冷启动经 `SceneDelegate.willConnect` 的 URL 投递未处理（仅 `openURLContexts`）

**修复方向**：若要 iOS 分享导入，需新建 Share Extension target；否则至少在文档/UI 明确"iOS 仅支持深链，不支持分享"。

---

### 2.4 #7 数组校验只覆盖 3 个

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/export/import_service.dart:141-167,277-290` |
| 状态 | 🟡 半修复 |

必需数组：`accounts`、`categories`、`transactions`（`:141-145`）。
仍可缺省为 `[]`：`merchant_rules`、`pending_captures`、`fx_rates`、`budgets`（`:156-167`）。

**后果**：一份**合法但省略了 `budgets`/`fx_rates`** 的备份仍会静默清空这两张表（作用域内）。#1 的整库危险已消除，但"缺字段即清空"的模式仍在。

其他小问题：
- `"accounts": null` 能通过 `containsKey` 检查，随后报英文 `'accounts cannot be null'`
- 错误文案**中英混杂**：`'missing required field: $key'` / `'$field cannot be null'`（英）vs `'$field 必须是数组'` / `'缺少账本信息'` / `'不支持的数据版本 schema_version=…'`（中）
- `_asMapList` **静默丢弃**非 Map 元素（`:287-290`），用户不会知道少导了几条

**修复方向**：把 4 个可选数组也纳入"存在性"校验（或至少校验计数一致性）；错误文案统一中文；非 Map 元素改为计数上报。

---

### 2.5 #16 PIN：限流已加，但哈希仍是单轮 SHA-256

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/security/app_lock_service.dart:20-25,43-53,55-77,135-138`；`lib/features/security/pin_pad.dart:243-260` |
| 状态 | 🟡 半修复 |

**已修**（我上一轮判断有误，此处更正）：失败限流已实现 —— `_maxFails = 5`、`_lockoutMs = 60_000`、`lockoutRemaining()`，并在 `app_lock_page.dart:74-82` 以 `SnackBar('Try again in Ns')` 呈现。

**仍缺**：
- 哈希仍是**单轮** `sha256.convert(utf8.encode('$salt:$pin'))`，无 PBKDF2/Argon2/迭代数
- `pin_pad.dart:243-260` 的验证弹窗（修改 PIN / 关闭应用锁时的身份验证）只显示通用「PIN 错误」，**没有锁定倒计时**——与解锁页体验不一致，用户会以为可以继续试
- 格式正则仍硬编码 `6` 而非 `kAppLockPinLength`

**修复方向**：换 PBKDF2（Dart 用 `cryptography` 或 `pointycastle`）并保留失败退避；`showVerifyPinDialog` 接上 `lockoutRemaining()`。

---

## 3. 🆕 新增问题（本轮新发现，12 项）

### 3.1 【严重】还原会跨账本串数据

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/db/centli_database.dart:2134-2140`（清空）↔ `:2155-2163`（插入） |
| 状态 | 🆕 新增 |

清空已按 `lid` 作用域（正确），但插入是**原样照搬**每一行的 `ledgerId`，既不做归一化也不做校验：

```dart
for (final t in txnRows) {
  await into(transactions).insert(t.toCompanion(true));   // ledgerId 来自备份原文
}
```

由于外键现在**真的生效**（`PRAGMA foreign_keys = ON`，`:61`），后果分两种：

| 子行 `ledgerId` | 实际行为 |
|---|---|
| 本地不存在的账本 | 外键冲突 → **整个还原回滚**（行为尚可接受，但错误信息对用户不可读） |
| 本地**已存在**的另一个账本 | **插入成功**，挂到那个账本上，在还原的账本里查询不到（所有查询按 `ledgerId` 过滤）→ **跨账本串数据**；日后清空那个账本会把它一起删掉 |

**触发条件**：手工编辑过的备份、或由多个来源拼接的备份。正常导出不会有此问题（子行 `ledgerId` 恒等于顶层 id）。

**修复方向**：插入前把每行的 `ledgerId` 强制写成顶层 `lid`（并与顶层 `ledger.id` 做一致性校验后拒绝或修正）。这是 #1 修复后的正确收尾。

---

### 3.2 【严重】用户识别规则会被静默永久清空

| 项 | 内容 |
|---|---|
| 位置 | `lib/platform/notifications/noti_template_store.dart:108-140`、`:397-401`；`lib/platform/notifications/notification_parse.dart:39,41,46` |
| 状态 | 🆕 新增（新功能引入） |

**链路**：

1. `NotiTemplate.fromJson` 对关键字段是**硬转换**（`notification_parse.dart:39,41,46`）：

```dart
id: j['id'] as String,                             // 缺 id → throw
packages: (j['packages'] as List).cast<String>(),  // 非字符串数组 → throw
amountRegex: j['amountRegex'] as String,           // 缺字段 → throw
```

2. `_loadUserFile` 中**任一条目**抛错 → 整个列表解析中止 → catch 把内存置空（`noti_template_store.dart:127-139`）：

```dart
for (final item in list) { ... }   // 一条坏 → 全表丢
_user = templates;
} catch (_) {
  _user = [];                      // 静默吞掉
  _disabledOfficialIds = {};
}
```

另外 `:116`（顶层非 Map）与 `:126`（`templates` 非 List）也提前 `return`，同样只留 `_user = []`。

3. **致命的一步**：文件此刻仍在磁盘上，但只要用户做任何写操作，`_persistUserFile()`（`:397-401`）就把**空集合**落盘 → **全部规则永久消失**。

**触发场景**（都很现实）：
- 用「从文件导入」导入一份 JSON，其中某条目缺 `amountRegex` → `importUserRulesJson` **不校验 schema 也不校验正则**，静默写入坏条目
- 之后在编辑页**新增或修改任意一条规则** → 旧规则全灭
- **无提示、无撤销、无备份**

**连带隐患**：解析侧 `notification_ingest_bridge.dart:47-48` 调 `parseNotification` 时**无 try/catch**，而 `notification_parse.dart:204,290,396` 直接 `RegExp(...)` → 一条坏正则会让异常抛回 MethodChannel（`notification_listener_io.dart:157`），**该通知静默丢失**，且中断后续所有候选规则的匹配。

**修复方向**（都很小）：
- `fromJson` 改为逐条 try/catch，**跳过坏条目并计数上报**，而非整表落空
- `_loadUserFile` 的 catch **不清空**（保留上次已知good值）并记录错误
- 导入复用编辑页已有的正则校验（`recognition_rule_edit_page.dart:126-143`）
- `parseNotification` 调用点加 try/catch，坏规则只跳过该条
- 写盘前先备份旧文件（`.bak`）—— 这是用户自己攒的规则

---

### 3.3 【高】识别规则编辑会丢字段

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/settings/recognition_rule_edit_page.dart:151-162`、`:68`、`:90-101`、`:117` |
| 状态 | 🆕 新增 |

- `defaultCurrency` **未在编辑页建模**，保存时 `NotiTemplate(...)` 不传该字段 → 回落 `'CNY'`
- `packages` **只取第一个**（`:68`）且**只写回一个**（`:90-101`、`:117`）

**后果**：导入的**多包规则**或**非 CNY 规则**，只要在编辑页点一次保存，就被静默改写成"单包 + CNY"。用户以为只是改了个名字。

**修复方向**：给 `defaultCurrency` 加下拉；`packages` 改为多值编辑（或至少在保存时保留未编辑的其余包名）。

---

### 3.4 【高】规则文件不在任何备份里

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/export/export_service.dart` ↔ `noti_template_store.dart:434-437` |
| 状态 | 🆕 新增 |

`我的规则` 存在 `documents/user_noti_templates.json`，而 `/me/export` 的 JSON/Excel 导出**完全不含**该文件。

**后果**：换机、重装、清数据 → **全部自定义规则丢失**，且用户会以为备份是完整的（因为走的是"导出/导入"这条官方路径）。

**修复方向**：把 `user_noti_templates.json` 纳入导出 bundle（如 `recognition_rules` 键）与还原流程；否则至少在导出页明确提示"不含识别规则"。

---

### 3.5 【中】规则「替换」导入不可撤销

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/settings/recognition_rules_page.dart:162-183`、`:247-267`；`noti_template_store.dart:337-340` |
| 状态 | 🆕 新增 |

对话框只问"合并还是完全替换？"，**措辞轻描淡写**；「替换」直接 `replaceUserTemplates(imported, ...)` 覆盖，无预检、无导出提醒、无撤销。

**后果**：误点「替换」用一个错误/空文件覆盖掉全部规则。结合 §3.4（无备份），后果不可逆。

**修复方向**：替换前自动导出当前规则到剪贴板/文件作为保险；对话框写明"将删除现有 N 条规则"。

---

### 3.6 【中】编辑不存在的 id 会静默变成新建

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/settings/recognition_rule_edit_page.dart:54-88` |
| 状态 | 🆕 新增 |

`_bootstrap` 在 `peekUser()` 中找不到 `widget.ruleId` 时，`_editingId` 保持 `null` → 保存走新建分支生成 `user_<uuid>`。

**后果**：用户以为在改旧规则，实际是新建了一条，旧的原封不动（于是"改完没生效"）。

**修复方向**：找不到时提示"规则不存在"并禁用保存，或返回列表。

---

### 3.7 【中】编辑会改变匹配优先级

| 项 | 内容 |
|---|---|
| 位置 | `lib/platform/notifications/noti_template_store.dart:257-269`；`notification_parse.dart:202-239` |
| 状态 | 🆕 新增 |

`upsertUserTemplate` 是"先删同 id、再追加到末尾"，而匹配顺序 = 数组顺序、**先到先得**。

**后果**：仅编辑一条规则的名称，就会把它从优先级第 1 位挪到末尾，可能被后加的宽泛规则抢先匹配。且 UI **没有手动排序**。

**修复方向**：保持原位置（按 index 替换而非删除+追加）；或加拖拽排序 + 显示匹配顺序。

---

### 3.8 【中】禁用官方规则无确认、无撤销

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/settings/recognition_rules_page.dart:326-337`；`noti_template_store.dart:245-255` |
| 状态 | 🆕 新增 |

底部弹层里一个 Switch，切换即 `setOfficialDisabled` 并立即 pop。无确认、无撤销、SnackBar 无 action。`setOfficialDisabled` 自身也**无 try/catch**，写盘失败时用户以为已生效。

**修复方向**：加确认或至少加撤销 SnackBar；`setOfficialDisabled` 包 try/catch 并提示。

---

### 3.9 【中】三套金额正则不一致

| 项 | 内容 |
|---|---|
| 位置 | `notification_parse.dart:162-163`（Dart builtin）、`assets/noti_templates.json:14,28`、`NativeCaptureIngest.kt:185-187`（Kotlin） |
| 状态 | 🆕 新增 |

| 来源 | 是否要求货币符号 |
|---|---|
| Dart builtin `kAmountRegex` | **要求**（`(?:...\|(?:¥\|￥\|$\|€))`） |
| `assets/noti_templates.json` | **不要求**（可选） |
| Kotlin `AMOUNT` | **要求** |

而编辑页的"金额正则"默认值用的是 **builtin 版**（`recognition_rule_edit_page.dart:26`）。

**后果**：同一条逻辑规则，在"设备实际加载的官方规则"（assets）与"内置兜底"（builtin）下行为不同——而这正是 #9 修复的那个 bug 的变体。用户在"试一试"里看到的结果可能与真机不符。

**修复方向**：以 builtin 为准统一三者（assets JSON 也要改），并在文档中固定该约定。

---

### 3.10 【低】规则相关的其他摩擦

| 问题 | 位置 | 说明 |
|---|---|---|
| 「试一试」无 try/catch | `recognition_rules_page.dart:113-125` | 命中坏规则时 release 下异常被吞，按钮"没反应" |
| 导入绕过正则校验 | `noti_template_store.dart:301-343` | 与编辑页 `:126-143` 的校验能力不对等 |
| 无重复规则检测 | `noti_template_store.dart:257-269` | 同名同包可无限添加，且无 id 冲突检查（可与官方 id 同名） |
| `_hintForChoice` 静默改写「无」 | `recognition_rule_edit_page.dart:103-113` | 用户显式选「无」，但 hint 为 null 且 app 为 alipay/wechat 时会被"补回" |
| 「试一试」切「其它」不清空包名 | `:30-32` vs `:541-552` | 保留上一次支付宝包名，易测错对象 |
| 「我的规则」无正则预览 | 列表/详情 | 官方规则详情页把原始正则全展示（`:290-344`），自己的规则反而看不到，保存后无法核对 |
| `installBundledOverride` 疑似死代码 | `noti_template_store.dart:214-239` | 需确认是否仍有调用点 |
| 规则无任何测试 | `test/` | 8 个测试文件无一提及 `NotiTemplateStore` / 用户规则 / 导入导出 / 非法正则 |

---

## 4. ❌ 仍存在（10 项，本轮核实未修）

### 4.1 【高】锁屏通知明文金额 + `hide_amount` 覆盖不全

| 项 | 内容 |
|---|---|
| 位置 | `android/.../NativeCaptureIngest.kt:94-99`；`PendingConfirmNotifier.kt:62-72`；`notification_ingest_bridge.dart:94-102`；`pending_capture_intake.dart:191-197`；`pending_page.dart:534` |
| 状态 | ❌ 仍存在 |

- 待确认推送恒为 `待确认 ¥xx`，**不读 `hide_amount`**
- `PendingConfirmNotifier` 的 builder 链止于 `.setAutoCancel(true).setOnlyAlertOnce(true)`，**无 `setVisibility(...)`** → 锁屏可见明文金额（`android/` 下 grep `VISIBILITY_SECRET|setVisibility|hide_amount` = 0 匹配）
- **待确认页也不生效**：`pending_page.dart:534` 的 `formatMinor(ccy, c.amountMinor!)` **漏传 `hide`**，而首页/统计/详情都传了

**影响**：记账是敏感数据。你开了"隐藏金额"，但锁屏通知和待确认页仍然明示——保护是漏的。

**修复方向**：推送标题按 `hide_amount` 决定是否显示金额，并加 `setVisibility(VISIBILITY_SECRET)`；待确认页补 `hide`。

---

### 4.2 【中】全库零索引

| 项 | 内容 |
|---|---|
| 位置 | 全库；`centli_database.dart:43`（`schemaVersion => 3`）、`:51-59`（迁移） |
| 状态 | ❌ 仍存在 |

grep 确认：`@TableIndex` = 0、`CREATE INDEX` / `createIndex` = 0、`tables/*.dart` 中 `index` = 0。

上一轮文档声明的 8 类索引**一个都没建**，`beforeOpen`（`:60-61`）里也没有补建。

**影响**：`(ledger_id, happen_at)` 是首页/统计/账单列表的主查询路径。当前数据量下无感，但记账 App 的数据是**只增不减**的，一两年后列表滚动与统计会明显变慢。

**修复方向**：加 `@TableIndex` + 迁移到 v4 建成，或直接在 `beforeOpen` 里 `CREATE INDEX IF NOT EXISTS`（更省事，且对新旧库都生效）。

---

### 4.3 【中】FX 无交叉汇率 —— 本位币非 CNY 时基本失效

| 项 | 内容 |
|---|---|
| 位置 | `lib/core/utils/fx.dart:59-70`、`:72-84` |
| 状态 | ❌ 仍存在 |

`rate()` 只做两次查找：正向 `_rateOnOrBefore(from,to)`、反向 `1/_rateOnOrBefore(to,from)`。**不经基准货币两跳换算**。

而远端服务只写入 `foreign → base` 一个方向（`fx_remote_service.dart:101-120`）。

**后果**：只要本位币不是 CNY，**任何两个非本位币之间**（JPY→TWD、USD→EUR）换算都会失败，这些流水落入 `unconverted` 不计入统计。

**修复方向**：在三跳内允许 `from → base → to`（用已在库中的 base 报价做三角换算）。

---

### 4.4 【中】金额全链路仍是 `double`

| 项 | 内容 |
|---|---|
| 位置 | `lib/core/utils/money.dart:3-12`；`lib/core/utils/fx.dart:15`、`:105-117` |
| 状态 | ❌ 仍存在 |

```dart
int toMinor(String ccy, double major) { ... return (major * factor).round(); }
static int applyRate({... required double rate ...}) {
  final major = amountMinor / fromFactor;
  return (major * rate * toFactor).round();
}
```

存储是整数最小单位（正确），但**解析 / 换算 / 汇总仍走 double**，每次换算都 `.round()`。

**影响**：单次误差极小，但汇率换算会二次放大，长期累积。记账应用的金额准确性是底线。

**修复方向**：引入 `Decimal`（或用整数比例运算）替换 `double`；至少让 `applyRate` 用整数化率值。

---

### 4.5 其余仍存在项

| 原编号 | 问题 | 位置 | 影响 |
|---|---|---|---|
| #11 | FX 日期语义混用 + 空结果也写门禁 | `fx_remote_service.dart` | 供应商更新日 vs 本地今天混用；`upserted==0` 也不重试 |
| #19 | 原生过滤硬编码，用户规则不下发 | `NativeCaptureIngest.kt:174-183` | 包名能同步（`watched_packages`），但 `isPaymentCandidate` 对非支付宝/微信 `return false` → **自定义包名规则仅在 App 存活时有效**；进程被杀时用户规则与"禁用官方"一律无效。`docs/recognition_rules.md:18-22` 已承认，但 UI 未告知 |
| #25 | Excel 往返丢字段 | `import_service.dart:487`、`export_service.dart` | `include_in_budget` 强制 1、`transfer_group_id`/`pending_id`/两个 `icon` 不在 sheet |
| #26 | Excel 按列序号解析、无表头校验 | `import_service.dart:424-553,597-603` | 用户编辑过 Excel 后会静默写入 0 元流水 |
| #27 | 见 §4.4 | — | — |
| #28 | 见 §4.3 | — | — |
| #30 | FX 门禁语义 | `fx_remote_service.dart:122,144-146` | — |
| #31 | `http.Client` 未关闭（FX 服务） | `fx_remote_service.dart:38,156` | 注：`importUserRulesFromUrl` 已正确 close |
| #40 | 列表行内 N+1 查询 | `txn_list_tile.dart`、`home_page.dart` | 每行 3 个 `FutureBuilder` 且重复查同一分类；千条量级滚动会卡 |
| #43 | 版本号两处落后 | `me_page.dart:169`、`export_service.dart:47` | 仍是 `1.0.0+1`，pubspec 与 `about_page.dart:9` 为 `1.0.1+2` |

---

## 5. 日常动线 UX 优化（本轮重点）

### 5.1 「记一笔」实测点击成本

最常用场景「¥28.5 · 餐饮 · 支付宝」：

| 步骤 | 点击 |
|---|---|
| 底部导航「记账」 | 1 |
| 金额 `2` `8` `.` `5` | 4 |
| 分类 chip → 父类 → 子类 | 3 |
| 账户 chip → 账户行 | 2 |
| `✓` 保存 | 1 |
| **合计** | **11** |

支出/收入/转账默认「支出」、时间默认 now，均 0 点击。**若默认分类与账户刚好命中，为 6 击**。

### 5.2 TOP 10 改进（按 收益 ÷ 成本 排序）

| # | 改进项 | 用户收益 | 成本 | 优先级 |
|---|---|---|---|---|
| **1** | **记住上次账户 + 分类**，作为下次默认 | 每笔省 5 击（11→6）。当前默认取 `accounts.first`/`cats.first`（`bookkeeping_sheet.dart:150-152`）即 sortOrder 最小项；若「支付宝」不是排序第一，**每笔都多花 5 击**。全库无 last-used 设置键 | S | **P0** |
| **2** | **保存后 Toast + 「撤销」**，并给 `_save` 加 `catch` | 现正常保存**直接 pop、无任何提示**；`_save` 只有 try/finally 无 catch（DB 异常无提示）；`_ledgerId==null \|\| _accountId==null` 时点 ✓ **完全静默**（`:462`） | S | **P0** |
| **3** | 金额支持**粘贴** / 系统数字键盘，接上 `'00'`、加「万」键 | 金额不是 `TextField` 故**无法粘贴**；`'00'` 分支存在（`:300-310`）但 `_keys`（`:1702-1707`）**没有该键** = 死代码；无「万/千」 | S-M | **P0** |
| **4** | 面板加**今天 / 昨天 / 前天**快捷键 | 补记从 4-5 击降到 1 击（现点击 chip 后串行弹日期 + 时间两个选择器，`:604-636`） | S | P1 |
| **5** | 「保存并继续」做成**可见按钮** | 现只能**长按 ✓**（`:1502-1504,1751`），全应用无任何文案提示该交互存在 | S | P1 |
| **6** | **记账面板 / 分类选择器改用主题色** | 暗色模式**白底浅字 → 不可用**（见 §5.3） | S | P1 |
| **7** | 列表行**左滑删除 / 编辑** + 删除后 **SnackBar 撤销** | 全库无 `Dismissible`/`Slidable`、无 `SnackBarAction`（**全应用零撤销**）；删一条要先进详情 3 步 | M | P1 |
| **8** | 待确认：分类按收/支过滤 + 复用上次账户 + 左滑入账/忽略 + 入账可撤销 | 第二高频动线，每条要点 3 个下拉（`pending_page.dart:452-506`） | M | P1 |
| **9** | Android **长按图标「记一笔」**快捷方式 + 小组件点击直达记账面板 | 无 `res/xml/shortcuts.xml`；小组件点击只路由到 `/home` 或 `/home/pending`（`centli_home_widget_sync.dart:114-125`） | M | P1 |
| **10** | 文案/一致性收口（见 §5.4） | 降低困惑与误读 | M | P2 |

### 5.3 【功能性不可用】暗色模式记账面板

面板硬编码白底：`bookkeeping_sheet.dart:24, 1068, 1561`、`category_picker_sheet.dart:20`。
但内部文字用 `Theme.of(context)` 取色 → 暗色 scheme 的 `onSurface` 是**浅色** → **白底浅字**。

具体位置：金额大字 `:1334-1343`、分类 chip `:1595`。
同族硬编码：`Color(0xFFF7F8FA)`(`:1474`)、`Color(0xFFE6E8EC)`(`:1478,1485,1570`)、键盘 `Color(0xFF333333)`(`:1720`)、`Color(0xFFC62828)`(`:1718`)。

**若日常使用暗色，记账面板现在是不可用的**。改法：面板/选择器底色改 `scheme.surface`，键盘色改用 `colorScheme` 派生。

其他暗色残留：`home_page.dart:406`（选中 tab `Colors.white`）、`assets_page.dart:589` 同类、`home_page.dart:533` 与 `:710-713` 的低对比度小字。

### 5.4 一致性 / 反馈 / 无障碍（低成本高感知）

| 类别 | 问题 | 位置 |
|---|---|---|
| **配色** | **收入颜色三套并存**：列表用自定绿色常量（`txn_list_tile.dart:14-15`，与 `theme.dart:61-62` 重复）、首页日历用 `CentliTheme.incomeGreen`、详情页用 `scheme.primary`（蓝）→ **同一笔收入列表绿、详情蓝** | 三处 |
| **文案** | 首页空态「点**右下角**记账按钮」，实际在**底部导航正中** | `home_page.dart:298` |
| **口径** | 首页标签写死「**月**收入/月支出」，而默认区间是「**近 30 天**」或自定义 → 标签与数据不符 | `home_page.dart:504,511` vs `date_range_control.dart:96` |
| **术语** | 首页「月收入/月支出」vs 统计「收入合计/支出合计」；面板 chip 显示「现金 · CNY」而选择器显示「人民币」 | 多处 |
| **错误态** | 直接把 Dart 异常字符串上屏（`Text('$e')`）；预算区 loading 是 `SizedBox.shrink()` → 静默空白无骨架 | `stats_page.dart:172,299,335,490`、`home_page.dart:274,349`、`search_page.dart:348` |
| **静默 no-op** | 记账 `:462`、`:841`；待确认「忽略」成功**不弹提示**（`pending_page.dart:636-644`） | — |
| **误关闭丢数据** | `showModalBottomSheet` 未设 `isDismissible:false`，无 `PopScope` → 下滑/点 X 直接丢弃已输入内容，无确认无草稿 | `bookkeeping_sheet.dart:20-30,1153-1156` |
| **触摸目标** | `_MetaChip` 40dp、`_ModeTab` ~32dp（低于 48dp 建议）；键盘键 52dp ✓ | `:1525`、`home_page.dart:412` |
| **字号** | 日历日期金额 `fontSize: 9` 且无 `FittedBox` → 系统字体放大后 7 列固定网格**必然溢出** | `home_page.dart:771,780-783` |
| **对比度** | `Color(0xFF9AA0A6)` 11px、`Color(0xFF8A8F98)` 12px 白底上低于 4.5:1 | `home_page.dart:710-713,533` |
| **无障碍** | 全库**零 `Semantics`**；日历仅靠红/绿区分收支，**无色盲冗余编码** | 全库、`home_page.dart:768-785` |
| **单手** | 「记账」在底部导航正中 ✓；搜索/隐藏金额在右上角，大屏单手够不到 | `shell.dart:15-25`、`home_page.dart:167-182` |

### 5.5 缺失的生活质量功能（供参考，属可接受空缺）

- 快速重复上一笔
- 系统/IME 数字键盘（仅自绘键盘）
- 模板 / 收藏 / 常用分类
- 列表内联改金额
- 多选批量删除
- 小票照片附件（`image_picker` 目前仅用于待确认 OCR）
- 标签（表无 `tags` 列）
- 搜索历史
- 按月对比 / 环比
- 订阅 / 周期性识别
- 预算超支**本地通知**（目前只有统计页进度条 + `ratio>=0.8` 变色 + 「超支」文案）
- 待确认**批量入账**（只有「全部忽略」）
- iOS Share Extension（见 §2.3）

---

## 6. 建议执行顺序

| 批次 | 内容 | 理由 |
|---|---|---|
| **P0** | §2.1 待确认恒为支出 · §3.2 用户规则静默清空 · §3.1 还原 `ledgerId` 归一化 · §5.3 暗色记账面板 | 前两条是数据正确性/丢失；第三条是 #1 修复的正确收尾；第四条是功能性不可用。**改动都在 5-20 行内** |
| **P1** | §5.2 #1 记住上次账户分类 · #2 保存反馈+撤销 · §4.1 锁屏与待确认页 `hide_amount` · §3.4 规则纳入备份 | 体验杠杆最高 + 消除隐私泄漏 + 防换机丢规则 |
| **P2** | §3.3 编辑丢字段 · §3.5 替换可撤销 · §3.6/3.7 编辑语义 · §3.8 禁用确认 · §3.9 三套正则统一 · §2.2 去重键 · §4.2 索引 | 规则功能健壮性 + 长期性能 |
| **P3** | §2.4 数组校验补齐 · §4.3 FX 交叉汇率 · §4.4 Decimal · §4.5 其余项 · §5.4 一致性收口 | 结构性改进，需要更多验证 |
| **P4** | 补测试（规则/还原/多账本）、恢复 shell 后跑 `analyze`+`test` | 防回归 |

---

## 7. 修正记录（对上一轮审计的更正）

保持透明，记录本轮推翻或修正的上一轮结论：

| 上一轮表述 | 更正 |
|---|---|
| #16「PIN 无失败计数、无锁定、无退避」 | **错误**。限流已实现（`_maxFails=5`、`_lockoutMs=60_000`，`app_lock_service.dart:20-25,43-53,55-77`）。上一轮读的是旧版文件。仍成立的是"单轮 SHA-256"与"pin_pad 弹窗无倒计时" |
| #12「权限页隐式开启采集」判定为已修 | **修正为半修**。`auto_capture_enabled` 确实不再被强制置 true，但待确认入账**恒记支出**（§2.1），比原来更具误导性 |
| #4「去重键不一致」 | 键格式已统一，但**商户语义仍不一致**（§2.2），微信场景仍会重复 |
| #3「Excel 清空汇率」 | 该项**已修**（`replaceFxRates`）；此处 #3 指上一轮的"数组校验"，现为**半修**（只覆盖 3/7 个数组） |
| #21「索引缺失」 | 上一轮不确定是否用 `beforeOpen` 补建；本轮 grep 确认**完全没建**（§4.2） |
| #35「重复 ValueKey」 | 已由重构**结构性消除**（文件内已无 `DropdownButtonFormField`） |

---

## 8. 结论

这一轮的修复质量很高，且明显是**按根因**改的：作用域化还原、外键启用、`replaceFxRates` 开关、`bridgeReady` 握手、原生金额单位统一、`kDebugMode` 门禁——这些都不是打补丁。

剩余风险集中在三处：

1. **新功能自身的健壮性**：识别规则可能被静默清空（§3.2）、不在备份里（§3.4）、编辑会丢字段与改变优先级（§3.3/§3.7）。这是当前最该收口的地方。
2. **还原路径的正确收尾**：`ledgerId` 未归一化导致跨账本串数据（§3.1）——这是 #1 修复后遗留的最后一段。
3. **日常体验的两个零**：「零记忆」与「零反馈」（§5.2 #1/#2）——改动极小，却直接决定每笔记账是 6 击还是 11 击，以及失败时是否静默。

另外，**暗色模式记账面板不可用**（§5.3）属于功能性缺陷，若日常用暗色应优先于多数优化项。
