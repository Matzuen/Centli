# 收尾审计输入说明（notes）— 工单 10～14

生成时间：2026-10-16（Asia/Shanghai）

## 1. 本批对应工单与改动文件

### 工单10（commit e404da1）— 待确认页降密度
- `lib/features/pending/pending_page.dart`：折叠摘要 + 入账/调整/忽略；建议值回落第一项并标出；分类/账户父级一次加载；保留 `ValueKey`；未改 `confirmPendingCapture` 签名
- `test/pending_card_key_test.dart`：适配构造（amend 入同 commit）

### 工单11（commit f180669）— 词表 + 来源 + 删除文案
- `lib/features/assets/assets_page.dart`：分组/类型统一为 现金/银行卡/电子钱包/其他
- `lib/core/constants/currencies.dart`：`currencyLabel` → `CNY（人民币）`
- `lib/features/settings/me_page.dart`：本位币用 `currencyLabel`
- `lib/app/shell.dart`：底栏「记一笔」
- `lib/data/db/centli_database.dart`：`confirmPendingCapture` 按 `sourcePkg` 写入真实来源（ocr/clipboard/share…）
- `lib/features/ledger/ledger_detail_page.dart`：来源标签覆盖截图等；删除确认改为「可在『回收站』恢复」

### 工单12（commit 491a855）— 信息层级
- `lib/features/ledger/ledger_detail_page.dart`：基本信息 / 来源与时间 / 其它；备注整行多行；商户空「—」
- `lib/features/assets/assets_page.dart`：归档态保留净资产卡（用使用中账户）；说明常显
- `lib/features/settings/me_page.dart`：通用/功能/数据/关于；移除账户管理；引导项仅 `kDebugMode`

### 工单13（commit 2c6b1e6）— tags + schema v4（独立提交）
- `lib/data/db/tables/transactions.dart`：`tags` TEXT 可空
- `lib/data/db/txn_tags.dart`：encode/decode（最多 5 个、每标签 ≤12 字）
- `lib/data/db/centli_database.dart`：schemaVersion 4；`onUpgrade` addColumn；`_ensureQueryIndexes`（5 条）；insert/update/confirm/search/listDistinct/updateTags
- `lib/data/db/centli_database.g.dart`：`build_runner` 已跑
- `lib/data/export/export_service.dart` / `import_service.dart`：schema 4；Excel tags 列；旧备份缺 tags 回落
- `lib/core/widgets/txn_list_tile.dart`：最多 2 标签 +N
- `lib/features/ledger/ledger_detail_page.dart`：显示/编辑标签
- `test/schema_v4_tags_migration_test.dart`：编解码、PRAGMA 索引、软删保留、搜索、schema3 无 tags 导入

### 工单14（commit 21bda68）— 记账面板方案 B（独立提交）
- `lib/features/ledger/bookkeeping_sheet.dart`：标题「记一笔 · 账本」；文字下划线 tab；去关闭 X；金额居中 + ISO；PopScope 防丢方案 B；智能填单移至键盘上方；备注旁标签；✓ Tooltip；tags 写入；未改键盘布局/`_evalAmount`/跨币弹窗

### 工单14补 — 分类账户改为两列下拉
- `lib/features/ledger/bookkeeping_sheet.dart`：**已补两列下拉**：L4 左分类/右账户（转账则转出|转入），`labelMedium`+`bodyLarge`+▾，点开沿用原 picker；删除 `_ChipScrollRow`/`_MetaChip`；时间改为 L5 表单行；未改配色/键盘/`_evalAmount`/跨币/防丢 B/标签输入/L7 语音文字

## 2. 是否有工单外顺手改动

- **无配色/主题改动**；**未改 §6 自动记账链路**；`stash@{0}` 仍保留。
- 工单13 为满足导入兼容，在 `_normalizeTransaction` 中保留并补全 `includeInStat`/`createdAt` 等 putIfAbsent（与补 tags 同函数）。
- 工单14补：已补两列下拉；分类|账户（转账时转出|转入）为「标签+当前值▾」表单行，不再使用横向 chip；时间改为同款表单行；标签输入未改。

## 3. flutter analyze / flutter test

- `flutter analyze` → **No issues found!**（见 `analyze.txt`）
- `flutter test` → **All tests passed!** **71 passed / 0 failed**（见 `test.txt`；基线 67 + schema/tags 相关 4）

## 4. 工单 13：build_runner / 迁移证据

