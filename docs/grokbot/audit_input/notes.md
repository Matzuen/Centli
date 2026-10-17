# Centli B2 审计输入 · notes.md

> 生成：2026-10-17（Asia/Shanghai）
> 执行者：Grok Bot
> 基线：`50fe624` → HEAD `185ebf9`
> 本批续做：此前已完成 T1–T4-2；本回合补齐 T4-3 … T6-6，并尝试 T6-7

---

## 1. 子任务 → commit hash

| 子任务 | commit | 说明 |
|---|---|---|
| T1-1 | `2db6454` | NotiTemplate.direction |
| T1-2 | `d033eb2` | ParseResult.direction |
| T1-3 | `60638a6` | 收入/退款模板 |
| T1-4 | `d1589a5` | 待确认折叠方向 |
| T1-5 | `90315c1` | 默认分类按方向 |
| T2-1 | （只读） | 无 commit |
| T2-2 | `6672de8` | rules_json 下发 Scheme A |
| T2-3 | `8219e7b` | dedupe 去 merchant |
| T2-4 | `d87702c` | 原生入队带 direction |
| T3-1 | （只读） | 无 commit |
| T3-2/T3-3/T3-4 | `7182bae` | 文件/URL 导入 + 版本守卫 |
| T3-5 | `aa6d36d` | 字段级合并用户优先 |
| T3-6 | （并入 `7182bae` / 规则更新路径） | 更新后走既有 sync 下发 |
| T4-1 | `87ed994` | 计入预算开关 |
| T4-2 | `065ec3e` | refund 类型冲减支出 |
| **T4-3** | **`41e535f`** | Excel include_in_budget + 按表头导入 |
| **T4-4** | **`5389a6a`** | 预算页未折算提示 |
| **T5-1** | **`39d5397`** | 历史商户自动完成 |
| **T5-2** | **`8b9631a`** | 存为模板 / 选模板预填 |
| **T5-3** | **`0b6398f`** | 可选 member + 详情展示（schema v5） |
| **T6-1** | **`5ad1231`** | 列表元数据上提，去掉行内 N+1 |
| **T6-2** | **`b3e3bf8`** | 搜索截断提示 / 归档账户 / 分类账户名 |
| **T6-3** | **`5e5da8a`** | 记账日期 lastDate=今天 |
| **T6-4** | **`ac4eac1`** | 期初二次确认 / 资产跟账户 / 余额校正标记 |
| **T6-6** | **`185ebf9`** | B1 遗留：textTheme、别名标注、行为测试、净资产一致测试 |
| **T6-7** | **未提交（已回滚）** | 见 §7 |
| **T6-5** | 本目录产物 | audit_input 相对 `50fe624` 重生 |

---

## 2. 本回合主要改动文件（续做部分）

- T4-3：`lib/data/export/export_service.dart`、`import_service.dart`，`test/excel_include_budget_test.dart`
- T4-4：`centli_database.dart`（MonthBudgetProgress.unconvertedByCcy）、`budget_page.dart`，`test/budget_test.dart`
- T5-1：`listMerchantSuggestions` + `bookkeeping_sheet` RawAutocomplete，`test/merchant_suggestions_test.dart`
- T5-2：`lib/data/txn_templates.dart`（settings JSON，无新表），详情「存为模板」、记账「模板」，`test/txn_templates_test.dart`
- T5-3：`transactions.member` + schema 5 + Drift 生成，记账/详情 UI，`test/member_field_test.dart`
- T6-1：`TxnListLookups` + `TxnGroupedList` 一次加载，`txn_list_tile` 同步查表
- T6-2：`searchTransactions` 提限 +1 / 分类账户名 / `loadAccountsIncludingArchived`
- T6-3：`bookkeeping_sheet` date picker
- T6-4：`assets_page` 确认对话框与 accounts 订阅；列表/详情「余额校正」标识
- T6-6：`home_page` 未折算改 textTheme；8 个 provider `@visibleForTesting`；pending 纯行为测试；`networth_consistency_test.dart`

---

## 3. analyze / test

```
flutter analyze  →  No issues found!
flutter test     →  120 passed / 0 failed
```

起始基线 87；本批（含先前 T1–T4-2）净增测试至 120。

---

## 4. flutter build apk --debug

见 `build_apk.txt`：成功生成 `build/app/outputs/flutter-apk/app-debug.apk`（退出码 0）。
仍有 home_widget KGP 前向兼容警告（不阻塞）。

---

## 5. T1 要点（既有）

- 微信红包：收入模板用 mustContain 区分「收到/领取」；发出仍走支出；无法可靠区分时宁可漏记。
- `direction` → 待确认确认入账：`refund` → `type='refund'`；`in`/`out` 按分类 kind；与 `type` 对齐，避免方向与类型歧义。

---

## 6. T2 要点（既有）

- `rules_json`：Dart 合并规则生成，写入原生；原生按 pkg 匹配，无匹配则宽松入队。
- **真机「App 被杀」路径：本环境未做真机验证**（诚实标注）。逻辑与 debug 构建已通过。

---

## 7. T3 要点（既有）

- 来源：本地文件导入 + 用户填写 HTTPS URL；**未臆造官方 URL**。
- 版本：整数 `version` 更高才覆盖；坏规则拒绝；可回滚内置。

---

## 8. T4 要点

- 退款 A+B：`type=refund` 冲减支出合计、不进收入；负金额支出兼容。
- Excel：导出 `include_in_budget`；导入按表头；缺必需列抛可读错误；缺预算列默认 1。
- 预算未折算：仍不计入 spent，页面提示与首页/统计同前缀「未折算：」。

---

## 9. T5

- T5-1 / T5-2 / T5-3 **均已做**（未跳过成员）。
- 模板存 app_settings JSON（`txn_templates_<ledgerId>`），无完整 CRUD 页。
- 成员为自由文本列，无成员管理页/筛选。

---

## 10. 工单外顺手改动

无（仅 schema 测试断言随 v5 更新 `user_version` 期望，属 T5-3 必要配套）。

---

## 11. 风险与不确定

1. **T6-7**：已尝试将 `android.builtInKotlin` 设为 `true`；debug/release 均构建成功，但 **KGP 警告仍在**（`home_widget` 在 AGP&lt;9 时仍 apply kotlin-android）。按验收「警告消失」未达成，**已回滚为 false，无半迁移提交**。真正消除需 AGP 9+。
2. **T2 杀进程路径**：无真机实证。
3. **目视**：本回合未做浅色/暗色真机目视（记账面板含模板/商户/成员输入法弹起未人工看）。
4. Autocomplete 商户建议依赖列表级一次加载；极多历史商户时仅取前 30。
5. 搜索 `limit+1` 探测截断；默认展示上限 200。

---

## 12. 目视确认

未在本机完成浅色/暗色/输入法弹起目视；请审计方或用户抽查：预算未折算条、记账商户/成员/模板、搜索截断条、余额校正标识、期初确认对话框。
