#!/usr/bin/env python3
"""Build a macOS .icns from a 1024×1024 master PNG."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Resources" / "AppIcon.png"
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"

# Apple's macOS icon continuous-corner approximation.
CORNER_RATIO = 0.2237

SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def squircle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(size * CORNER_RATIO)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def prepare_master(src: Path, dest: Path) -> Image.Image:
    im = Image.open(src).convert("RGBA")
    im = im.resize((1024, 1024), Image.Resampling.LANCZOS)
    # Punch out near-white margins from generated previews, then apply squircle.
    pixels = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r > 245 and g > 245 and b > 245:
                pixels[x, y] = (r, g, b, 0)
    im.putalpha(ImageChops.multiply(im.getchannel("A"), squircle_mask(1024)))
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "PNG")
    return im


def build_iconset(master: Image.Image) -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)
    for size, name in SIZES:
        frame = master.resize((size, size), Image.Resampling.LANCZOS)
        frame.save(ICONSET / name, "PNG")


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else MASTER
    if not src.exists():
        print(f"error: missing {src}", file=sys.stderr)
        return 1
    master = prepare_master(src, MASTER)
    build_iconset(master)
    subprocess.check_call(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)])
    shutil.rmtree(ICONSET)
    print(ICNS)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
