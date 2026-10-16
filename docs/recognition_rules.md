# 识别规则（用户可配置）

## 入口

设置 → 自动记账 → **识别规则**（开关下方）

## 存储

| 文件 | 位置 | 内容 |
|---|---|---|
| `noti_templates.json` | assets + documents 覆盖 | **官方**模板（只读 UI；版本热更新） |
| `user_noti_templates.json` | documents | **我的规则** + `disabled_official_ids` |

解析时合并：`我的规则 ∪ (官方 − 已禁用)`，我的规则优先匹配。

官方 assets 本体不因用户编辑而改写。

## Native 杀路径说明

- Flutter 存活时：完整合并规则由 Dart `parseNotification` 执行。
- 进程被杀 / 仅原生：`CentliNotificationListener` 只做包名过滤 + `NativeCaptureIngest` 内置支付关键词；**不会**执行用户规则正文。
- 包名监听列表：Flutter 在保存规则后调用 `setWatchedPackages`，写入 SharedPreferences `watched_packages`，原生与内置微信/支付宝集合取并集，便于「其它」包名进入 Flutter 队列后再按用户规则解析。

## 试一试

页面内粘贴样例通知 → `explainNotificationParse` 显示金额/商户/忽略原因与步骤。

## 支付宝（v4）

- 包名：`com.eg.android.AlipayGphone`（原生 `WATCHED_PACKAGES` 与 `setWatchedPackages` 并集均含此包）。
- 匹配关键词：支付成功 / 付款成功 / **交易成功** / **交易提醒** / **交易通知**（标题或正文任一命中即可）。
- Native 杀路径 `NativeCaptureIngest` 的 `MUST_ALIPAY` 与 Dart 官方模板保持同步。
- 微信规则未改，不影响微信监听。
