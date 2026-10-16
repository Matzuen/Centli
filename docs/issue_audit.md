# Centli（厘记）— 问题审计清单

> 审计日期：2026-10-16（Asia/Shanghai）
> 审计方式：**纯静态读码**（read / glob / grep）
> 审计范围：`lib/`、`android/`、`ios/`、`test/`、`assets/`、`docs/`
> 问题总数：**52 项**，按危险等级从高到低排列

---

## 0. 覆盖边界与可信度说明

### 0.1 重要限制

**本会话 shell 完全不可用**。每次执行 `pwsh` 均返回：

```
Error: SetNamedSecurityInfoW failed (Win32 5): grantWrite(D:\Resource\Codebase\studyProject\Centli)
```

这是工作区 ACL 问题（连 `Write-Output`、以及把 workdir 切到 `C:\Users\ponyhch` 都失败），非命令本身错误。因此：

- **未运行 `flutter analyze`**
- **未运行 `flutter test`**
- **未运行任何构建**

全部结论来自读码。运行时推断一律标注为「⚠️ 推测」。

辅助说明：曾尝试加载 `diagnose-windows-sandbox-acl` 技能以自助修复，但技能包缺失（`SKILL.md` ENOENT）。

### 0.2 状态标记

| 标记 | 含义 |
|---|---|
| ✅ 已确认 | 已亲自复核代码，或经独立二次读取交叉验证 |
| 🔍 单次读码 | 由一次通读得出，未二次交叉验证 |
| ⚠️ 推测 | 运行时行为推断，未实机验证 |

### 0.3 已深读（结论较可靠）

- `lib/data/`：`db/centli_database.dart`(2292 行)、`db/tables/*`(9 张表)、`export/export_service.dart`、`export/import_service.dart`、`fx/fx_remote_service.dart`
- `lib/platform/`：`notifications/*`(全部)、`pending/pending_capture_intake.dart`、`home_widget/centli_home_widget_sync.dart`、`ocr/bill_ocr_service.dart`
- `android/app/src/main/kotlin/com/centli/centli/*.kt`（全部 6 个）+ `AndroidManifest.xml`
- `ios/Runner/AppDelegate.swift`
- `lib/app/`：`app.dart`、`router.dart`、`shell.dart`
- `lib/core/utils/*`、`lib/core/constants/currencies.dart`
- `lib/features/`：`home/home_page.dart`、`pending/pending_page.dart`、`ledger/bookkeeping_sheet.dart`、`ledger/ledger_detail_page.dart`、`ledger/llm_text_fill.dart`、`security/*`、`settings/me_page.dart`、`settings/security_page.dart`、`settings/permission_explain_page.dart`、`onboarding/splash_page.dart`、`stats/stats_page.dart`(头部)、`assets/assets_page.dart`(头部)
- `assets/noti_templates.json`、`test/*`(8 个文件)

### 0.4 未深读（清单可能不完整）

- **构建配置**：`android/app/build.gradle`、`ios/Runner/Info.plist`、`windows/`、`web/`
- **core/widgets**：`category_visuals.dart`、`centli_icon.dart`、`icon_picker_sheet.dart`、`date_range_control.dart`
- **features/settings**：`export_page.dart`、`import_page.dart`、`fx_rates_page.dart`、`recycle_bin_page.dart`、`ledgers_page.dart`、`categories_page.dart`、`budget_page.dart`、`auto_capture_page.dart` 的**页面内部逻辑**
- **features 其他**：`assets/account_detail_page.dart` 主体、`stats/stats_page.dart` 图表渲染段、`stats/category_drill_page.dart`、`ledger/search_page.dart` 筛选实现、`ledger/ai_text_fill.dart` 主体(仅读注释与结构)、`ledger/local_speech.dart` 主体

> 这些位置仍可能存在同级问题，尤其 `import_page.dart` / `export_page.dart` 的还原确认流程（与 §1 的 #1–#4 同属一条链路）。

---

## 1. 🔴 严重 —— 数据丢失 / 崩溃 / 静默失效

### #1 还原清空所有账本，而备份只含单个账本

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/db/centli_database.dart:2122-2129` ↔ `lib/data/export/export_service.dart:50` |
| 状态 | ✅ 已确认 |

`restoreFromImportBundle` 内的 8 条删除语句**全部无 WHERE 子句**：

```dart
await delete(transactions).go();
await delete(pendingCaptures).go();
await delete(merchantRules).go();
await delete(budgets).go();
await delete(categories).go();
await delete(accounts).go();
await delete(ledgers).go();
await delete(fxRates).go();
```

而导出侧 `buildBundle({required String ledgerId, ...})` 只取单个账本。

**后果**：多账本用户还原「个人」账本的备份时，**其他所有账本被永久抹除**。

**自相矛盾**：该函数文档注释自称 *"Wipe all ledger-scoped rows (+ FX + budgets)"*（`:2092`），实现却清的是全库。

**为何长期未被发现**：现有测试（`test/export_import_budgets_test.dart`）恰好在内存库上只用了一个账本。

**修复方向**：改为「仅删除当前 `ledger_id` 关联行」，或在整库替换前明确提示「将覆盖 N 个账本」并要求二次确认。

---

### #2 `merchant` 列无任何写入路径

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/db/centli_database.dart:687-724`（insert）、`:1039-1069`（update） |
| 状态 | ✅ 已确认 |

`insertManualTransaction` 与 `updateManualTransaction` **都没有 `merchant` 参数**。智能填单识别出的商家被降级塞进备注（`lib/features/ledger/bookkeeping_sheet.dart:943-951`）。

**后果**：以下三条功能链对**手工记账用户**（主路径）全部失效：

1. **商户规则学习** —— `merchant_rules` 依赖 `pending_captures.merchant`，手工记账永不产生规则，「改一次分类，下次预填」的承诺不成立
2. **搜索的商户匹配** —— `searchTransactions` 的 `t.merchant.lower().like(pattern)`（`:514`）对手工流水恒不命中
3. **导出可读性** —— JSON/Excel 的 `merchant` 列对手工流水恒为空

**附带问题**：编辑通知入账的流水也不会更新 `merchant`，商家与备注可能不一致。

---

