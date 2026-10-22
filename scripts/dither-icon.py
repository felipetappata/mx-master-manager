#!/usr/bin/env python3
"""Apply a coarse, deterministic Bayer dither to the original mouse pixels.

Requires Pillow. Usage: dither-icon.py <mouse.png> <icon.png>
The working image is 128 pixels square; nearest-neighbor scaling preserves it.
"""
from pathlib import Path
import math
import sys
from PIL import Image

GRID = 128
OUTPUT = 1024
PALETTE = [(8, 4, 15), (152, 152, 161), (245, 245, 247)]
BAYER = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)


def dither(source: Path, destination: Path) -> None:
    original = Image.open(source).convert("RGBA")
    bounds = original.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("The mouse image is empty")
    mouse = original.crop(bounds)
    height = 112
    width = round(mouse.width * height / mouse.height)
    mouse = mouse.resize((width, height), Image.Resampling.LANCZOS)
    luminance = mouse.convert("L")
    alpha = mouse.getchannel("A")
    values = sorted(value for value, coverage in zip(luminance.getdata(), alpha.getdata()) if coverage >= 240)
    black = values[round((len(values) - 1) * 0.02)]
    white = values[round((len(values) - 1) * 0.95)]
    image = Image.new("RGB", (GRID, GRID), PALETTE[0])
    x0, y0 = (GRID - width) // 2, (GRID - height) // 2
    for y in range(height):
        for x in range(width):
            threshold = (BAYER[y % 4][x % 4] + 0.5) / 16
            if alpha.getpixel((x, y)) / 255 <= threshold:
                continue
            level = (luminance.getpixel((x, y)) - black) / max(1, white - black)
            level = min(1, max(0, level)) ** 0.65
            scaled = level * 2
            lower = math.floor(scaled)
            color = min(2, lower + int(scaled - lower >= threshold))
            image.putpixel((x0 + x, y0 + y), PALETTE[color])
    image = image.resize((OUTPUT, OUTPUT), Image.Resampling.NEAREST)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)
    print(f"128x128 Bayer dither, 3 exact colors, nearest-neighbor to 1024: {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: dither-icon.py <mouse.png> <icon.png>")
    dither(Path(sys.argv[1]), Path(sys.argv[2]))
