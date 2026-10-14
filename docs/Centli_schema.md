# Centli（厘记）— Drift 表结构 + 迁移

> 金额一律存 **最小货币单位整数**（`amount_minor`）。  
> 时间存 UTC 毫秒或 ISO-8601 文本，UI 再转本地。  
> 首版 schemaVersion = **1**。

---

## 1. 包与文件约定

```
lib/data/db/
  centli_database.dart      # @DriftDatabase
  tables/*.dart
  daos/*.dart
  converters/
    money_converter.dart    # 可选
assets/sql/                 # 若用手写迁移备查
```

`pubspec.yaml` 依赖建议：`drift`、`drift_dev`、`build_runner`、`sqlite3_flutter_libs`、`path_provider`、`path`。

---

## 2. 表定义

### 2.1 ledgers — 账本

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | uuid |
| name | TEXT | NOT NULL | 默认「个人」 |
| base_currency | TEXT | NOT NULL | 本位币，如 CNY |
| created_at | INTEGER | NOT NULL | epoch ms |
| archived | INTEGER | NOT NULL DEFAULT 0 | 0/1 |

### 2.2 accounts — 账户

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | |
| ledger_id | TEXT | NOT NULL FK→ledgers | |
| name | TEXT | NOT NULL | |
| currency | TEXT | NOT NULL | CNY/USD/JPY/TWD/HKD/EUR… |
| type | TEXT | NOT NULL | cash/bank/ewallet/other |
| opening_balance_minor | INTEGER | NOT NULL DEFAULT 0 | 期初，按账户币种 |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| archived | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

索引：`(ledger_id, archived)`。

### 2.3 categories — 分类

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | |
| ledger_id | TEXT | NOT NULL FK→ledgers | |
| name | TEXT | NOT NULL | |
| parent_id | TEXT | NULL FK→categories | 一级为 NULL |
| kind | TEXT | NOT NULL | `out` / `in` |
| icon | TEXT | NULL | 资源 key |
| sort_order | INTEGER | NOT NULL DEFAULT 0 | |
| archived | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | |

索引：`(ledger_id, kind, archived)`、`(parent_id)`。

### 2.4 transactions — 流水

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | |
| ledger_id | TEXT | NOT NULL FK→ledgers | |
| type | TEXT | NOT NULL | `in` / `out` / `transfer` |
| amount_minor | INTEGER | NOT NULL | 对本账户币种；转账为转出腿金额 |
| currency | TEXT | NOT NULL | |
| account_id | TEXT | NOT NULL FK→accounts | 支出/收入账户；转账=转出 |
| to_account_id | TEXT | NULL FK→accounts | 仅 transfer |
| category_id | TEXT | NULL FK→categories | transfer 可空 |
| merchant | TEXT | NULL | |
| note | TEXT | NULL | |
| happen_at | INTEGER | NOT NULL | 业务发生时间 |
| include_in_stat | INTEGER | NOT NULL DEFAULT 1 | |
| include_in_budget | INTEGER | NOT NULL DEFAULT 1 | 预算未做也先留列 |
| transfer_group_id | TEXT | NULL | 同一笔跨账户转账两侧同 id（若拆两腿）；单行模型可只用一行+to_account |
| fx_rate | REAL | NULL | 转出币→转入币；同币种 NULL |
| to_amount_minor | INTEGER | NULL | 跨币种时转入腿金额 |
| source | TEXT | NOT NULL DEFAULT manual | `manual` / `notification` |
| pending_id | TEXT | NULL | 来自哪条待确认 |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |
| deleted_at | INTEGER | NULL | 软删可选；首版可硬删不设 |

索引：`(ledger_id, happen_at)`、`(account_id, happen_at)`、`(category_id)`、`(transfer_group_id)`。

**余额计算（应用层）：**  
`balance = opening_balance_minor + Σ(in) − Σ(out) − Σ(transfer 转出) + Σ(transfer 转入 to_amount 或 amount)`。

首版推荐 **单行转账模型**（一行含 account_id + to_account_id），实现简单。

### 2.5 pending_captures — 待确认

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | |
| ledger_id | TEXT | NOT NULL | 默认当前账本 |
| source_pkg | TEXT | NOT NULL | 如 com.eg.android.AlipayGphone |
| raw_title | TEXT | NULL | |
| raw_text | TEXT | NOT NULL | |
| amount_minor | INTEGER | NULL | 解析失败可空 |
| currency | TEXT | NULL | 默认按建议账户币种，否则 CNY |
| merchant | TEXT | NULL | |
| happen_at | INTEGER | NULL | 解析不到用通知时间 |
| suggested_category_id | TEXT | NULL | |
| suggested_account_id | TEXT | NULL | |
| status | TEXT | NOT NULL | `pending` / `confirmed` / `ignored` |
| dedupe_key | TEXT | NOT NULL UNIQUE | 见解析文档 |
| parse_ok | INTEGER | NOT NULL DEFAULT 0 | |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

索引：`(status, created_at)`、`(dedupe_key)` UNIQUE。