### #3 清库前不校验完整性

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/export/import_service.dart:269-278` |
| 状态 | ✅ 已确认 |

`_asMapList` 对 `null` 返回空数组：

```dart
static List<Map<String, dynamic>> _asMapList(Object? v, String field) {
  if (v == null) return [];   // ← 缺失键 == 空数组
  ...
}
```

即：一个 `format` / `export_version` / `schema_version` / `ledger` 都合法、但**缺 `transactions` 键**的文件，会被判为「0 条流水」并通过校验，随后执行 §#1 的整库清空。

**后果**：结构合规但内容残缺的文件 → 静默清空本地全部数据。

---

### #4 Excel 还原清空本地汇率且不恢复

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/db/centli_database.dart:2129` + `lib/data/export/import_service.dart:567-570` |
| 状态 | ✅ 已确认 |

还原无差别执行 `await delete(fxRates).go()`，而 Excel 路径构造的 bundle 中 `'fx_rates': <Map<String, dynamic>>[]` 恒为空 → 汇率被删且不恢复。

**UI 提示不足**：`excelRestoreLimitations`（`:373-377`）只说「**不含** fx_rates / settings 工作表」，用户不会预期**已有的**汇率被删除。

---

### #5 iOS 分享 / 深链入口完全不可用

| 项 | 内容 |
|---|---|
| 位置 | `lib/platform/notifications/notification_listener_io.dart:152-154` + `ios/Runner/AppDelegate.swift:42-49` |
| 状态 | ✅ 已确认（已亲自读取 AppDelegate.swift 复核） |

`AppDelegate.swift` 在 `centli/notification_capture` 通道上投递 `pending_intake`：

```swift
pendingIntakeChannel = FlutterMethodChannel(
  name: "centli/notification_capture",
  binaryMessenger: messenger
)
```

但 Dart 侧 `bindPendingIntake` 在注册 handler **之前**就提前返回：

```dart
static Future<void> bindPendingIntake(
  void Function(Map<String, dynamic> payload) onIntake,
) async {
  onPendingIntake = onIntake;
  if (!supported) return;      // supported = !kIsWeb && Platform.isAndroid
  if (_bound) return;
  _bound = true;
  _channel.setMethodCallHandler((call) async { ... });
}
```

iOS 上 `Platform.isAndroid == false` → 永不注册 handler → 消息静默丢弃。`lib/` 内**只有这一处**注册该通道 handler。

**后果**：iOS 用户通过系统分享菜单导入账单、以及 `centli://pending` 快捷指令全部无效（这是 iOS 上唯一的手工导入通道）。

---

### #6 编辑已归档账户的流水必崩

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/ledger/bookkeeping_sheet.dart:86`、`:1259-1274`、`:1326-1342` |
| 状态 | ✅ 已确认 |

`_load` 只加载**在用**账户：

```dart
final accounts = await db.loadActiveAccounts(ledgerId);   // archived = 0
```

而两处 `DropdownButtonFormField` 的候选列表同样只来自 `_accounts`，`initialValue` 却直接取流水上的 `accountId`：

```dart
DropdownButtonFormField<String>(
  key: ValueKey('dd-$_fieldEpoch-${_accountId}_${_toAccountId}_$_type'),
  initialValue: _accountId,        // 可能是已归档账户
  items: [ for (final a in _accounts) ... ],   // 不含已归档账户
)
```

`initialValue` 不在 `items` 中 → Flutter 断言失败。

**复现路径**：归档账户 → 打开该账户的历史账单 → 点「编辑」。归档是常规操作，故此为必现崩溃。

**附带缺陷**：转账的「转出」与「转入」两个下拉框使用了**完全相同的 `ValueKey`**（`:1260` 与 `:1290`，以及 `:1328`），同一父节点下兄弟节点 key 重复，会导致元素复用/状态迁移行为不可预期。

---

### #7 跨币种弹窗取消时泄漏 TextEditingController

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/ledger/bookkeeping_sheet.dart:386`、`:397-398` |
| 状态 | ✅ 已确认 |

```dart
if (ok != true) return;      // ← 取消时提前返回
setState(() { ... });
toCtrl.dispose();            // ← 只有确认路径才释放
rateCtrl.dispose();
```

反复开关面板会累积未释放的控制器。

---

### #8 JPY 在原生路径差 100 倍

| 项 | 内容 |
|---|---|
| 位置 | `android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt:201`、`:244-248` |
| 状态 | ✅ 已确认 |

```kotlin
val minor = Math.round(major * 100.0).toInt()   // 一律 ×100
```

但 `lib/core/constants/currencies.dart:5` 定义 `'JPY': 0`（0 位小数）。而 `formatYuan` 又按整数日元打印：

```kotlin
return if (currency == "JPY") { "$symbol$minor" } else { ... }
```

**后果**：进程被杀时采集到的日元金额错误 100 倍，且同一份代码内部自相矛盾。

---

### #9 金额正则把日期当金额

| 项 | 内容 |
|---|---|
| 位置 | `lib/platform/notifications/notification_parse.dart:107-108`、`:236`；原生同缺陷 `NativeCaptureIngest.kt:185-187`、`:191` |
| 状态 | ✅ 已确认（逐字符分析正则 + 与测试用例交叉验证） |

```dart
const kAmountRegex =
    r'(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\s*)?(?:¥|￥|\$|€)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)';
```

币种码与货币符号**都是可选**的，且 `_extractAmount` 取 `firstMatch`。

**后果**：`"10月15日 向XX付款¥28.50"` → 捕获组得到 `10` → 记为 **¥10.00**。

这是中文支付通知最常见的文本形态（含日期前缀），因此实际影响面大于其他解析问题。

---

### #10 原生队列「先删后发、无 ack」

| 项 | 内容 |
|---|---|
| 位置 | `android/.../CentliNotificationListener.kt:131` + `MainActivity.kt:176-178`、`:290` |
| 状态 | ✅ 已确认 |

`drainQueue` 先清除持久化数据，再逐条投递：

```kotlin
fun drainQueue(context: Context): List<Map<String, Any?>> {
    val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
    p.edit().remove(KEY_QUEUE).apply()      // ← 先删
    ...
}
```

而 `MainActivity.configureFlutterEngine` 的 `mainHandler.post { flushQueuedCaptures() }` 执行时机**早于** `app.dart` 中 post-frame 的 `_ensureBridge()`（Dart handler 尚未绑定）→ 消息进入内存队列后丢失。

`PendingIntakeIntents.drain`（`:119-122`）同样先删后发。

