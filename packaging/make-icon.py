#!/usr/bin/env python3
"""Build AppIcon.icns: one lit keycap on the app's black ground.

An original mark for this project, drawn entirely here. It deliberately does not
use AULA's logo: the app is unofficial, and the MIT licence could not cover it.
"""
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUT_ICNS = HERE / "AppIcon.icns"
SIZE = 1024
SS = 2  # drawn at twice the size, then reduced for clean edges
EMBER = (255, 199, 153)  # Ink's peach accent
HOT = (255, 238, 220)


def rounded(size, box, radius, fill=255):
    layer = Image.new("L", size, 0)
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius, fill=fill)
    return layer


def vertical(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize(size).convert("RGBA")


def build():
    S = SIZE * SS
    canvas = (S, S)
    inset = round(S * 0.09)
    tile_box = (inset, inset, S - inset - 1, S - inset - 1)
    tile_radius = round((S - 2 * inset) * 0.224)
    tile_mask = rounded(canvas, tile_box, tile_radius)

    art = vertical(canvas, (28, 29, 33), (3, 3, 5))

    # The keycap: a wide skirt with a dished top set into it.
    cx, cy = S // 2, round(S * 0.485)
    half = round(S * 0.235)
    skirt = (cx - half, cy - half, cx + half, cy + half)
    r = round(half * 0.26)
    top_in = round(half * 0.20)
    top = (cx - half + top_in, cy - half + round(top_in * 0.55),
           cx + half - top_in, cy + half - round(top_in * 1.45))

    # Light escaping from under the cap: a wide soft bloom, then a tight bright rim.
    for blur, strength, grow in ((0.085, 0.62, 0.030), (0.030, 0.85, 0.012), (0.009, 1.0, 0.004)):
        g = round(S * grow)
        mask = rounded(canvas, (skirt[0] - g, skirt[1] - g, skirt[2] + g, skirt[3] + g), r + g)
        mask = mask.filter(ImageFilter.GaussianBlur(S * blur))
        mask = mask.point(lambda v, s=strength: int(v * s))
        art.paste(Image.new("RGBA", canvas, EMBER + (255,)), (0, 0), mask)
    rim = rounded(canvas, (skirt[0] - 5 * SS, skirt[1] - 5 * SS, skirt[2] + 5 * SS, skirt[3] + 5 * SS),
                  r + 5 * SS).filter(ImageFilter.GaussianBlur(3 * SS))
    art.paste(Image.new("RGBA", canvas, HOT + (255,)), (0, 0), rim)

    # The cap itself sits on top of the light, so only its edge glows.
    body = vertical(canvas, (54, 55, 60), (19, 19, 22))
    art.paste(body, (0, 0), rounded(canvas, skirt, r))
    face = vertical(canvas, (74, 75, 81), (40, 41, 46))
    art.paste(face, (0, 0), rounded(canvas, top, round(r * 0.72)))

    # A single ember legend: a small lit bar, the app's "applied" light.
    bar_w, bar_h = round(half * 0.56), round(half * 0.088)
    mid_y = (top[1] + top[3]) // 2
    bar = (cx - bar_w // 2, mid_y - bar_h // 2, cx + bar_w // 2, mid_y + bar_h // 2)
    bloom = rounded(canvas, bar, bar_h // 2).filter(ImageFilter.GaussianBlur(S * 0.012))
    art.paste(Image.new("RGBA", canvas, EMBER + (255,)), (0, 0), bloom)
    art.paste(Image.new("RGBA", canvas, HOT + (255,)), (0, 0), rounded(canvas, bar, bar_h // 2))

    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.paste(art, (0, 0), tile_mask)

    # A hairline, so the tile reads as an object on a dark Dock rather than a hole.
    edge = Image.new("L", canvas, 0)
    ImageDraw.Draw(edge).rounded_rectangle(tile_box, radius=tile_radius, outline=120, width=3 * SS)
    out.paste(Image.new("RGBA", canvas, (120, 122, 134, 255)), (0, 0), ImageChops.multiply(edge, tile_mask))
    return out.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    master = build()
    master.save(HERE.parent / ".github" / "assets" / "icon.png")
    iconset = HERE / "AppIcon.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir()
    for px in (16, 32, 64, 128, 256, 512, 1024):
        scaled = master.resize((px, px), Image.LANCZOS)
        scaled.save(iconset / f"icon_{px}x{px}.png")
        if px >= 32:
            scaled.save(iconset / f"icon_{px // 2}x{px // 2}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_ICNS)], check=True)
    shutil.rmtree(iconset)
    print(f"built {OUT_ICNS.name} ({OUT_ICNS.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
