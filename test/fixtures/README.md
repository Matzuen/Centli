# Schema 迁移测试用的真实数据库

- `schema_v4.db`：schema 版本 4 的快照（含 member 列、无 asset_types）
- `schema_v10_member.db`：schema 版本 10 的快照（含 member 列，用于验证 v10→v11 合并）

用途：`test/schema_v11_member_merge_test.dart` 直接打开它们，验证真实升级路径。

**schema 变更时如何 regenerate**：用对应版本的 drift schema 生成空库 →
插入固定测试数据（见测试文件顶部注释）→ 覆盖本目录文件。