- **build_runner**：已执行 `dart run build_runner build`（drift_dev 写出 `centli_database.g.dart`，含 `tags` 列）。
- **迁移**：`schemaVersion` 3→4；`onUpgrade from < 4` → `addColumn(transactions, transactions.tags)`；`beforeOpen`/`onUpgrade` 均调用 `_ensureQueryIndexes`（`CREATE INDEX IF NOT EXISTS` ×5）。
- **实测**（`test/schema_v4_tags_migration_test.dart`）：
  1. 新库 `PRAGMA user_version = 4`
  2. `PRAGMA index_list('transactions')` 含 `idx_txn_ledger_happen`、`idx_txn_account_happen`
  3. accounts/categories/pending 对应索引存在
  4. 写入 tags → 软删后 tags 仍在
  5. `schema_version: 3` 且无 `tags` 字段的 JSON 备份可导入，tags 为 null
- **说明**：未做「手写 raw sqlite v3 文件再 opened 升级」的端到端模拟（表结构与 Drift 生成 SQL 对齐成本高）；升级路径与既有 `from < 3` addColumn(icon) 同一模式，由 addColumn + beforeOpen 索引覆盖。

## 5. 工单 14 §14.4 误关闭防丢

- **选方案 B**：关闭（系统返回 / 下滑 / 遮罩触发的 pop）时若金额>0 或备注/标签非空，弹「已输入 …，确定放弃？」→ 放弃 / 继续记账。
- **原因**：用户不要关闭 X 但仍要退出路径；方案 B 不引入草稿复杂度（C），也不因 `isDismissible: false`（A）把下滑误关问题留给用户；一次确认成本低。

## 6. 「择一」选择

- 工单14 防丢：**方案 B**（见上）。
- 其余本批无新增强制二选一；工单2/4 等历史择一已在前序 commit。

## 7. 目视确认

- **未在真机/模拟器完成浅色+暗色+输入法弹起的完整目视**（本执行环境以 analyze/test 为主）。
- 工单8/14 相关布局按 `textTheme` / `displaySmall` / 左右 16 边距改动；**请审计方或用户在设备上补一眼**，尤其 800px + 键盘弹起时金额是否仍可见。

## 8. 风险与不确定点

1. **工单14 chip→下拉**：已补两列下拉（`_FormSelectTile`：`labelMedium` 标签 + `bodyLarge` 值 + ▾；点开仍用原 category/account picker）；已删除 `_ChipScrollRow`/`_MetaChip`；转账为转出|转入两列；时间改为同款表单行（标签输入仍在备注旁，未改）。
2. **工单14 文字 tab**：用 `InkWell`+下划线替代 `SegmentedButton`；选中态依赖 `primary`，未改 ColorScheme。
3. **工单13 迁移**：缺少「磁盘上真实 v3 DB 文件」升级的自动化用例；生产首次打开 v3 库时依赖 Drift Migrator + addColumn，建议真机升级抽检。
4. **工单11 来源**：仅新确认的 pending 会写入 ocr/share 等；历史已落库为 `notification` 的截图账单不会回写修正。
5. **Excel 导入列序**：新增 tags 列后按新列序号解析；旧 Excel（无 tags 列）可能错位——与既有「按列序号」风险一致（§7 备查），JSON 路径已兼容。
6. **stash@{0}** `pre-r2-workdir-auto-accounting-wip` 未弹出、未丢弃。

## 文字/语音记账独立面板（2026-10-16）

- 新增独立 bottom sheet：`text_bookkeeping_sheet.dart`、`voice_bookkeeping_sheet.dart`；共享入账 `smart_bookkeeping_submit.dart`（复用 `parseBookkeepingText` + 可选 LLM，不重写解析引擎）。
- 底栏「记一笔」短按仍打开传统手动面板；长按菜单分别打开文字/语音独立面板（不再 `expandAi`/`startVoice` 塞进传统 sheet）。
- 传统 `bookkeeping_sheet.dart` 已删除 L7 语音/文字辅助行及全部 AI 展开路径；标签、×÷、芯片行保留。
- **长录音模式**：现有 `LocalSpeechService` 无独立长录音引擎，语音面板暂不展示「切换到长录音模式」入口；若产品需要，后续可加入口并落到同一录音流程或接入长录音。
- 「每日剩余」无本地配额体系，文字/语音面板均未展示，未做付费墙。
- 标题用「文字记账」（本地规则解析为主；LLM 仅设置页可选增强），不用「AI 文字记账」。
