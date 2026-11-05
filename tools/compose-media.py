#!/usr/bin/env python3
"""Frames raw captures for the README: window corners, a shadow, a cropped board."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
BOARD_CROP = (0, 190, 1672, 760)  # the board and its light bar, without the empty black


def windowed(path, radius=14, margin=48):
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    image.putalpha(mask)
    canvas = Image.new("RGBA", (w + 2 * margin, h + 2 * margin), (0, 0, 0, 0))
    shadow = Image.new("L", canvas.size, 0)
    shadow.paste(mask, (margin, margin + 10))
    shadow = shadow.filter(ImageFilter.GaussianBlur(margin / 2.4)).point(lambda v: int(v * 0.55))
    canvas.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 255)), (0, 0), shadow)
    canvas.alpha_composite(image, (margin, margin))
    return canvas


for name in ("lighting", "perkey", "clock", "presets", "apps", "settings", "panel"):
    windowed(raw / f"{name}.png").save(out / f"{name}.png", optimize=True)

for name in ("zones", "off"):
    Image.open(raw / f"{name}.png").convert("RGB").crop(BOARD_CROP).save(out / f"board-{name}.jpg", quality=90)

frames = [Image.open(p).convert("RGB").crop(BOARD_CROP).resize((960, 327), Image.LANCZOS)
          for p in sorted(raw.glob("wave-*.png"))]
# One palette from every frame: a single frame's colours would band the others.
mosaic = Image.new("RGB", (960, 327 * 6))
for row, frame in enumerate(frames[:: len(frames) // 6][:6]):
    mosaic.paste(frame, (0, 327 * row))
palette = mosaic.quantize(colors=256, method=Image.MAXCOVERAGE, dither=Image.NONE)
frames = [f.quantize(palette=palette, dither=Image.FLOYDSTEINBERG) for f in frames]
frames[0].save(out / "hero.gif", save_all=True, append_images=frames[1:],
               duration=80, loop=0, optimize=True, disposal=1)
