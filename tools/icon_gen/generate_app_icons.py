# -*- coding: utf-8 -*-
"""Generate Centli Android + iOS app icons from logo/logo.png (Pillow only).

Idempotent: re-running overwrites outputs with identical bytes for the same source.
Does NOT modify logo/logo.png.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "logo" / "logo.png"

ANDROID_TRADITIONAL = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# 108dp adaptive foreground canvases
ANDROID_FOREGROUND = {
    "drawable-mdpi": 108,
    "drawable-hdpi": 162,
    "drawable-xhdpi": 216,
    "drawable-xxhdpi": 324,
    "drawable-xxxhdpi": 432,
}

# iOS AppIcon.appiconset sizes (filename stem -> px)
IOS_SIZES = {
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

FOREGROUND_SCALE = 0.93  # fit content into 72dp safe zone


def sample_bg(im: Image.Image) -> tuple[int, int, int]:
    """Mean RGB of opaque pixels near left interior of the rounded square."""
    rgba = im.convert("RGBA")
    samples: list[tuple[int, int, int]] = []
    for x in range(220, 280, 10):
        for y in range(500, 700, 20):
            r, g, b, a = rgba.getpixel((x, y))
            if a > 240:
                samples.append((r, g, b))
    if not samples:
        raise RuntimeError("no opaque samples for background")
    n = len(samples)
    return (
        sum(s[0] for s in samples) // n,
        sum(s[1] for s in samples) // n,
        sum(s[2] for s in samples) // n,
    )


def resize_rgba(im: Image.Image, size: int) -> Image.Image:
    return im.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def make_foreground(im: Image.Image, canvas: int) -> Image.Image:
    scaled = int(round(canvas * FOREGROUND_SCALE))
    logo = resize_rgba(im, scaled)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    off = (canvas - scaled) // 2
    out.paste(logo, (off, off), logo)
    return out


def flatten_rgb(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    rgba = im.convert("RGBA")
    base = Image.new("RGBA", rgba.size, (*bg, 255))
    return Image.alpha_composite(base, rgba).convert("RGB")


def write_png(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, format="PNG", optimize=True)


def main() -> None:
    raw = SRC.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    im = Image.open(SRC)
    assert im.size == (1254, 1254), im.size
    bg = sample_bg(im)
    bg_hex = f"#{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}"
    print(f"source_sha256={sha}")
    print(f"sampled_bg={bg_hex}")

    res = ROOT / "android" / "app" / "src" / "main" / "res"

    # T7-2 traditional + round copies
    for folder, size in ANDROID_TRADITIONAL.items():
        icon = resize_rgba(im, size)
        write_png(icon, res / folder / "ic_launcher.png")
        write_png(icon, res / folder / "ic_launcher_round.png")
        print(f"android traditional {folder} {size} mode={icon.mode}")

    # T7-3 adaptive foregrounds
    for folder, size in ANDROID_FOREGROUND.items():
        fg = make_foreground(im, size)
        write_png(fg, res / folder / "ic_launcher_foreground.png")
        print(f"android foreground {folder} {size} mode={fg.mode}")

    # background color resource
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{bg_hex}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n"
    )
    (anydpi / "ic_launcher.xml").write_text(adaptive, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(adaptive, encoding="utf-8")

    # T7-4 iOS RGB flatten
    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in IOS_SIZES.items():
        rgb = flatten_rgb(resize_rgba(im, size), bg)
        assert rgb.mode == "RGB"
        write_png(rgb, ios_dir / f"{name}.png")
        print(f"ios {name} {size} mode={rgb.mode}")

    # Confirm source unchanged
    assert hashlib.sha256(SRC.read_bytes()).hexdigest() == sha
    print("OK source unchanged")


if __name__ == "__main__":
    main()