**附带**：`emitNotificationCapture` 的 `catch`（`MainActivity.kt:290`）只能捕获同步异常，Dart 侧异步失败不会回落到 `enqueue` —— 与代码注释所述行为不符。

---

## 2. 🟠 高 —— 功能受损 / 隐私 / 合规 / 安全

### #11 去重键两侧不一致 → 同一通知双写双推

| 项 | 内容 |
|---|---|
| 位置 | `notification_parse.dart:158-163` ↔ `NativeCaptureIngest.kt:225-234` |
| 状态 | ✅ 已确认 |

微信通知 `title = "微信支付"` 时：

- **Dart 侧**：`merchantFromTitle = true` → `merchantRegex` 不匹配 → `merchant = "微信支付"`
- **原生侧**：`guessMerchant` 把 title 里 `-?微信支付$` 剪空 → 回落正则也匹配不到 → `merchant = null`

去重键 `pkg|merchant|amountMinor|bucket` 因此不同，`existsDedupe`（原生）与 `existsDedupeKey`（Dart）都查不到对方 → **写入两条 pending + 推送两次系统通知**。

---

### #12 权限页隐式开启采集

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/settings/permission_explain_page.dart:73-77` |
| 状态 | ✅ 已确认（已亲自复核） |

```dart
if (granted) {
  // Keep preference in sync once the user has granted access.
  final db = ref.read(databaseProvider);
  await db.setSetting('auto_capture_enabled', 'true');
  await NotificationCaptureStub.setAutoCaptureEnabled(true);
  await NotificationCaptureStub.ensureListenerRebind();
}
```

只要 `_refresh` 检测到系统通知使用权已开启，就自动把采集开关置为 `true`。用户**从未在应用内点击过任何开关**。

**问题**：该代码在权限页初始化时也会执行（不仅是「从系统设置返回」路径），且注释所称 "keep preference in sync" 与「开启新采集」是两件不同的事 —— 合规与用户预期上应只做状态同步，不应代为开启。

---

### #13 原生默认值与 Dart 相反

| 项 | 内容 |
|---|---|
| 位置 | `CentliNotificationListener.kt:107` + `NativeCaptureIngest.kt:51-55` ↔ `notification_ingest_bridge.dart:38-39` |
| 状态 | ✅ 已确认 |

- **原生** `SharedPreferences` 默认 `true`：`prefs(context).getBoolean(KEY_AUTO, true)`
- **原生直写** 在 DB 设置缺失时也放行：`if (enabled != null && enabled != "true") skip`（即 `null` → 继续写入）
- **Dart** 严格要求 `== 'true'`

**后果**：DB 设置缺失/未初始化时，原生会持续采集而 Dart 侧认为已关闭，出现「Dart 以为关了、原生还在收」的不一致状态。

---

### #14 PIN 弱哈希 + 无失败限制

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/security/app_lock_service.dart:101-104`；`app_lock_page.dart:71-83` |
| 状态 | ✅ 已确认 |

```dart
static String _hashPin(String pin, String salt) {
  final bytes = utf8.encode('$salt:$pin');
  return sha256.convert(bytes).toString();      // 单轮 SHA-256
}
```

- 使用**单轮 SHA-256**，非 PBKDF2 / Argon2 / bcrypt，无迭代数
- 6 位数字空间仅 10⁶，本地攻击者可离线穷举
- 无失败计数、无锁定、无指数退避（`app_lock_page.dart:66-84`、`pin_pad.dart:243-261`）
- PIN 格式正则硬编码 `6` 而非使用常量 `kAppLockPinLength`（`:92-93`）

**背景**：对本地优先应用而言，应用锁是唯一的访问边界，值得加固。

---

### #15 隐私文案与实现冲突

| 项 | 内容 |
|---|---|
| 位置 | `assets/legal/privacy_zh.txt:26,38-41` ↔ `local_speech.dart:207`、`llm_text_fill.dart:134-157` |
| 状态 | ✅ 已确认 |

**语音**：文案称「于设备本地将语音转为文字…可优先离线模型，音频与转写结果不上传」，实现却是**网络优先**：

```dart
onDevice: false,   // 先试网络
```

**LLM**：`llm_text_fill.dart` 会把用户的记账话术 + 分类名列表（截断 80 条）+ 账户名列表（截断 40 条）发往用户自填的第三方端点：

```dart
final uri = Uri.parse('${config.normalizedBaseUrl}/chat/completions');
```

隐私政策仅在第七节谈论 Flutter / 开源依赖，**完全没有披露**这一外发行为。且 `baseUrl` 不强制 https，用户填 `http://` 时 API Key 明文外发。

---

### #16 深链可注入

| 项 | 内容 |
|---|---|
| 位置 | `android/app/src/main/AndroidManifest.xml:49-55` + `pending_capture_intake.dart:286-357` |
| 状态 | ✅ 已确认 |

`centli://pending` 注册为 `exported="true"` + `BROWSABLE`，而 `ingestUri` 不校验来源即直接入库：

```dart
if (uri.scheme != 'centli') return ...;
...
return ingestText(db, text: textParam, sourceKind: 'url', navigate: navigate);
```

**后果**：任何应用或网页可用 `centli://pending?text=向X转账¥100` 向账本注入伪造待确认条目，仅靠用户手动确认兜底。

---

### #17 `hide_amount` 不覆盖通知与持久化队列

| 项 | 内容 |
|---|---|
| 位置 | `PendingConfirmNotifier.kt:56-81`；`CentliNotificationListener.kt:113-126` |
| 状态 | ✅ 已确认 |

- `hide_amount` **只作用于桌面小组件**（`centli_home_widget_sync.dart:39-40`）
- 待确认推送仍明文显示金额（原生 `NativeCaptureIngest.kt:94-98`、Dart `notification_ingest_bridge.dart:94-99`）
- 推送未设 `VISIBILITY_SECRET` / `localOnly` → 锁屏可见
- 通知原文 `raw_text` 明文入库，且完整原文以明文存入 `SharedPreferences` 队列（上限 50 条），无脱敏/加密

---

### #18 原生直写不填建议字段（体验断档）

| 项 | 内容 |
|---|---|
| 位置 | `NativeCaptureIngest.kt:86-91` ↔ `centli_database.dart:1344-1355` |
| 状态 | ✅ 已确认 |

