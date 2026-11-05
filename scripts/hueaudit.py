#!/usr/bin/env python3
"""Gate 2 — the hue audit.

The round trip proves the preview reproduces four particular photographs. This
proves it stays faithful all the way round the colour wheel, which no amount of
reproducing four frames can show.

Twelve hues at 30 degree steps at full saturation and value, plus white and a
mid grey. For each frame: render it through the real preview, sample the pure
chromatic pixels each key owns outright (w1 > 0.9, saturated, fA low, so the
white-hot cores are skipped -- they are white by design) and take the hue.

  per frame  |mean hue - sent hue| <= 4 deg
  per key    no key deviates from its frame's mean by more than 3 deg
  bar        every lit column within 4 deg of the frame's hue
  grey/white brightness monotone
  RAINBOW    the 48 bar columns sweep hue monotonically
"""

import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "viewer", "photo", "maps.json")

# Immutable thresholds.
TOL_FRAME_HUE = 4.0
TOL_KEY_HUE = 3.0
TOL_BAR_HUE = 4.0


def app_binary():
    return os.environ.get("AULA_APP") or os.path.join(
        ROOT, "build", "release", "Aula S98 Pro Companion.app", "Contents", "MacOS", "Aula S98 Pro Companion")


def render(out_path, colour=None, rainbow=False):
    env = dict(os.environ)
    env.update({"AULA_SNAPSHOT": "1", "AULA_SNAPSHOT_PANEL": "keyboard3d",
                "AULA_SNAPSHOT_OUT": out_path, "AULA_KB_EFFECT": ""})
    for k in ("AULA_KB_RAINBOW", "AULA_KB_ZONES", "AULA_KB_OFF", "AULA_KB_FRAME",
              "AULA_KB_COLOUR"):
        env.pop(k, None)
    if rainbow:
        env["AULA_KB_RAINBOW"] = "1"
    else:
        env["AULA_KB_COLOUR"] = "%02X%02X%02X" % colour
    subprocess.run([app_binary()], env=env, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    if not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
        print("ERR hueaudit: the preview did not render", file=sys.stderr)
        sys.exit(1)
    return np.asarray(Image.open(out_path).convert("RGB")).astype(np.float64)


def hsv(rgb):
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    c = mx - mn
    idx = np.argmax(rgb, axis=-1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cd = np.where(c == 0, 1.0, c)
    h = np.where(idx == 0, ((g - b) / cd) % 6,
                 np.where(idx == 1, (b - r) / cd + 2, (r - g) / cd + 4)) * 60.0
    s = np.where(mx > 0, c / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def circ_mean(h):
    a = np.deg2rad(h)
    return float(np.rad2deg(np.arctan2(np.sin(a).mean(), np.cos(a).mean())) % 360.0)


def hue_delta(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def hsv_to_rgb(h, s=1.0, v=1.0):
    c = v * s
    x = c * (1 - abs((h / 60.0) % 2 - 1))
    m = v - c
    seg = int(h // 60) % 6
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][seg]
    return (int(round((r + m) * 255)), int(round((g + m) * 255)), int(round((b + m) * 255)))


def main():
    with tempfile.TemporaryDirectory(prefix="aula-hueaudit.") as tmp:
        run(tmp)


def run(tmp):
    meta = json.load(open(MAPS))
    own = np.asarray(Image.open(os.path.join(ROOT, "viewer", "photo", "own.png")))
    id1, w1, fA = own[..., 0], own[..., 2], own[..., 3] / 255.0
    key_ids = sorted(int(k) for k in meta["rainbowKeyColors"])
    bar0, barn = meta["barBase"], meta["barCount"]

    failures = []

    print("hue sweep: 12 hues at 30 degree steps, full saturation and value")
    print("  %-5s %-14s %8s %8s %7s   %s" % ("hue", "sent", "frame", "err", "worstkey", ""))
    for step in range(12):
        want = step * 30.0
        colour = hsv_to_rgb(want)
        img = render(os.path.join(tmp, "h%03d.png" % int(want)), colour=colour)
        h, s, v = hsv(img)
        hues = []
        worst = 0.0
        worst_key = None
        for kid in key_ids:
            m = (id1 == kid) & (w1 > 229) & (fA < 0.55) & (s > 0.35) & (v > 40)
            if m.sum() < 30:
                continue
            hues.append((kid, circ_mean(h[m])))
        if len(hues) < 80:
            print("ERR hueaudit: only %d keys had samplable chromatic pixels" % len(hues),
                  file=sys.stderr)
            sys.exit(1)
        frame_hue = circ_mean(np.array([x for _, x in hues]))
        ferr = hue_delta(frame_hue, want)
        for kid, kh in hues:
            d = hue_delta(kh, frame_hue)
            if d > worst:
                worst, worst_key = d, kid
        # bar columns
        bad_bar = 0
        for c in range(barn):
            m = (id1 == bar0 + c) & (s > 0.35) & (v > 40)
            if m.sum() < 30:
                continue
            if hue_delta(circ_mean(h[m]), frame_hue) > TOL_BAR_HUE:
                bad_bar += 1
        ok = ferr <= TOL_FRAME_HUE and worst <= TOL_KEY_HUE and bad_bar == 0
        if not ok:
            failures.append("hue %.0f" % want)
        print("  %-5.0f %-14s %8.2f %8.2f %7.2f (led %-3s) bar off %d  %s"
              % (want, str(colour), frame_hue, ferr, worst, worst_key, bad_bar,
                 "PASS" if ok else "FAIL"))

    print("\nbrightness monotonicity: white vs mid grey")
    wimg = render(os.path.join(tmp, "w.png"), colour=(255, 255, 255))
    gimg = render(os.path.join(tmp, "g.png"), colour=(128, 128, 128))
    lit = (id1 > 0) & (w1 > 229)
    wl = float(wimg[lit].mean())
    gl = float(gimg[lit].mean())
    mono = gl < wl
    print("  white mean %.2f, grey mean %.2f over lit pixels -> %s"
          % (wl, gl, "monotone PASS" if mono else "FAIL"))
    if not mono:
        failures.append("brightness monotonicity")

    print("\nRAINBOW: do the 48 bar columns sweep hue monotonically?")
    rimg = render(os.path.join(tmp, "r.png"), rainbow=True)
    h, s, v = hsv(rimg)
    seq = []
    for c in range(barn):
        m = (id1 == bar0 + c) & (s > 0.3) & (v > 30)
        if m.sum() >= 30:
            seq.append(circ_mean(h[m]))
    unwrapped = [seq[0]]
    for x in seq[1:]:
        prev = unwrapped[-1]
        cand = x + 360.0 * round((prev - x) / 360.0)
        while cand < prev - 180:
            cand += 360
        while cand > prev + 180:
            cand -= 360
        unwrapped.append(cand)
    diffs = np.diff(unwrapped)
    backsteps = int((diffs < -1.0).sum())
    print("  %d columns sampled, total sweep %.1f deg, %d backward steps -> %s"
          % (len(seq), unwrapped[-1] - unwrapped[0], backsteps,
             "PASS" if backsteps == 0 else "FAIL"))
    if backsteps:
        failures.append("bar sweep monotonicity")

    print()
    if failures:
        print("GATE 2 FAIL: %s" % ", ".join(failures))
        sys.exit(1)
    print("GATE 2 PASS: hue is faithful all the way round the wheel")


if __name__ == "__main__":
    main()