### 2.6 merchant_rules — 商户学习

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | |
| ledger_id | TEXT | NOT NULL | |
| merchant_key | TEXT | NOT NULL | 规范化商户名 |
| category_id | TEXT | NULL | |
| account_id | TEXT | NULL | |
| hit_count | INTEGER | NOT NULL DEFAULT 1 | |
| updated_at | INTEGER | NOT NULL | |

唯一：`(ledger_id, merchant_key)`。

### 2.7 fx_rates — 汇率缓存 `[P2+]`

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| day | TEXT | PK 联合 | `yyyy-MM-dd` |
| from_ccy | TEXT | PK 联合 | |
| to_ccy | TEXT | PK 联合 | |
| rate | REAL | NOT NULL | 1 from = rate to |
| source | TEXT | NULL | |
| updated_at | INTEGER | NOT NULL | |

首版可空表；跨币种转账靠用户填 `fx_rate` / `to_amount_minor`。

### 2.8 app_settings — 键值设置

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| key | TEXT | PK | |
| value | TEXT | NOT NULL | JSON 或纯字符串 |

常用 key：`current_ledger_id`、`onboarding_done`、`hide_amount`、`app_lock`、`auto_capture_enabled`、`notification_template_version`、`base_currency`（可与 ledger 重复，以 ledger 为准）。


### 2.9 budgets — 月度预算 `[P3 MVP]`

| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| id | TEXT | PK | uuid |
| ledger_id | TEXT | NOT NULL FK→ledgers | |
| year_month | TEXT | NOT NULL | `yyyy-MM` 本地月 |
| category_id | TEXT | NOT NULL DEFAULT '' | `''`=月度总支出预算；否则 categories.id |
| amount_minor | INTEGER | NOT NULL | **账本本位币**最小单位 |
| created_at | INTEGER | NOT NULL | |
| updated_at | INTEGER | NOT NULL | |

唯一：`(ledger_id, year_month, category_id)`。  
进度：当月 `type=out` 且 `include_in_budget=1` 流水，按发生日汇率折本位币后与额度对比。


---

## 3. Drift 表示意（节选）

```dart
class Ledgers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseCurrency => text().named('base_currency')();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get archived => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id').references(Ledgers, #id)();
  TextColumn get name => text()();
  TextColumn get currency => text()();
  TextColumn get type => text()();
  IntColumn get openingBalanceMinor =>
      integer().named('opening_balance_minor').withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

// Categories / Transactions / PendingCaptures / MerchantRules / FxRates / AppSettings
// 按上表同理映射；Transactions.toAccountId、categoryId 用 .nullable()
```

---

## 4. 种子数据（首次打开）

1. 插入 1 个 ledger：`个人`，`base_currency=CNY`  
2. 默认账户：现金 CNY、支付宝 CNY、微信 CNY（opening=0）  
3. 支出分类示例：餐饮、交通、日用、居住、娱乐、医疗、教育、其他  
4. 收入分类示例：工资、红包、理财、其他  
5. settings：`auto_capture_enabled=false`（等用户授通知后再开）

用 `MigrationStrategy.onCreate` 写入；**不要**在每次启动重复插入（查 ledger 计数）。

---

## 5. 迁移策略

```dart
MigrationStrategy(
  onCreate: (m) async {
    await m.createAll();
    await seedDefaults();
  },
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      // 示例：await m.addColumn(transactions, transactions.includeInBudget);
    }
  },
)
```

约定：
- 只加列、加表，尽量不改列类型  
- 破坏性变更：新表 + 数据拷贝，或提示用户导出后重建（学习项目可接受）  
- `schemaVersion` 每次变更 +1，并在本文件追加「变更日志」

### 变更日志

| version | 说明 |
|---|---|
| 1 | 首版：ledgers / accounts / categories / transactions / pending_captures / merchant_rules / fx_rates / app_settings |
| 2 | 新增 budgets（月度总额/分类预算，P3 MVP） |

---

## 6. 查询用例（DAO 层）

| 用例 | 要点 |
|---|---|
| 首页当月收支 | `happen_at` 落在月区间，`type in/out`，`include_in_stat=1`，按本位币折算（无汇率则分币种展示） |
| 最近账单 | `ORDER BY happen_at DESC LIMIT 50` |
| 待确认 | `status=pending ORDER BY happen_at DESC` |
| 入账事务 | 插 transaction + 更新 pending + upsert merchant_rule，**同一 transaction** |
| 账户余额 | opening + 流水聚合；可缓存到内存，改流水后失效 |

---

## 7. 币种小数位（应用常量，不入库）

```dart
const currencyDecimals = {
  'CNY': 2, 'USD': 2, 'HKD': 2, 'TWD': 2, 'EUR': 2,
  'JPY': 0,
};
int toMinor(String ccy, Decimal major) => ...
String formatMinor(String ccy, int minor) => ...
```

---

下一份配套：`docs/Centli_notification_parse.md`。

### 导出/导入（应用层）

- `centli-export` JSON：`schema_version: 2` 起包含 `budgets` 数组（缺省则导入为空列表，兼容旧备份）。
- Excel：`budgets` sheet；导入仍仅支持 JSON。
- 还原：`restoreFromImportBundle` 清空后写回 budgets。
