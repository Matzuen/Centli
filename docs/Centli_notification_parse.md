# Centli（厘记）— 通知解析伪代码 + 模板 JSON

> 原则：**只读通知**，用户确认后才入账；模板可远程/本地 JSON 热更新。  
> 安卓：`NotificationListenerService` → MethodChannel → Flutter `PendingRepository`。

---

## 1. 端到端流程

```
支付 App 发出通知
    → NotificationCaptureService.onNotificationPosted
    → 过滤 package / 渠道 / 标题
    → 取 title、text、bigText、when
    → 匹配 templates[]
    → 得到 ParseResult 或 failure
    → 算 dedupe_key；已存在则丢弃或刷新
    → 查 merchant_rules → 填 suggested_*
    → INSERT pending_captures
    → 系统通知「待确认 · ¥xx」/ 更新角标
    → Flutter 待确认页展示
    → 用户 Post → 写 transactions + 规则学习
```

---

## 2. 原生侧伪代码（Kotlin）

```kotlin
class NotificationCaptureService : NotificationListenerService() {
  override fun onNotificationPosted(sbn: StatusBarNotification) {
    if (!Settings.autoCaptureEnabled) return
    val pkg = sbn.packageName
    if (pkg !in TemplateStore.packages) return

    val extras = sbn.notification.extras
    val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
    val text = listOfNotNull(
      extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
      extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
    ).joinToString("\n")

    if (text.isBlank() && title.isBlank()) return

    val payload = mapOf(
      "pkg" to pkg,
      "title" to title,
      "text" to text,
      "when" to sbn.notification.`when`, // ms
      "key" to sbn.key,
      "channelId" to sbn.notification.channelId
    )
    // 发给 Flutter；若进程被杀，可先写入本地队列 Room/文件
    CentliPlugin.emit("notification_capture", payload)
  }
}
```

Flutter：

```dart
channel.setMethodCallHandler((call) async {
  if (call.method == 'notification_capture') {
    await pendingRepo.ingestRaw(Map<String, dynamic>.from(call.arguments));
  }
});
```

---

## 3. 解析伪代码（Dart）

```dart
class ParseResult {
  final int? amountMinor;
  final String? currency;   // 默认 CNY
  final String? merchant;
  final DateTime? happenAt;
  final bool ok;
  final String? templateId;
}

ParseResult parse(RawNotification raw, List<NotiTemplate> templates) {
  final matched = templates.where((t) => t.packages.contains(raw.pkg)).toList();
  for (final t in matched) {
    if (t.titleRegex != null && !RegExp(t.titleRegex!).hasMatch(raw.title)) continue;
    if (t.excludeTextRegex != null && RegExp(t.excludeTextRegex!).hasMatch(raw.text)) {
      continue; // 如「登录」「验证码」
    }
    final body = raw.fullText; // title + text
    if (!RegExp(t.mustContainRegex ?? r'.').hasMatch(body)) continue;

    final amount = _extractAmount(body, t.amountRegex);
    final merchant = _extractMerchant(body, t.merchantRegex, t.merchantFromTitle);
    final ccy = _extractCurrency(body, t) ?? t.defaultCurrency ?? 'CNY';
    final when = DateTime.fromMillisecondsSinceEpoch(raw.whenMs);

    return ParseResult(
      amountMinor: amount,
      currency: ccy,
      merchant: merchant?.trim(),
      happenAt: when,
      ok: amount != null,
      templateId: t.id,
    );
  }
  return ParseResult(ok: false, happenAt: DateTime.fromMillisecondsSinceEpoch(raw.whenMs));
}

int? _extractAmount(String body, String amountRegex) {
  final m = RegExp(amountRegex).firstMatch(body);
  if (m == null) return null;
  final raw = (m.group(1) ?? '').replaceAll(',', '');
  final major = Decimal.tryParse(raw);
  if (major == null) return null;
  // 先按默认 2 位；若命中 JPY 模板再用 0 位
  return (major * Decimal.fromInt(100)).toBigInt().toInt(); // 简化：非 JPY
}

String dedupeKey(RawNotification raw, ParseResult r) {
  // 优先稳定业务字段；否则退回通知 key
  final merchant = (r.merchant ?? '').trim().toLowerCase();
  final amt = r.amountMinor?.toString() ?? 'na';
  final bucket = (raw.whenMs ~/ 120000); // 2 分钟窗
  return '${raw.pkg}|$merchant|$amt|$bucket';
}
```

**入队：**

