# tools/icon_pack — 图标库补齐管线

把仓库里**已经 vendored** 的图标包（`assets/_icon_packs/*.icons.json`）导入到
`assets/icons/<family>/` 与 `lib/core/icons/centli_icon_catalog.dart`。

## 为什么这样没有法律风险

| 项 | 说明 |
|---|---|
| 字形来源 | 只用仓库内已有的 `phosphor`（MIT）、`remix`（Apache-2.0）、`arcticons`（CC BY-SA 4.0）、`simple-icons`（CC0） |
| 不下载 | 脚本不联网，也不引用任何第三方 App 的字体或图形 |
| 不复制竞品 | 与 Finch 的图标库只共享「11 家族分类法」这一设计决策，不共享任何图形资产 |
| 许可义务 | 若新增 arcticons 图标，需遵守 CC BY-SA 4.0（署名 + 相同方式共享）；phosphor/remix/simple-icons 为宽松许可 |

## 用法

```bash
# 1) 编辑 targets.json，追加 { family, key, label, source, name }
#    source ∈ phosphor | remix | arcticons | simple-icons
#    name   = 图标包内的名字（如 currency-eur、piggy-bank）

# 2) 试运行，确认能解析
python tools/icon_pack/sync_icons.py

# 3) 写入 SVG 并追加 catalog 条目
python tools/icon_pack/sync_icons.py --apply
```

## 行为

- **幂等**：`key` 已存在于 catalog 时自动跳过，可反复运行。
- **缺名字不静默失败**：目标名在包里找不到时，该条进入 `unresolved` 并打印原因，其余照常处理。
- **改 catalog 前自动备份**：`lib/core/icons/centli_icon_catalog.dart.bak`。
- **生成格式**与现有图标完全一致：`<svg viewBox="0 0 256 256" width="256" height="256">` + `fill="currentColor"`。
- 运行记录写入 `tools/icon_pack/last_run.json`。

## 校验

改完后跑两个检查：

```bash
flutter analyze                                   # Dart 侧必须 0 issue
python tools/icon_pack/audit_icons.py             # catalog ↔ 磁盘 ↔ defaults 三层一致性（结果写 last_audit.txt）
```

`audit_icons.py` 会报告：条目指向的资产缺失、磁盘孤儿 SVG、默认图标键无法解析、以及每家族相对 Finch 的覆盖率。

## 当前状态（2026-10-17）

- 160 → **323** 个图标；通用家族已到 **~70%**（money 68%、food 63%、home 72%、life 70%、transport 68%、office 68%、electronics 70%、other 71%）
- 品牌类家族（bank 11%、payment 12%、brand 30%）**有意不追平**
- `flutter analyze`：No issues found
- 三层一致性：323 条目 ↔ 323 SVG ↔ 323 标签，0 处问题
- 未执行 `dart format`：该文件在本次改动前就不符合 `dart format`（备份同样不符合），整体重排会产生与本次无关的大量 diff

> **注意（已发生过一次）**：`centli_icon_catalog.dart` 若正被编辑器打开，编辑器可能用旧缓冲区覆盖磁盘内容，导致新增条目"消失"。`sync_icons.py` 是幂等的，重新 `--apply` 即可恢复；改完后建议在编辑器里对该文件执行 *Revert File / Reload from Disk*。
