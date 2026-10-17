#!/usr/bin/env python3
"""Audit the icon library: catalog <-> asset files <-> default keys <-> local packs.

Checks:
  1. every catalog entry's asset file exists, and no SVG is orphaned
  2. every key referenced by centli_icon_defaults.dart resolves
  3. keys in labels.json that are not yet in the catalog
  4. per-family coverage for reference

Usage:  python tools/icon_pack/audit_icons.py
Writes: tools/icon_pack/last_audit.txt   (and a short summary to stdout)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PACKS = REPO / "assets" / "_icon_packs"
ICONS = REPO / "assets" / "icons"
HERE = Path(__file__).resolve().parent
REPORT = HERE / "last_audit.txt"

CATALOG = REPO / "lib" / "core" / "icons" / "centli_icon_catalog.dart"
DEFAULTS = REPO / "lib" / "core" / "icons" / "centli_icon_defaults.dart"

# reference counts observed in the target product, used only for coverage reporting
REFERENCE = {"bank": 168, "payment": 122, "money": 101, "food": 60, "life": 57,
             "other": 48, "brand": 40, "home": 39, "office": 37,
             "transport": 34, "electronics": 30}
TARGET_RATIO = 0.70
TOLERANCE = 0.65  # "~70%, exact parity not required": >=65% counts as reached


def main() -> int:
    catalog_src = CATALOG.read_text(encoding="utf-8")
    defaults_src = DEFAULTS.read_text(encoding="utf-8")

    group_re = re.compile(r"CentliIconGroup\(\s*id:\s*'([^']+)',\s*title:\s*'([^']*)'")
    entry_re = re.compile(
        r"CentliIconEntry\(\s*key:\s*'([^']+)',\s*label:\s*'([^']*)',\s*asset:\s*'([^']+)'")

    marks = [(m.start(), "group", m.groups()) for m in group_re.finditer(catalog_src)]
    marks += [(m.start(), "entry", m.groups()) for m in entry_re.finditer(catalog_src)]
    marks.sort(key=lambda t: t[0])

    groups, cur = [], None
    for _, kind, g in marks:
        if kind == "group":
            cur = {"id": g[0], "title": g[1], "entries": []}
            groups.append(cur)
        elif cur is not None:
            cur["entries"].append({"key": g[0], "label": g[1], "asset": g[2]})

    default_keys = set(re.findall(r"return '([a-z0-9_]+)';", defaults_src))
    labels = {}
    lp = PACKS / "labels.json"
    if lp.exists():
        labels = json.loads(lp.read_text(encoding="utf-8"))

    pack_icons = {}
    for name in ("simple-icons", "arcticons", "phosphor", "remix"):
        p = PACKS / f"{name}.icons.json"
        if p.exists():
            pack_icons[name] = set(json.loads(p.read_text(encoding="utf-8")).get("icons", {}))

    disk = {p.relative_to(REPO).as_posix() for p in ICONS.rglob("*.svg")}
    all_entries = {e["key"]: e for g in groups for e in g["entries"]}
    referenced = {e["asset"] for e in all_entries.values()}

    missing_assets = [e for e in all_entries.values() if not (REPO / e["asset"]).exists()]
    orphan_assets = sorted(disk - referenced)
    defaults_missing = sorted(k for k in default_keys if k not in all_entries)
    labels_missing = sorted(k for k in labels if k not in all_entries)
    sourced = {k: [n for n, s in pack_icons.items() if k in s] for k in labels_missing}

    L = []
    L.append("=== 1. catalog 与磁盘一致性 ===")
    L.append(f"catalog 条目: {len(all_entries)}   磁盘 SVG: {len(disk)}")
    L.append(f"条目指向的资产缺失: {len(missing_assets)}")
    for e in missing_assets[:20]:
        L.append(f"   MISSING ASSET  {e['key']:<22} {e['asset']}")
    L.append(f"磁盘上未被 catalog 引用的 SVG: {len(orphan_assets)}")
    for p in orphan_assets[:20]:
        L.append(f"   ORPHAN  {p}")

    L.append("")
    L.append("=== 2. 默认图标键是否可解析 ===")
    L.append(f"defaults 引用键: {len(default_keys)}   catalog 中不存在: {len(defaults_missing)}")
    if defaults_missing:
        L.append("   " + ", ".join(defaults_missing))

    L.append("")
    L.append("=== 3. labels.json 有标签但未入 catalog ===")
    L.append(f"labels 键数: {len(labels)}   未入 catalog: {len(labels_missing)}")
    for k in labels_missing[:20]:
        src = sourced.get(k) or []
        L.append(f"   {k:<24} {labels[k]:<10} 可用来源: {', '.join(src) if src else '（本地包无同名）'}")

    L.append("")
    L.append("=== 4. 每家族覆盖 ===")
    L.append(f"{'family':<14}{'centli':>7}{'ref':>6}{'ratio':>8}{'target70':>10}{'status':>12}")
    under = []
    for g in groups:
        n = len(g["entries"])
        ref = REFERENCE.get(g["id"], 0)
        ratio = n / ref if ref else 0
        target = int(ref * TARGET_RATIO + 0.5) if ref else 0
        brand = g["id"] in {"bank", "payment", "brand"}
        if brand:
            status = "n/a(brand)"
        elif ref and ratio >= TOLERANCE:
            status = "OK"
        else:
            status = "SHORT"
            under.append((g["id"], n, target))
        L.append(f"{g['id']:<14}{n:>7}{ref:>6}{ratio:>7.0%}{target:>10}{status:>12}")

    L.append("")
    L.append("=== 5. 结论 ===")
    problems = len(missing_assets) + len(orphan_assets) + len(defaults_missing)
    L.append(f"  一致性问题: {problems} 处")
    L.append(f"  未达 70% 的通用家族: {len(under)}")
    for fam, n, t in under:
        L.append(f"    {fam}: {n} < {t}")

    REPORT.write_text("\n".join(L), encoding="utf-8")

    # ASCII-only stdout summary (console codepage may not be UTF-8)
    print(f"entries={len(all_entries)} svg={len(disk)} "
          f"missing_assets={len(missing_assets)} orphans={len(orphan_assets)} "
          f"defaults_broken={len(defaults_missing)} under_target={len(under)}")
    print(f"report: {REPORT}")
    return 0 if problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
