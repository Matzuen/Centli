# -*- coding: utf-8 -*-
"""Validate generated app icons (T7-5)."""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "logo" / "logo.png"
EXPECTED_SHA = None  # filled at runtime from current file; must be stable across runs

TRAD = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
FG = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}
IOS = {
    "Icon-App-20x20@1x": 20,
    "Icon-App-20x20@2x": 40,
    "Icon-App-20x20@3x": 60,
    "Icon-App-29x29@1x": 29,
    "Icon-App-29x29@2x": 58,
    "Icon-App-29x29@3x": 87,
    "Icon-App-40x40@1x": 40,
    "Icon-App-40x40@2x": 80,
    "Icon-App-40x40@3x": 120,
    "Icon-App-60x60@2x": 120,
    "Icon-App-60x60@3x": 180,
    "Icon-App-76x76@1x": 76,
    "Icon-App-76x76@2x": 152,
    "Icon-App-83.5x83.5@2x": 167,
    "Icon-App-1024x1024@1x": 1024,
}


def main() -> int:
    errors: list[str] = []
    sha = hashlib.sha256(SRC.read_bytes()).hexdigest()
    print(f"logo_sha256={sha}")

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, size in TRAD.items():
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = res / folder / name
            im = Image.open(path)
            if im.size != (size, size) or im.mode != "RGBA":
                errors.append(f"{path}: got {im.size} {im.mode}")
            if path.stat().st_size < 1000:
                errors.append(f"{path}: suspiciously small {path.stat().st_size}")

    for folder, size in FG.items():
        path = res / folder / "ic_launcher_foreground.png"
        im = Image.open(path)
        if im.size != (size, size) or im.mode != "RGBA":
            errors.append(f"{path}: got {im.size} {im.mode}")

    anydpi = res / "mipmap-anydpi-v26"
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        if not (anydpi / name).exists():
            errors.append(f"missing {anydpi / name}")

    if not (res / "values" / "ic_launcher_background.xml").exists():
        errors.append("missing ic_launcher_background.xml")

    ios = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in IOS.items():
        path = ios / f"{name}.png"
        im = Image.open(path)
        if im.size != (size, size) or im.mode != "RGB":
            errors.append(f"{path}: got {im.size} {im.mode}")

    manifest = (ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    if 'android:roundIcon="@mipmap/ic_launcher_round"' not in manifest:
        errors.append("manifest missing roundIcon")

    if errors:
        print("FAIL")
        for e in errors:
            print(" ", e)
        return 1
    print("OK all icon checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