Dart 侧 `ingestParsedNotification` 会查默认账户映射与商户规则，填充 `suggested_account_id` / `suggested_category_id`；原生直写时二者硬编码为 `null`：

```kotlin
null, null, "pending", dedupe,   // suggested_category_id, suggested_account_id
```

**后果**：进程被杀场景（正是这条路径存在的意义）采集的条目缺少预填，用户在待确认页需从零选择账户与分类。

> 注：原生路径**有** `auto_capture_enabled` 检查（`NativeCaptureIngest.kt:51-55`），此前报告中关于「关闭后仍写库」的表述已修正 —— 真正缺陷是建议字段缺失 + 默认值不一致（见 #13）。

---

### #19 原生过滤硬编码，不随模板热更新

| 项 | 内容 |
|---|---|
| 位置 | `CentliNotificationListener.kt:98-101`、`:165-168` |
| 状态 | ✅ 已确认 |

```kotlin
val WATCHED_PACKAGES = setOf("com.eg.android.AlipayGphone", "com.tencent.mm")
private val EXCLUDE_COMMON = Pattern.compile("验证码|登录|朋友圈|...")
```

而 Dart 侧支持 `documents > assets > builtin` 三级模板热更新（`noti_template_store.dart:33-68`）。

**后果**：模板新增支持的应用包，在「进程被杀」场景完全无效；且原生 `EXCLUDE_COMMON` 比 Dart 模板更严（额外含「收款到账提醒/服务通知/余额宝收益」，且对微信一并生效），两侧规则会漂移。

---

### #20 手工记账无法记收入（待确认页）

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/pending/pending_page.dart:454-457` |
| 状态 | ✅ 已确认 |

```dart
future: ref.read(databaseProvider).loadCategories(widget.ledgerId, 'out'),
```

`_PendingCard` 写死只加载 `out` 分类，且无「支出/收入」类型切换 → 从待确认流入账收入类账单时只能选支出分类（或无法选到正确分类）。

---

### #21 文档承诺的 8 类索引全部未创建

| 项 | 内容 |
|---|---|
| 位置 | `docs/Centli_schema.md:52,68,96,124` ↔ 实现 |
| 状态 | ✅ 已确认 |

全仓库无任何 `@TableIndex`。文档声明的以下索引**均不存在**：

| 表 | 文档声明的索引 |
|---|---|
| accounts | `(ledger_id, archived)` |
| categories | `(ledger_id, kind, archived)`、`(parent_id)` |
| transactions | `(ledger_id, happen_at)`、`(account_id, happen_at)`、`(category_id)`、`(transfer_group_id)` |
| pending_captures | `(status, created_at)` |

其中 `(ledger_id, happen_at)` 是首页与统计页的主查询路径。当前数据量下无感，数据增长后会退化。

---

### #22 外键未启用

| 项 | 内容 |
|---|---|
| 位置 | `lib/data/db/centli_database.dart:2286-2292` |
| 状态 | ✅ 已确认 |

```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'centli.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

无 `beforeOpen` 回调、无 `PRAGMA foreign_keys = ON` → Drift 的 `.references()` 声明在**运行时不生效**（Drift 仅在 `alterTable` 内部临时开启）。

**双重后果**：
1. 脏引用不会被拦截（配合 #32 产生孤儿行）
2. 正因如此，**#1 的整库清空不会因外键报错而中止** —— 错误被静默吞掉

---

### #23 调试按钮进生产 UI

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/pending/pending_page.dart:96-119` |
| 状态 | ✅ 已确认 |

「添加示例通知」按钮（`Icons.science_outlined`）调用 `seedSamplePendingCaptures` 写入 5 条示例数据，**无 `kDebugMode` 保护**。真实用户误点即污染真实账本。

---

### #24 导出 schema_version 与 DB 不一致

| 项 | 内容 |
|---|---|
| 位置 | `export_service.dart:75`；`import_service.dart:127` |
| 状态 | ✅ 已确认 |

- 导出硬编码 `'schema_version': 2`，而 DB `schemaVersion => 3`
- 导入校验 `if (schemaVersion < 1 || schemaVersion > 2) throw`

**后果**：若将来把导出改为 `3`，应用会**拒绝自己的导出文件**。

---

### #25 Excel 往返丢字段

| 项 | 内容 |
|---|---|
| 位置 | `import_service.dart:487`；`export_service.dart:318-338, 265-274, 292-300` |
| 状态 | ✅ 已确认 |

| 字段 | 情况 |
|---|---|
| `transactions.include_in_budget` | 导入时硬编码为 `1` |
| `transactions.transfer_group_id` | 不在 sheet 中 |
| `transactions.pending_id` | 不在 sheet 中 |
| `accounts.icon` | 不在 sheet 中（v3 新增列，往返丢失） |
| `categories.icon` | 不在 sheet 中 |

---

### #26 Excel 按列序号解析、无表头校验

| 项 | 内容 |
|---|---|
| 位置 | `import_service.dart:424-553`、`:597-603` |
| 状态 | ✅ 已确认 |

所有取值均为硬编码列号（`_cellStr(row, 3)`、`_cellInt(row, 4)` …），无表头校验。且：

```dart
static int _cellInt(List<Data?> row, int i, {int fallback = 0}) {
  ...
  return int.tryParse('$raw'.trim()) ?? fallback;   // 解析失败 → 0
}
```

**后果**：用户手工编辑过 Excel（插列、改表头）后导入，或单元格为文本格式时，会**静默写入 0 元流水 / 0 元预算**，而非报错。

---

## 3. 🟡 中 —— 正确性 / 一致性 / 代码质量

### #27 全链路浮点金额

| 项 | 内容 |
|---|---|
| 位置 | `lib/core/utils/money.dart:6`；`lib/core/utils/fx.dart:116` |
| 状态 | ✅ 已确认 |

```dart
// money.dart
return (major * factor).round();

