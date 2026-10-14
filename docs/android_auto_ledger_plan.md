# Centli（厘记）— 安卓自动记账落地方案

> **Centli：厘记，厘清每一笔账单**  
> 对标 Finch 的产品路径与体验，不复制其代码与资源。  
> **已拍板：** 产品名 Centli / 厘记 · Flutter · 通知 + 待确认 · 首版多常见币种 · 后续文档一律 Markdown。

---

## 1. 目标与边界

**目标：** 安卓先发，记得出、记得准、改得快；支付通知进来先待确认，一键入账。

**首版做：**
- 账本 / 账户 / 分类 / 收支转账
- 计算器式手工记账
- `NotificationListener` 解析支付通知 → 待确认队列
- 商户规则学习（改一次分类，下次预填）
- 月统计（分类占比 + 收支趋势）
- 浅色 / 深色跟随系统；可选藏金额、生物识别锁
- 多币种：CNY、USD、JPY、TWD、HKD、EUR（可配置扩展，首版预置这批）
- 本地 SQLite；导出 JSON / Excel

**首版不做：** 云同步、加密货币、股票、订阅/分期/借贷/物品/愿望、完整 AI 聊天、WebDAV/Drive 备份（可放二期）。

---

## 2. 技术选型

| 层 | 选择 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x + Dart | 安卓先发，结构清晰 |
| 状态 | Riverpod 或 Bloc | 二选一，团队熟哪个用哪个 |
| 路由 | go_router | |
| 本地库 | Drift（推荐）或 Isar | SQL 可查、迁移清楚；金额用整数最小单位 |
| 偏好 | shared_preferences / Drift 设置表 | |
| 通知 | 安卓原生 `NotificationListenerService` + MethodChannel / pigeon | Flutter 侧只收结构化事件 |
| 图表 | fl_chart | |
| 导出 | Excel（如 excel 包）+ JSON | |
| 汇率（可选 P1.5） | 远程拉取日频缓存 | 首版可「账户自带币种 + 手工汇率」，统计按本位币折算 |

**工程结构建议：**

```
lib/
  app/           # 主题、路由、启动
  core/          # 金额、币种、时间、Result
  data/          # drift db、dao、repository
  domain/        # 实体、用例
  features/
    home/
    ledger/      # 记账面板、账单详情
    pending/     # 待确认
    stats/
    accounts/
    settings/
  platform/      # 通知 channel 封装
android/
  app/src/main/kotlin/.../NotificationCaptureService.kt
```

---

## 3. 币种规则（首版）

**预置：** `CNY, USD, JPY, TWD, HKD, EUR`（展示名 + 符号 + 小数位）。

| 币种 | 小数位 | 存储单位示例 |
|---|---|---|
| JPY | 0 | 1 日元 = 1 |
| 其余常见 | 2 | 1 元 = 100 |

- 每个**账户**绑定一种币种；流水币种跟账户走。
- **转账跨币种：** 记两笔腿 + 用户填汇率或对端金额（不要静默猜）。
- **账本本位币：** 用户选一个（默认 CNY）；统计页按「发生日汇率缓存」折算，无汇率时标「未折算」只展示原币。
- **不要**首版上加密货币。

---

## 4. 自动记账（通知 + 待确认）

### 4.1 流程

1. 引导页申请「通知使用权」（写清：只用于支付成功类通知辅助记账）。
2. `NotificationCaptureService` 过滤包名（支付宝 / 微信等可配置）。
3. 解析金额、商户、时间 → 写入 `pending_capture`。
4. 弹出/更新系统通知：「待确认 ¥xx · 商户」；点进 App 待确认页。
5. 用户：**确认** / **改分类·账户后确认** / **忽略**。
6. 确认后写 `transaction`，并 upsert `merchant_rule`。

### 4.2 体验要点

- 默认**不**静默入账。
- 去重：同商户 + 同金额 + 时间窗（如 120s）合并。
- 解析失败：进待确认，展示原始文案，金额可手改。
- 模板远程 JSON（包名、正则、字段），减少发版。

### 4.3 不做

- 无障碍掏页面、root、逆向支付 App 接口。

---

## 5. 信息架构（5 Tab / 入口）

1. **首页** — 本月概览、待确认红点、最近账单  
2. **记账** — 底部大「+」半屏面板：金额 → 分类 → 账户 → 备注  
3. **统计** — 月切换、分类占比、趋势（本位币）  
4. **资产** — 账户列表与余额（按币种分组）  
5. **我的** — 分类、币种/本位币、自动记账开关、导出、锁与藏金额、深浅色  

路径目标：待确认入账 ≤ 2 步；改分类就地完成。

---

## 6. 数据模型（最小）

```text
ledger(id, name, base_currency, created_at)
account(id, ledger_id, name, currency, type, opening_balance_minor, archived)
category(id, ledger_id, name, parent_id, kind /* in|out */, icon, sort)
transaction(
  id, ledger_id, type /* in|out|transfer */,
  amount_minor, currency,
  account_id, to_account_id, category_id,
  merchant, note, happen_at,
  include_in_stat, include_in_budget,
  transfer_group_id, fx_rate, /* 跨币种转账 */
  source /* manual|notification */, pending_id
)
pending_capture(
  id, source_pkg, raw_title, raw_text,
  amount_minor, currency, merchant, happen_at,
  suggested_category_id, suggested_account_id,
  status /* pending|confirmed|ignored */, dedupe_key
)
merchant_rule(id, merchant_key, category_id, account_id, hit_count)
fx_rate(day, from_ccy, to_ccy, rate)  -- 可二期再填
```

索引：`happen_at`、`account_id`、`category_id`、`pending.status`、`dedupe_key` UNIQUE。

---

## 7. 分阶段（可排期）

| 阶段 | 周期 | 交付 |
|---|---|---|
| P0 | 2 周 | Flutter 工程、Drift 表、账户分类、手工记账、账单列表详情、多币种账户 |
| P1 | 1～2 周 | 通知 Channel + 待确认页 + 去重 + 商户规则 |
| P2 | 1 周 | 月统计、导出、应用锁/藏金额、深浅色 |
| P3 | 按需 | 语音/文本 AI 填单、小组件（Android MVP 见 docs/centli_home_widget.md）、预算、备份、汇率自动刷新 |

---

## 8. 合规与上架

- 隐私政策写明：通知读取范围、本地存储、无云同步（若首版无）。
- 文案用「辅助记账，需确认后入账」。
- 渠道对通知监听敏感时，设置里可关，并提供纯手工模式。

---

## 9. 下一步（工程拆解，下份 md 可写）

1. `页面清单 + 线框说明`  
2. `Drift 表 SQL / 迁移`  
3. `通知解析伪代码 + 模板 JSON 样例`  
4. `P0 任务板（按日）`  

你说一声先写哪份即可。
