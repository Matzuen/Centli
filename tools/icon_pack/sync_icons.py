#!/usr/bin/env python3
"""Fill Centli's icon library from the packs already vendored in this repo.

Pipeline:
  1. read tools/icon_pack/targets.json  (curated: family, key, label, source, name)
  2. resolve the glyph body from assets/_icon_packs/<source>.icons.json
  3. write assets/icons/<family>/<key>.svg  (same wrapper as the existing icons)
  4. insert a CentliIconEntry into the matching group of lib/core/icons/centli_icon_catalog.dart

Nothing is downloaded and no third-party app assets are used: every glyph comes from
phosphor (MIT), remix (Apache-2.0) or arcticons (CC BY-SA 4.0), which this repo already ships.

Usage:
  python tools/icon_pack/sync_icons.py            # dry run, prints the plan
  python tools/icon_pack/sync_icons.py --apply    # writes SVGs and patches the catalog
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PACK_DIR = REPO / "assets" / "_icon_packs"
ICON_DIR = REPO / "assets" / "icons"
CATALOG = REPO / "lib" / "core" / "icons" / "centli_icon_catalog.dart"
TARGETS = Path(__file__).resolve().parent / "targets.json"
REPORT = Path(__file__).resolve().parent / "last_run.json"

SVG_WRAP = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
            'width="{w}" height="{h}">{body}</svg>')

ENTRY = """      CentliIconEntry(
        key: '{key}',
        label: '{label}',
        asset: '{asset}',
      ),
"""


def load_packs(names):
    packs = {}
    for n in names:
        p = PACK_DIR / f"{n}.icons.json"
        if p.exists():
            packs[n] = json.loads(p.read_text(encoding="utf-8"))
    return packs


def resolve_body(pack, name, seen=None):
    """Return (body, width, height) for an icon name, following alias parents."""
    seen = seen or set()
    if name in seen:
        return None
    seen.add(name)
    icons = pack.get("icons", {})
    aliases = pack.get("aliases", {})
    if name in icons:
        it = icons[name]
        return it.get("body"), it.get("width", pack.get("width", 24)), it.get("height", pack.get("height", 24))
    if name in aliases:
        al = aliases[name]
        if "parent" in al:
            return resolve_body(pack, al["parent"], seen)
        return al.get("body"), al.get("width", pack.get("width", 24)), al.get("height", pack.get("height", 24))
    return None


def catalog_state():
    text = CATALOG.read_text(encoding="utf-8")
    keys = set(re.findall(r"CentliIconEntry\(\s*key:\s*'([^']+)'", text))
    groups = re.findall(r"CentliIconGroup\(\s*id:\s*'([^']+)'", text)
    return text, keys, groups


def patch_catalog(text, additions):
    """Insert entries at the end of each group's entries list."""
    for family, entries in additions.items():
        gid = re.search(r"CentliIconGroup\(\s*id:\s*'" + re.escape(family) + r"'", text)
        if not gid:
            raise SystemExit(f"group '{family}' not found in catalog")
        estart = text.find("entries: [", gid.end())
        if estart < 0:
            raise SystemExit(f"'entries: [' not found for group '{family}'")
        close = text.find("\n    ],", estart)
        if close < 0:
            raise SystemExit(f"group close not found for '{family}'")
        block = "".join(ENTRY.format(**e) for e in entries)
        text = text[:close] + "\n" + block.rstrip("\n") + text[close:]
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write files instead of planning")
    args = ap.parse_args()

    targets = json.loads(TARGETS.read_text(encoding="utf-8"))["targets"]
    packs = load_packs({t["source"] for t in targets})
    text, existing_keys, groups = catalog_state()

    plan, unresolved, duplicates = [], [], []
    by_family: dict[str, list[dict]] = {}

    for t in targets:
        fam, key = t["family"], t["key"]
        if fam not in groups:
            unresolved.append({**t, "reason": f"unknown family '{fam}'"})
            continue
        if key in existing_keys:
            duplicates.append({**t, "reason": "key already in catalog"})
            continue
        pack = packs.get(t["source"])
        if not pack:
            unresolved.append({**t, "reason": f"pack '{t['source']}' not vendored"})
            continue
        got = resolve_body(pack, t["name"])
        if not got or not got[0]:
            unresolved.append({**t, "reason": f"'{t['name']}' not found in {t['source']}"})
            continue
        body, w, h = got
        asset = f"assets/icons/{fam}/{key}.svg"
        plan.append({**t, "asset": asset, "bytes": len(SVG_WRAP.format(w=w, h=h, body=body))})
        by_family.setdefault(fam, []).append({**t, "asset": asset})
        existing_keys.add(key)  # guard against duplicate keys inside targets.json

    print(f"targets={len(targets)}  to_add={len(plan)}  "
          f"duplicates={len(duplicates)}  unresolved={len(unresolved)}")
    for fam in sorted(by_family):
        print(f"  {fam:<14} +{len(by_family[fam])}")
    for u in unresolved:
        print(f"  UNRESOLVED {u['family']}/{u['key']}: {u['reason']}")
    for d in duplicates:
        print(f"  SKIP       {d['family']}/{d['key']}: {d['reason']}")

    if not args.apply:
        print("\n(dry run — re-run with --apply to write)")
        REPORT.write_text(json.dumps({"plan": plan, "unresolved": unresolved,
                                      "duplicates": duplicates, "applied": False},
                                     ensure_ascii=False, indent=1), encoding="utf-8")
        return 0

    written = []
    for item in plan:
        fam, key, src, name = item["family"], item["key"], item["source"], item["name"]
        body, w, h = resolve_body(packs[src], name)
        out = REPO / item["asset"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(SVG_WRAP.format(w=w, h=h, body=body), encoding="utf-8")
        written.append(item["asset"])

    backup = CATALOG.with_suffix(".dart.bak")
    shutil.copy2(CATALOG, backup)
    new_text = patch_catalog(text, by_family)
    CATALOG.write_text(new_text, encoding="utf-8")

    _, keys_after, _ = catalog_state()
    print(f"\napplied: {len(written)} svg, catalog entries {len(existing_keys)} -> {len(keys_after)}")
    print(f"backup:  {backup}")
    REPORT.write_text(json.dumps({"plan": plan, "unresolved": unresolved,
                                  "duplicates": duplicates, "applied": True,
                                  "written": written, "catalogBackup": str(backup)},
                                 ensure_ascii=False, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
