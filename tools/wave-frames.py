#!/usr/bin/env python3
"""Writes per-key colour frames for the README's animation: a looping rainbow sweep."""
import colorsys
import json
import re
import sys
from pathlib import Path

FRAMES = 36
root = Path(__file__).resolve().parent.parent
layout = (root / "src" / "KeyLayout.swift").read_text()
keys = [(int(i), float(x)) for i, x in re.findall(r'KeyCap\(id:\s*(\d+),.*?x:\s*([-\d.]+),', layout)]
width = max(x for _, x in keys) or 1
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for n in range(FRAMES):
    frame = {}
    for led, x in keys:
        r, g, b = colorsys.hsv_to_rgb((x / width * 0.85 - n / FRAMES) % 1, 1, 1)
        frame[str(led)] = [round(r * 255), round(g * 255), round(b * 255)]
    (out / f"{n:02d}.json").write_text(json.dumps(frame))