// fx.dart
return (major * rate * toFactor).round();
```

未使用 `Decimal` —— 与项目自己的文档建议相悖（`docs/Centli_schema.md:279` 建议 `Decimal`）。

**示例**：`8.615 * 100` 在 IEEE 754 下为 `861.4999...` → `round()` 得 `861`（期望 `862`）。单次误差极小，但汇率换算会二次放大。

---

### #28 FX 无交叉汇率

| 项 | 内容 |
|---|---|
| 位置 | `lib/core/utils/fx.dart:59-70` |
| 状态 | ✅ 已确认 |

`rate()` 只查 `(from, to)` 与 `(to, from)` 两个方向，**不经过基准货币两跳换算**。

**后果**：只缓存了 `USD→CNY` 与 `EUR→CNY` 时，`USD→EUR` 返回 `null` → 该笔流水落入 `unconverted` 不计入统计。

远端服务 `refreshToBase` 只写入 `foreign → base` 方向的报价（`fx_remote_service.dart:101-120`），因此**只要本位币不是 CNY，任何非本位币之间的换算都会失败**。

---

### #29 FxBook 注释与实现不一致

| 项 | 内容 |
|---|---|
| 位置 | `fx.dart:20-24` ↔ `:65-69` |
| 状态 | ✅ 已确认 |

注释声称查找顺序为：

```
1. identity when currencies match
2. exact day forward quote
3. exact day inverse (1/rate)
4. nearest prior day forward, then inverse
```

实现实为：

```dart
final forward = _rateOnOrBefore(fromCcy, toCcy, onDay);   // 任意历史日的正向
if (forward != null) return forward;
final inverse = _rateOnOrBefore(toCcy, fromCcy, onDay);   // 才轮到反向
```

即「**任意历史正向**」优先于「当日反向」，与注释描述不符。这会导致有当日反向报价时仍使用陈旧的正向报价。

---

### #30 FX 日期语义混用 + 空结果也写门禁

| 项 | 内容 |
|---|---|
| 位置 | `fx_remote_service.dart:95`、`:122`、`:144-146` |
| 状态 | ✅ 已确认 |

- 报价的 `day` 取自**供应商的 `time_last_update_unix`**（`:85-95`）
- 每日一次的门禁 `lastDayKey` 写的是**本地今天**（`:122`、`:144-146`）

两者语义不同。此外，即使 `upserted == 0`（一条都没成功）也写入门禁 → **当天不再重试**。

---

### #31 http.Client 从不关闭

| 项 | 内容 |
|---|---|
| 位置 | `fx_remote_service.dart:38`、`:156` |
| 状态 | ✅ 已确认 |

`FxRemoteService({http.Client? client}) : _client = client ?? http.Client()` 创建后无 `close()`，`scheduleFxAutoRefresh` 每次调用都新建实例。

---

### #32 还原不重写子行 ledgerId

| 项 | 内容 |
|---|---|
| 位置 | `centli_database.dart:2107-2117` |
| 状态 | ✅ 已确认 |

所有子行直接 `X.fromJson(map)` 后以 `toCompanion(true)` 插入，**不做 `ledgerId` 归一化**。若备份中某子行的 `ledgerId` 与顶层 `ledger.id` 不一致（手工编辑过的备份、或拼接来源），会写入孤儿行。

---

### #33 还原主键冲突的错误信息不可读

| 项 | 内容 |
|---|---|
| 位置 | `centli_database.dart:2131-2152` |
| 状态 | ✅ 已确认 |

`toCompanion(true)` 直插，主键/唯一键冲突在事务中途抛出 `SqliteException`，整体回滚（行为上正确），但异常原文对用户不可读，UI 只会原样透出。

---

### #34 app 锁双数据源

| 项 | 内容 |
|---|---|
| 位置 | `lib/app/app.dart:80` ↔ `lib/features/security/app_lock_controller.dart:10` |
| 状态 | ✅ 已确认 |

`_relockIfNeeded` 直接读 setting：`await ref.read(databaseProvider).getSetting('app_lock')`，与 `appLockEnabledProvider` 并行存在两套状态来源。

---

### #35 转账下拉框 ValueKey 重复

| 项 | 内容 |
|---|---|
| 位置 | `bookkeeping_sheet.dart:1260`、`:1290`、`:1328` |
| 状态 | ✅ 已确认 |

三处均为同一表达式 `ValueKey('dd-$_fieldEpoch-${_accountId}_${_toAccountId}_$_type')`。其中 `:1260`（转出）与 `:1290`（转入）是同一父节点下的兄弟节点 → **key 重复**，Flutter 的元素复用与状态迁移行为不可预期。

---

### #36 `_reloadCategories` 重置已选分类

| 项 | 内容 |
|---|---|
| 位置 | `bookkeeping_sheet.dart:144` |
| 状态 | 🔍 单次读码 |

切换类型（支出↔收入）时重新加载分类，会把用户已选分类重置为第一个，可能丢失用户选择。

---

### #37 stats 预算区块口径不一致

| 项 | 内容 |
|---|---|
| 位置 | `lib/features/stats/stats_page.dart:440-444` |
| 状态 | ✅ 已确认（已亲自复核） |

```dart
final String ym;
if (range.kind == DateRangeKind.month) {
  ym = budgetYearMonth(range.startLocal);
} else {
  ym = budgetYearMonth();      // 非「按月」区间 → 当前月
}
```

用户把区间切成「近 30 天」或自定义区间时，预算区块仍显示**当前自然月**的进度，与上方图表口径不一致，且 UI 上无提示。

---

### #38 LLM 降级零提示

| 项 | 内容 |
|---|---|
| 位置 | `llm_text_fill.dart:243-249` |
| 状态 | ✅ 已确认 |

`on TimeoutException → null`，`catch (_) → null`，所有失败静默返回 `null`，调用处无提示。用户无法区分「本地规则解析的结果」与「LLM 增强后的结果」。

另：`response_format: {'type': 'json_object'}`（`:142`）不被部分 OpenAI 兼容端点支持，这些端点会持续报错 → 永远静默回退到本地解析。

---

### #39 分类/账户名单静默截断

| 项 | 内容 |
|---|---|
| 位置 | `llm_text_fill.dart:116-117` |
| 状态 | ✅ 已确认 |

```dart
final catList = names.take(80).join('、');
final accList = accountNames.take(40).join('、');
```

分类/账户超过上限时，模型看不到全部候选，`categoryHint` 可能落到不存在的名称上。

---

### #40 行内 N+1 查询

| 项 | 内容 |
|---|---|
| 位置 | `lib/core/widgets/txn_list_tile.dart:65,81,95,184,192`；`home_page.dart:480-481` |
| 状态 | ✅ 已确认 |

- `TxnListTile` 每行发起 **3 个 `FutureBuilder`**
- `_catMeta`（`:184`）与 `_categoryTitle`（`:192`）**重复查询同一分类**
- 首页待确认 carousel 每次 build 新建 Future 查分类

**后果**：账单列表是高频界面，千条量级下滚动会明显卡顿。

---

### #41 硬编码配色 / 深色主题缺项

| 项 | 内容 |
|---|---|
| 位置 | `theme.dart:14,39,56`；`txn_list_tile.dart:14-15,56`；`stats_page.dart:638-650`；`centli_icon.dart:45`；`category_visuals.dart:28-46` |
| 状态 | 🔍 单次读码 |

配色分散在 5 个文件中硬编码，未走 `ColorScheme`；且 `CentliTheme.dark()` 缺少 `inputDecorationTheme`（`theme.dart:68-109`）→ 深色下输入框样式与浅色不一致。

---

### #42 默认区间 30 天硬编码三处

| 项 | 内容 |
|---|---|
| 位置 | `home_page.dart:20`、`stats_page.dart:14`、`date_range_control.dart:96` |
| 状态 | ✅ 已确认 |

`DateRangeWindow.lastDays(days: 30)` 的默认值散落三处，无统一常量。

---

### #43 版本号不一致（两处）

| 项 | 内容 |
|---|---|
| 位置 | `me_page.dart:169`、`export_service.dart:47` |
| 状态 | ✅ 已确认（已亲自复核） |

| 位置 | 值 |
|---|---|
| `pubspec.yaml:6` | `1.0.1+2` ✅ 权威来源 |
| `about_page.dart:9` | `1.0.1+2` ✅ 一致 |
| `me_page.dart:169` | `1.0.0+1` ❌ 落后 |
| `export_service.dart:47`（写进备份） | `1.0.0+1` ❌ 落后 |

> 修正说明：早前口头报告中曾称 `about_page.dart` 落后，实际它是正确的；真正落后的是另外两处。

---

### #44 原生主线程写库 + 竞争风险

| 项 | 内容 |
|---|---|
| 位置 | `NativeCaptureIngest.kt:41,46-92`；`centli_database.dart:2286-2292`；`notification_ingest_bridge.dart:71-74` |
| 状态 | ⚠️ 推测 |

- `onNotificationPosted` 在主线程同步 `openDatabase` 并写入，无事务 → 高频通知下有 ANR 风险
- Drift 侧 `createInBackground` 未显式设置 `busy_timeout`，与原生写竞争时可能 `SQLITE_BUSY`
- 而 Dart 侧异常被吞：`catch (e) { return null; }`（注释称「原生可能已插入同一 dedupe_key」）→ 真实的 SQLITE_BUSY 也会被当作正常去重而**静默丢件**

---

### #45 商店合规风险

| 项 | 内容 |
|---|---|
| 位置 | `AndroidManifest.xml:5,8`；`MainActivity.kt:245-256`；`PendingIntakeIntents.kt:83-99` |
| 状态 | ⚠️ 推测 |

- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 属 Google Play **受限能力**，需提交用途说明，否则可能被拒
- `READ_MEDIA_IMAGES` 未加 `android:maxSdkVersion`
- 分享图片缓存 `cacheDir/shared_intake` 无清理逻辑，会持续增长

---

### #46 OCR 桌面未守卫

| 项 | 内容 |
|---|---|
| 位置 | `lib/platform/ocr/bill_ocr_service.dart:18` |
| 状态 | ⚠️ 推测 |

仅拦截 `kIsWeb`，Windows/Linux 上会落到 `google_mlkit_text_recognition` 的 `MissingPluginException`，而非友好的 `UnsupportedError`（鉴于项目有 Windows 构建目标，这条有实际意义）。

---

## 4. 🟢 低 —— 卫生 / 可维护性

### #47 备份文件入库（7 个）

| 项 | 内容 |
|---|---|
| 状态 | ✅ 已确认 |

| 路径 |
|---|
| `lib/features/ledger/ai_text_fill.dart.bak_smartfill` |
| `lib/features/ledger/bookkeeping_sheet.dart.bak_smartfill` |
| `lib/features/ledger/bookkeeping_sheet.dart.bak_voiceux` |
| `lib/features/ledger/local_speech.dart.bak_voiceux` |
| `lib/app/router.dart.bak_smartfill` |
| `lib/features/settings/me_page.dart.bak_smartfill` |
| `_patch_tmp/txn_list_tile.bak.dart` |
| `test/ai_text_fill_test.dart.bak_smartfill` |

**内容考证**（供清理时判断是否可安全删除）：

- `.bak_smartfill` 组 = **引入大模型之前**的快照。全部 `.bak_smartfill` 中 grep 不到 `smart-fill|SmartFill|OpenAI|大模型`；`router.dart.bak_smartfill` 无 `/me/smart-fill` 路由（live 有 `router.dart:157-161`）；`me_page.dart.bak_smartfill` 在「自动记账」与「桌面小组件」之间无智能填单项（live 有 `me_page.dart:93-99`）
- `ai_text_fill.dart`：403 行 → 779 行。新增 `CategoryRef`/`categories` 参数、置信度体系（`categoryConfidence`、阈值 0.72）、`mapCategoryHintToLocal`、短词表、span 式备注抽取、品牌商家表；删除旧版 `note = input`
- `local_speech.dart`：166 行 → 258 行。新增 `friendlyError` 中文映射、状态/音量/错误回调、`finalTimeout: 3s`；`ListenMode.confirmation→dictation`、`cancelOnError: true→false`、新增 `pauseFor`/`listenFor`
- `bookkeeping_sheet.dart`：bak_smartfill 1224 / bak_voiceux 1284 → live 1546 行。两个备份都只有 `_speechListening` 布尔，没有 live 的 `_speechPhase`/`_speechLevel` 状态机与 `_SpeechStatusBanner`（`live:1467-1546`）；**`bak_voiceux` 是两者之间的中间态**

---

### #48 重复 UI 逻辑与无效计算

| 项 | 内容 |
|---|---|
| 位置 | `stats_page.dart:163-218`、`:351-352`、`:238-239` |
| 状态 | ✅ 已确认 |

- stats 手写两张汇总卡，而 `home_page.dart:223` 已有 `_SummaryCard`（私有，无法复用）
- `stats_page.dart:351-352` 在循环内反复调用 `_categoryColors(...)[i]` → O(n²) 颜色分配
- `:238-239` 连续两个相同的 `SizedBox(height: 16)`

---

### #49 死代码 / 未使用成员

| 项 | 内容 |
|---|---|
| 状态 | ✅ 已确认 |

| 位置 | 说明 |
|---|---|
| `account_detail_page.dart:23-27` | `_accountRangeProvider` 的 family 参数 `accountId` 完全未使用 |
| `notification_listener_io.dart:12`、`stub_impl.dart:8` | `templateVersion = 3` 从未被引用 |
| `pending_capture_intake.dart:360-362` | `previewUri` 疑似无调用方 |
| `search_page.dart:88` | `setState(() {})` 空回调，仅为刷新清除按钮 |

---

### #50 模板版本常量三处手工同步

| 项 | 内容 |
|---|---|
| 位置 | `notification_listener_io.dart:12`、`stub_impl.dart:8`、`noti_template_store.dart:221` + `assets/noti_templates.json:2` |
| 状态 | ✅ 已确认 |

四处（含 assets JSON）都写着版本号，全靠人工保持一致，无编译期保障。

---

### #51 通道 handler 两份重复实现

| 项 | 内容 |
|---|---|
| 位置 | `notification_listener_io.dart:108-143`（`bind`）与 `:155-189`（`bindPendingIntake`） |
| 状态 | ✅ 已确认 |

两个方法各自 `setMethodCallHandler` 一份几乎相同的实现，靠 `_bound` 标志 + 静态字段「先绑者生效」侥幸工作 —— 这也是 #5 的根因之一。

---

### #52 其他小项

| 项 | 位置 | 状态 |
|---|---|---|
| 同秒同账本导出会覆盖同名文件 | `export_service.dart:110-122, 161-165`（时间戳精确到秒） | ✅ |
| `lastDays` 用 `Duration` 减天数，DST 时区会偏移 1 小时 | `date_range.dart:36, 89-90, 112-113`（Asia/Shanghai 无 DST，故潜在） | 🔍 |
| `FxBook` 币种比较大小写敏感 | `fx.dart:64`（`fromCcy == toCcy` 直接字符串比较） | ✅ |
| `_cellRaw` 依赖 excel 包 `toString()` 返回纯文本 | `import_service.dart:605-613`（当前正确但脆弱） | 🔍 |
| `parseNotification` 每次调用重建全部 `RegExp` | `notification_parse.dart:143-165` | 🔍 |
| `txn_grouped_list` 每次 build 重新分组 | `txn_grouped_list.dart:71` | 🔍 |
| `pending_page.dart:75/81/96` 缩进错乱 | — | ✅ |

---

## 5. 文档与实现漂移

`docs/` 是项目的重要资产（8 份中文设计文档，质量较高），但已明显滞后于代码，会误导后续开发。

| 项 | 文档 | 实现 | 位置 |
|---|---|---|---|
| `accounts.icon` | 未记录，changelog 只到 v2 | DB `schemaVersion = 3`，v3 新增该列 | `Centli_schema.md:39-50, 255-256` ↔ `centli_database.dart:43, 55-58` |
| 索引 | 声明 8 类索引 | 全部未创建 | `Centli_schema.md:52, 68, 96, 124` |
| `categories.parent_id` | FK → categories | 无 FK | `Centli_schema.md:61` ↔ `tables/categories.dart` |
| Excel 导入 | 「导入仍仅支持 JSON」 | 已支持 Excel | `Centli_schema.md:290` ↔ `import_service.dart:349` |
| `daos/`、`converters/money_converter.dart` | 列为目录结构 | 不存在（DB 逻辑全堆在单文件 2292 行） | `Centli_schema.md:14-16` |
| 金额精度 | 建议 `Decimal` | 全链路 `double` | `Centli_schema.md:279` ↔ `money.dart:6` |
| schemaVersion | 「首版 schemaVersion = 1」 | 现为 3 | `Centli_schema.md:5` |

**收益**：纯文档修改，成本极低，可与代码修复同步进行。

---

## 6. 测试缺口

现有 8 个测试文件**全部是单元测试**：

| 文件 | 覆盖 |
|---|---|
| `test/widget_test.dart` | money（CNY/JPY/隐藏金额）、`DateRangeWindow` |
| `test/fx_test.dart` | FX 换算 |
| `test/budget_test.dart` | `budgetYearMonth`、预算进度模型（纯模型，不碰 DB） |
| `test/export_import_budgets_test.dart` | budgets 的 JSON 解析与还原后重插 |
| `test/excel_import_test.dart` | Excel 尽力而为解析 |
| `test/notification_parse_test.dart` | 通知解析（含中文聊天/验证码负例） |
| `test/ai_text_fill_test.dart` | AI 填单规则 |
| `test/home_widget_route_test.dart` | 小组件 URI → 路由映射 |

**缺口**：

- **无 Widget 测试、无集成测试**
- **最危险的还原路径只有内存库级验证**，且恰好只用了**单个账本** —— 这正是 #1 能长期存在的原因
- 无「残缺备份应被拒绝」的负例测试（#3）
- 无 Excel 清理汇率后果的测试（#4）
- 无商户列写入的测试（#2）

**高性价比补充**：为 #1 / #2 / #3 / #4 添加针对性测试，成本小，可有效防止回归。

---

## 7. 修复收益总表

### 7.1 严重组（P0/P1）

| # | 问题 | 修复收益 | 成本 |
|---|---|---|---|
| 1 | 还原清空所有账本 | **消除唯一的永久性数据丢失路径**。多账本用户当前随时可能在正常使用「导入」时失去全部其他账本 | 小，约 20 行 |
| 2 | `merchant` 无写入路径 | **一次性恢复三条功能链**：商户规则学习、搜索商户匹配、导出可读性。手工记账是主路径，等于「学一次下次预填」目前只对通知路径成立 | 中 |
| 3 | 清库前不校验完整性 | 把「静默清空」变成「拒绝导入」，为 #1/#4 外层再加一道门槛 | 小，约 15 行 |
| 4 | Excel 清空汇率 | 消除第二次数据丢失；同时补齐 UI 文案预期 | 小 |
| 5 | iOS handler 被短路 | 恢复 iOS 唯一的分享/快捷指令导入入口 | 小 |
| 6 | 编辑归档账户流水必崩 | 消除一个必现崩溃路径（归档是常规操作） | 小 |
| 7 | 控制器泄漏 | 消除面板重复开关的内存增长 | 极小 |
| 8 | JPY 差 100 倍 | 修正金额错误 | 小 |
| 9 | 正则误取日期 | 修正最常见的通知文本形态下的金额错误 | 小 |
| 10 | 队列先删后发 | 消除进程重启后的静默丢件 | 小～中 |

### 7.2 高组（P1/P2）

| # | 问题 | 修复收益 | 成本 |
|---|---|---|---|
| 11 | 去重键不一致 | 消除用户可见的重复账单与重复推送（难复现的迷惑性 bug） | 小 |
| 12 | 权限页隐式开启 | 合规与信任：采集开关必须由用户显式点击 | 小 |
| 13 | 原生默认值相反 | 消除「Dart 以为关了、原生还在收」 | 小 |
| 14 | PIN 弱哈希 | 显著提升本地攻击者的破解成本 —— 本地优先应用唯一的安全边界 | 小 |
| 15 | 隐私文案冲突 | 合规必需项（商店隐私审核会查） | 小～中 |
| 16 | 深链可注入 | 防止外部应用伪造账单注入数据库 | 小 |
| 17 | 锁屏明文金额 | 锁屏隐私（记账是敏感数据） | 小 |
| 18 | 原生不填建议字段 | 让「进程被杀也能记账」这条核心卖点在功能上完整 | 小 |
| 19 | 原生过滤硬编码 | 让模板热更新设计真正生效 | 中 |
| 20 | 待确认只加载 out 分类 | 恢复收入类待确认入账能力 | 小 |
| 21 | 索引缺失 | 数据量增长后的查询性能保障 | 小 |
| 22 | 外键未启用 | 数据完整性最后一道防线（配合 #1/#3） | 小 |
| 23 | 生产调试按钮 | 防止真实账本被测试数据污染 | 极小 |
| 24 | schema_version 不一致 | 避免未来「自己的备份自己导不进」 | 极小 |
| 25 | Excel 丢字段 | 明确 Excel 定位（人类可读 vs 备份）并补齐关键字段 | 中 |
| 26 | Excel 无表头校验 | 防止静默写入 0 值脏数据 | 小 |

### 7.3 中组（P2/P3）

| # | 问题 | 修复收益 | 成本 |
|---|---|---|---|
| 27 | 浮点金额 | 消除长期累积的分位误差 —— 记账应用金额准确性是底线 | 中 |
| 28 | 无交叉汇率 | 让「多币种」在**任意币种对**下成立（本位币非 CNY 时目前普遍失效） | 中 |
| 29–31 | 注释/行为不一致、日期语义、连接泄漏 | 修正不一致 + 避免汇率陈旧 | 小 |
| 32 | 孤儿行 | 消除脏引用（配合 #22） | 小 |
| 33 | 错误信息不可读 | 提升导入失败时的可诊断性 | 小 |
| 34–37 | 双数据源、重复 key、分类重置、预算口径 | 消除状态不同步与 UI 竞态 | 小 |
| 38–39 | LLM 零提示、名单截断 | 让降级行为可观测、候选集完整 | 小 |
| 40 | N+1 查询 | 列表滚动性能（千条量级明显卡顿） | 中 |
| 41–43 | 主题硬编码、30 天魔法数、版本号 | 一致性与可维护性 | 小 |
| 44 | 主线程写库 / SQLITE_BUSY 静默丢件 | 消除 ANR 与静默丢件（双写架构下最实际的风险） | 中 |
| 45 | 商店合规 | 上架通过率 | 小～中 |
| 46 | OCR 桌面未守卫 | Windows 目标下的友好降级 | 极小 |

### 7.4 低组（P4，清理批次）

| 项 | 修复收益 | 成本 |
|---|---|---|
| #47 备份文件 | 仓库干净，避免「改了 live 忘了 bak」的困惑 | 1 分钟 |
| #48–#52 | 每项都小，合计显著降低后续维护成本 | 小 |
| §5 文档漂移 | 项目最大资产恢复可信 | 小 |
| §6 补测试 | 防止 #1–#4 回归 | 小 |

---

## 8. 建议执行顺序

| 批次 | 内容 | 理由 |
|---|---|---|
| **P0**（一天内） | #1 #3 #4 #2 | 前三条是数据丢失，第四条恢复三条功能链；改动都小 |
| **P1**（两三天） | #6 #7 #8 #9 #11 #12 #13 #20 #23 #24 | 崩溃、金额错误、重复账单、隐式开启采集、生产调试入口 |
| **P2**（一周内） | #5 #10 #14 #15 #17 #21 #22 #26 | 平台入口、队列可靠性、安全与隐私合规、索引与外键 |
| **P3**（按需） | #16 #18 #19 #25 #27 #28 #40 #44 | 侵入性较大或需更多验证 |
| **P4**（清理） | #47–#52 + §5 文档同步 + §6 补测试 | 低风险高性价比，可穿插进行 |

---

## 9. 审计局限与后续建议

1. **未运行 `flutter analyze`**（shell 被 ACL 阻塞）。它可以一次性暴露大量静态问题（未使用变量、类型问题、lint 违规），效率远高于逐文件读码。**建议优先恢复 shell 后补跑一次**。

2. **未运行 `flutter test`**，故无法确认现有 8 个测试是否全部通过。

3. **清单仍不完整**：§0.4 列出的未深读文件中仍可能存在同级问题，尤其：
   - `features/settings/import_page.dart` / `export_page.dart` 的**还原确认流程**（与 #1–#4 同属一条链路，可能有二次确认缺失或提示不足）
   - `features/assets/account_detail_page.dart` 的余额校正逻辑
   - `android/app/build.gradle` 的签名与混淆（`minifyEnabled` 会影响原生 SQLite 直写路径的反射可用性，若使用了 Gson/反射需保留规则）

4. **未实机验证**：所有平台相关结论（#44 #45 #46 及通知链路）均未在真机/模拟器上验证。建议在修复后在 Android 真机 + iOS 真机上各跑一轮通知采集与还原流程。

5. **修正记录**：本审计过程中修正了两处早前口头结论 ——
   - `about_page.dart:9` 的版本号是**正确**的（`1.0.1+2`），落后的是 `me_page.dart:169` 与 `export_service.dart:47`（见 #43）
   - 原生路径**有** `auto_capture_enabled` 检查，「关闭后仍写库」的表述不成立；真实缺陷是建议字段缺失（#18）与默认值不一致（#13）
