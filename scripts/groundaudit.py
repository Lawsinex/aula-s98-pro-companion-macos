#!/usr/bin/env python3
"""Assert the selected studio palette is drawn — and the UI has not collapsed.

This replaces the old AULA_DARK render, which existed because the tab bodies once
came out white-on-white offscreen with nothing painting a background. That failure
is now impossible by construction (both roots paint Ink.ground explicitly), so the
check becomes a direct assertion instead of an inference.

Pixel (0,0) == #000000 alone is satisfied by a completely blank frame — exactly the
vacuous pass the distinctness check exists to catch — so the colour count is
asserted alongside it.
"""
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("groundaudit: Pillow is required (python3 -m pip install pillow)\n")
    sys.exit(2)

MIN_COLOURS = 200
CORNER_TOLERANCE = 6   # PNG round-trips exactly, but a 2x render can dither an edge

failures = []
for path in sys.argv[1:]:
    name = os.path.basename(path)
    image = Image.open(path).convert("RGB")
    width, height = image.size
    corners = {
        "top-left": (0, 0),
        "top-right": (width - 1, 0),
        "bottom-left": (0, height - 1),
        "bottom-right": (width - 1, height - 1),
    }
    # The editor titlebar is #151515; its workspace and the menu panel remain black.
    expected = {where: (21, 21, 21) if name.startswith("tab-") and where.startswith("top")
                else (0, 0, 0) for where in corners}
    bad = {where: image.getpixel(point) for where, point in corners.items()
           if max(abs(actual - wanted) for actual, wanted in
                  zip(image.getpixel(point), expected[where])) > CORNER_TOLERANCE}
    colours = len(set(image.getdata()))

    if bad:
        failures.append(f"{name}: studio surface differs from its token at {bad}")
    if colours < MIN_COLOURS:
        failures.append(f"{name}: only {colours} distinct colours — the view collapsed")
    print(f"  {name:24s} studio palette  colours={colours}")

if failures:
    for line in failures:
        sys.stderr.write("FAIL " + line + "\n")
    sys.exit(1)

print(f"ground audit: {len(sys.argv) - 1} renders use the studio surface tokens, none collapsed")
