#!/usr/bin/env python3
"""Gate 3 — the hitbox audit.

The hitbox map is what a click means, and it fails differently from the picture:
the board can look perfect while every click lands one key to the left. The
automated half re-asserts the Stage-4 invariants against the shipped texture
(not against the builder's memory of it); the human half is /tmp/hitboxes.png,
which a fresh pair of eyes checks against the WHITE photograph's printed legends.
"""

import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHOTO = os.path.join(ROOT, "viewer", "photo")
OUT = "/tmp/hitboxes.png"


def apply_h(H, pts):
    p = np.hstack([np.asarray(pts, float).reshape(-1, 2), np.ones((len(pts), 1))])
    q = p @ np.asarray(H).T
    return q[:, :2] / q[:, 2:3]


def main():
    meta = json.load(open(os.path.join(PHOTO, "maps.json")))
    layout = json.load(open(os.path.join(ROOT, "viewer", "layout.json")))
    keys = layout["keys"]
    hit = np.asarray(Image.open(os.path.join(PHOTO, "hit.png")).convert("L"))
    H = np.array(meta["homography"])

    fails = []
    want = sorted(k["id"] for k in keys)
    present = sorted(set(np.unique(hit).tolist()) - {0})
    ok = present == want
    print("distinct LED ids in the hitbox map: %d (want 96) -> %s"
          % (len(present), "PASS" if ok else "FAIL"))
    if not ok:
        fails.append("id set")

    # every region a single connected component
    broken = []
    for i in want:
        m = hit == i
        ys, xs = np.nonzero(m)
        if not len(ys):
            broken.append(i)
            continue
        seen = np.zeros_like(m)
        q = deque([(ys[0], xs[0])])
        seen[ys[0], xs[0]] = True
        n = 0
        while q:
            y, x = q.popleft()
            n += 1
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if (0 <= ny < m.shape[0] and 0 <= nx < m.shape[1]
                        and m[ny, nx] and not seen[ny, nx]):
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if n != m.sum():
            broken.append(i)
    print("regions that are a single connected component: %d/96 -> %s"
          % (96 - len(broken), "PASS" if not broken else "FAIL %s" % broken))
    if broken:
        fails.append("connectivity")

    # every region contains its own projected cap centroid
    missing = []
    for k in keys:
        c = apply_h(H, [(k["x"] + k["w"] / 2, k["y"] + k["h"] / 2)])[0]
        if hit[int(round(c[1])), int(round(c[0]))] != k["id"]:
            missing.append(k["name"])
    print("regions containing their own projected cap centroid: %d/96 -> %s"
          % (96 - len(missing), "PASS" if not missing else "FAIL %s" % missing))
    if missing:
        fails.append("centroid containment")

    # the bar, strip, screen and knob must not be paintable
    for name in ("tft", "knob"):
        x0, y0, x1, y1 = meta["exclude"][name]
        if hit[y0:y1, x0:x1].any():
            fails.append("%s is paintable" % name)
            print("%s region is paintable -> FAIL" % name)
    print("screen and knob are not paintable -> %s"
          % ("PASS" if not any("paintable" in f for f in fails) else "FAIL"))

    # the overlay a human checks
    white = Image.open(os.path.join(ROOT, "viewer", "reference", "white.png")).convert("RGB")
    base = np.asarray(white).astype(np.float64)
    tint = np.zeros_like(base)
    for n, i in enumerate(want):
        m = hit == i
        hue = (n * 137.508) % 360.0
        c = np.array(hsv_to_rgb(hue, 0.85, 1.0), float)
        tint[m] = c
    lit = hit > 0
    outimg = base.copy()
    outimg[lit] = base[lit] * 0.55 + tint[lit] * 0.45
    im = Image.fromarray(np.clip(outimg, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    # PIL's built-in bitmap font has no arrow or backtick glyphs and draws them as
    # empty boxes, which reads as a missing label rather than a present one.
    SPELL = {"\u2191": "up", "\u2193": "down", "\u2190": "left", "\u2192": "right",
             "`": "tick", "\\": "bslash", "//": "slash"}
    for k in keys:
        ys, xs = np.nonzero(hit == k["id"])
        cx, cy = xs.mean(), ys.mean()
        label = SPELL.get(k["name"], k["name"])
        w = 6 * len(label)
        d.rectangle([cx - w / 2 - 2, cy - 8, cx + w / 2 + 2, cy + 7], fill=(0, 0, 0))
        d.text((cx - w / 2, cy - 6), label, fill=(255, 255, 255))
    im.save(OUT)
    print("\noverlay written -> %s" % OUT)
    print("   (regions tinted by LED id over the WHITE frame, labelled with the")
    print("    layout's own key names, for a cold-eyes check against the legends)")

    print()
    if fails:
        print("GATE 3 AUTOMATED FAIL: %s" % ", ".join(fails))
        sys.exit(1)
    print("GATE 3 AUTOMATED PASS: hitbox invariants hold in the shipped texture")


def hsv_to_rgb(h, s, v):
    c = v * s
    x = c * (1 - abs((h / 60.0) % 2 - 1))
    m = v - c
    seg = int(h // 60) % 6
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][seg]
    return ((r + m) * 255, (g + m) * 255, (b + m) * 255)


if __name__ == "__main__":
    main()