```dart
Future<void> ingestRaw(Map raw) async {
  final parsed = parse(...);
  final key = dedupeKey(...);
  if (await existsDedupe(key)) return;

  final rule = parsed.merchant != null
      ? await findRule(normalize(parsed.merchant!))
      : null;

  await into(pendingCaptures).insert(PendingCapturesCompanion.insert(
    id: uuid(),
    sourcePkg: raw['pkg'],
    rawTitle: raw['title'],
    rawText: raw['text'],
    amountMinor: Value(parsed.amountMinor),
    currency: Value(parsed.currency),
    merchant: Value(parsed.merchant),
    happenAt: Value(parsed.happenAt?.millisecondsSinceEpoch),
    suggestedCategoryId: Value(rule?.categoryId),
    suggestedAccountId: Value(rule?.accountId ?? defaultAccountForPkg(raw['pkg'])),
    status: 'pending',
    dedupeKey: key,
    parseOk: parsed.ok ? 1 : 0,
    ...
  ));
  showLocalNotification(...);
}
```

**确认入账：**

```dart
await db.transaction(() async {
  await into(transactions).insert(... from pending + user edits ...);
  await update(pending).set(status: confirmed);
  if (merchant.isNotEmpty) upsertMerchantRule(...);
});
```

---

## 4. 模板 JSON Schema

```json
{
  "version": 4,
  "updated_at": "2026-10-16",
  "templates": [
    {
      "id": "alipay_pay_success_zh",
      "packages": ["com.eg.android.AlipayGphone"],
      "defaultCurrency": "CNY",
      "titleRegex": null,
      "mustContainRegex": "支付成功|付款成功|交易成功|交易提醒|交易通知",
      "excludeTextRegex": "验证码|登录|收款到账提醒",
      "amountRegex": "(?:¥|￥)\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)",
      "merchantRegex": "(?:给|向|付款给)\\s*(.+?)(?:\\s|$)",
      "merchantFromTitle": false,
      "defaultAccountHint": "alipay"
    },
    {
      "id": "wechat_pay_success_zh",
      "packages": ["com.tencent.mm"],
      "defaultCurrency": "CNY",
      "mustContainRegex": "微信支付|支付成功|已支付",
      "excludeTextRegex": "验证码|登录|朋友圈",
      "amountRegex": "(?:¥|￥)\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)",
      "merchantRegex": "(.+?)(?:-微信支付|付款)",
      "merchantFromTitle": true,
      "defaultAccountHint": "wechat"
    }
  ]
}
```


### 支付宝通知标题说明（v4）

真机上支付宝支付后的系统通知标题常见为 **交易提醒** / **交易通知**（不一定带「支付成功」字样）。
官方模板 `mustContainRegex` 已包含：`支付成功|付款成功|交易成功|交易提醒|交易通知`。
仍排除：验证码、登录、收款到账提醒、服务通知、余额宝收益等非支出记账噪声。

### 字段说明

| 字段 | 含义 |
|---|---|
| packages | 命中的应用包名列表 |
| mustContainRegex | 正文+标题必须匹配（支付成功类） |
| excludeTextRegex | 命中则丢弃（防验证码等） |
| amountRegex | 第 1 捕获组为金额 |
| merchantRegex | 第 1 捕获组为商户；可空 |
| merchantFromTitle | true 时优先用 title 当商户候选 |
| defaultAccountHint | 映射到本地账户 type/name |

模板文件位置建议：
- 内置：`assets/noti_templates.json`  
- 覆盖：`getApplicationDocumentsDirectory()/noti_templates.json`（设置页可「检查更新」）

---

## 5. 包名与默认账户映射（示例）

| hint / pkg | 默认账户名 |
|---|---|
| alipay / com.eg.android.AlipayGphone | 支付宝 |
| wechat / com.tencent.mm | 微信 |

用户可在设置里改「该 App → 账户」。

---

## 6. 边界与测试用例

| 场景 | 期望 |
|---|---|
| 验证码通知含金额 | exclude 丢掉 |
| 2 分钟内同商户同金额两条 | 同一 dedupe_key，只留一条 |
| 只有「支付成功」无金额 | parse_ok=0，进待确认手改 |
| 外币符号 `$` / `€` | 扩展 amountRegex 与 currency 探测（P1.5） |
| 服务被系统杀掉 | 引导开「忽略电池优化」；不承诺 100% 送达 |
| 用户关自动记账 | Service 直接 return |

手工测试：用 Android 通知测试 App 或 `adb shell cmd notification post` 模拟（真机包名过滤需临时加 debug 包名）。

---

## 7. 权限与文案

- 设置路径：系统 → 特殊应用权限 → 通知使用权 → Centli  
- 应用内文案：「开启后，将读取支付成功类通知并生成待确认账单，不会自动扣款或静默改账。」  
- Play/国内上架：隐私政策写明监听包名范围与本地存储。

---

## 8. 与页面的衔接

| 解析结果 | UI |
|---|---|
| parse_ok=1 + 有规则 | 待确认卡预填分类/账户，主按钮「入账」 |
| parse_ok=1 无规则 | 预填账户，分类必选后再入账 |
| parse_ok=0 | 高亮「补金额」，商户可编辑 |

配套表结构见 `docs/Centli_schema.md`。
