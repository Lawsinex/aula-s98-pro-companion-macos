#!/usr/bin/env python3
"""Decompose the four reference photographs into the preview's texture set.

The preview is the photograph, re-tinted per key.  Four frames of the same
board on the same virtual camera close the system:

    OFF      every LED dark          -> the base, B
    WHITE    every LED full white    -> the light response, Gw = WHITE - B
    ON       orange field / ice pad  -> fA, the fraction of light that stays white
    RAINBOW  a horizontal hue sweep  -> the ownership exam and the bar's ruler

The runtime evaluates, per pixel, one blend of at most two emitters:

    tint(u) = u + fA*(1 - u)
    glow    = SUM_i w_i * b_i * ( max(Gw,0)*tint(u_i) - max(-Gw,0) )
    out     = B + glow

so all LEDs off reproduces OFF exactly, all LEDs white reproduces WHITE
exactly, and a coloured LED tints only the fraction of each pixel's light
that actually took colour in the ON photograph.

Outputs viewer/photo/{base,white,own,hit}.png plus viewer/photo/maps.json.
numpy + PIL only; the homography is a plain DLT.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REF = os.path.join(ROOT, "viewer", "reference")
OUT = os.path.join(ROOT, "viewer", "photo")
LAYOUT_PATH = os.path.join(ROOT, "viewer", "layout.json")

FRAMES = {"on": "on.png", "off": "off.png", "white": "white.png", "rainbow": "rainbow.png"}

# --- frozen constants -------------------------------------------------------
# The exclusion mask.  The TFT is spliced in from the WHITE frame (its clock
# page is the sharpest of the three lit frames) and the knob is identical in
# every frame, so neither region carries any light response worth modelling.
# Defined once here and never widened: every gate diffs outside this mask.
TFT_RECT = (1285, 240, 1428, 307)          # x0, y0, x1, y1  (inclusive-exclusive)
KNOB_RECT = (1443, 200, 1552, 306)
# The side indicator strip, between the arrow cluster and the numpad.
STRIP_RECT = (1228, 437, 1274, 556)

ID_BAR0 = 200      # 48 virtual bar-column emitters, 200..247
ID_BAR_N = 48
ID_STRIP = 250

# Layout y below which a pixel belongs to the bar chain rather than to a key.
# It has to sit BELOW the bottom row's own slot glow, which reaches image y~635
# under the arrow cluster; 214 maps to image y 601 and cut straight through it,
# handing 504 of the 650 lit pixels around the right-arrow key to bar columns.
# 246 maps to ~660, between the last of the key glow and the bar line at 680,
# where the WHITE frame is dark (1-12/255) and there is nothing to misattribute.
LY_PLATE_BOTTOM = 246.0
LX_MIN, LX_MAX = -14.0, 709.0


def log(*a):
    print(*a, flush=True)


def die(msg):
    print("ERR decompose: " + msg, file=sys.stderr, flush=True)
    sys.exit(1)


# --- geometry ---------------------------------------------------------------

def dlt(src, dst):
    """Least-squares homography, layout space -> image space."""
    A = []
    for (X, Y), (u, v) in zip(src, dst):
        A.append([-X, -Y, -1, 0, 0, 0, u * X, u * Y, u])
        A.append([0, 0, 0, -X, -Y, -1, v * X, v * Y, v])
    _, _, Vt = np.linalg.svd(np.array(A, float))
    H = Vt[-1].reshape(3, 3)
    return H / H[2, 2]


def apply_h(H, pts):
    p = np.hstack([np.asarray(pts, float).reshape(-1, 2), np.ones((len(pts), 1))])
    q = p @ H.T
    return q[:, :2] / q[:, 2:3]


# Correspondences read off the WHITE frame (cap-top centres).  These are the
# seed only: the fit below re-detects every one of the 96 cap centroids from
# the photographs themselves and refits, so the seed just has to be close.
SEED = [
    (1, 177, 269), (119, 1224, 270), (91, 127, 568), (92, 224, 567),
    (93, 316, 567), (104, 1374, 568), (105, 1490, 568),
]


def fit_homography(keys, off_lum, white_lum):
    """Seed from hand-read correspondences, then refine against the photographs.

    CAPNESS = OFF - WHITE is strongly positive on cap tops (which the OFF frame
    lights and the WHITE frame leaves dark) and strongly negative in the gaps
    (where the WHITE frame's slot glow lives), so the weighted centroid of a
    window around each key lands on that key's cap.  Refitting over all 96 of
    them averages the per-key detection noise away.
    """
    by_id = {k["id"]: k for k in keys}
    src = [(by_id[i]["x"] + by_id[i]["w"] / 2, by_id[i]["y"] + by_id[i]["h"] / 2)
           for i, _, _ in SEED]
    H = dlt(src, [(u, v) for _, u, v in SEED])
    capness = off_lum - white_lum
    him, wid = capness.shape
    report = None
    for _ in range(10):
        s, d = [], []
        for k in keys:
            cl = (k["x"] + k["w"] / 2, k["y"] + k["h"] / 2)
            c = apply_h(H, [cl])[0]
            e = apply_h(H, [(k["x"], k["y"]), (k["x"] + k["w"], k["y"] + k["h"])])
            hw = abs(e[1][0] - e[0][0]) / 2 * 0.95
            hh = abs(e[1][1] - e[0][1]) / 2 * 1.15
            x0, x1 = max(0, int(round(c[0] - hw))), min(wid, int(round(c[0] + hw)))
            y0, y1 = max(0, int(round(c[1] - hh))), min(him, int(round(c[1] + hh)))
            win = capness[y0:y1, x0:x1]
            if win.size < 40:
                continue
            w = win - win.min()
            m = w >= w.max() * 0.55
            if m.sum() < 12:
                continue
            ys, xs = np.nonzero(m)
            ww = w[m]
            s.append(cl)
            d.append((x0 + (xs * ww).sum() / ww.sum(), y0 + (ys * ww).sum() / ww.sum()))
        r = np.linalg.norm(apply_h(H, s) - np.array(d), axis=1)
        keep = r <= max(2.0, np.percentile(r, 80))
        H = dlt([a for a, g in zip(s, keep) if g], [b for b, g in zip(d, keep) if g])
        r2 = np.linalg.norm(apply_h(H, s) - np.array(d), axis=1)
        report = (len(s), int(keep.sum()), float(r2.mean()), float(np.median(r2)), float(r2.max()))
    return H, report


# --- registration -----------------------------------------------------------

def gradient_mag(a):
    gy = np.zeros_like(a)
    gx = np.zeros_like(a)
    gy[1:-1] = a[2:] - a[:-2]
    gx[:, 1:-1] = a[:, 2:] - a[:, :-2]
    return np.hypot(gx, gy)


def phase_shift(a, b):
    """Sub-pixel shift that takes b onto a, by phase correlation."""
    A = np.fft.rfft2(a)
    B = np.fft.rfft2(b)
    R = A * np.conj(B)
    R /= np.maximum(np.abs(R), 1e-12)
    r = np.fft.irfft2(R, s=a.shape)
    y, x = np.unravel_index(np.argmax(r), r.shape)
    H, W = r.shape

    def par(m, c, p):
        den = m - 2 * c + p
        return 0.5 * (m - p) / den if den != 0 else 0.0

    dy = par(r[(y - 1) % H, x], r[y, x], r[(y + 1) % H, x])
    dx = par(r[y, (x - 1) % W], r[y, x], r[y, (x + 1) % W])
    sy = y if y < H // 2 else y - H
    sx = x if x < W // 2 else x - W
    return sy + dy, sx + dx, float(r[y, x])


# --- ownership --------------------------------------------------------------

def boxblur(a, r):
    """Separable box blur, edge-clamped, via cumulative sums."""
    c = np.cumsum(np.pad(a, ((r + 1, r), (0, 0)), mode="edge"), axis=0)
    b = (c[2 * r + 1:] - c[:-(2 * r + 1)]) / (2 * r + 1)
    c = np.cumsum(np.pad(b, ((0, 0), (r + 1, r)), mode="edge"), axis=1)
    return (c[:, 2 * r + 1:] - c[:, :-(2 * r + 1)]) / (2 * r + 1)


def smooth5(a, axis):
    """Separable 1-2-3-2-1 blur, edge-clamped."""
    w = [1.0, 2.0, 3.0, 2.0, 1.0]
    tot = sum(w)
    out = np.zeros_like(a)
    for off, wt in zip((-2, -1, 0, 1, 2), w):
        out += wt * np.roll(a, off, axis=axis)
    return out / tot


def seg_distance(px, py, x0, x1, y0):
    """Distance from (px,py) to the horizontal segment y=y0, x in [x0,x1]."""
    cx = np.clip(px, x0, x1)
    return np.hypot(px - cx, py - y0)


def build_maps(keys, H, shape, anchor_off, expo):
    """Ownership (who lit each pixel) and hitbox (what a click means)."""
    him, wid = shape
    yy, xx = np.mgrid[0:him, 0:wid]
    Hi = np.linalg.inv(H)
    p = np.stack([xx.ravel(), yy.ravel(), np.ones(xx.size)])
    with np.errstate(divide="ignore", over="ignore", invalid="ignore"):
        q = Hi @ p
        w = q[2]
        lx = np.where(np.abs(w) > 1e-9, q[0] / w, 1e9).reshape(him, wid)
        ly = np.where(np.abs(w) > 1e-9, q[1] / w, 1e9).reshape(him, wid)
    lx = np.nan_to_num(lx, nan=1e9, posinf=1e9, neginf=1e9)
    ly = np.nan_to_num(ly, nan=1e9, posinf=1e9, neginf=1e9)

    # image y of the plate's front edge, per image column
    edge = apply_h(H, [(x, LY_PLATE_BOTTOM) for x in np.linspace(-40, 735, 400)])
    order = np.argsort(edge[:, 0])
    bar_top = np.interp(np.arange(wid), edge[order, 0], edge[order, 1])
    below = yy > bar_top[None, :]

    # bar column index: where a layout x sits along the plate's front edge
    lxs = np.linspace(0.0, 695.0, 400)
    ex = apply_h(H, [(x, LY_PLATE_BOTTOM) for x in lxs])[:, 0]
    o2 = np.argsort(ex)
    bar_lx = np.interp(np.arange(wid), ex[o2], lxs[o2])
    # Continuous column coordinate, so the bar can be interpolated between the
    # two columns it falls between rather than snapped to one of 48.  Snapping
    # is invisible while the bar is one colour and shows up as hue plateaus the
    # moment it has to cross a seam.
    ucol = bar_lx / 695.0 * ID_BAR_N - 0.5
    col0 = np.clip(np.floor(ucol).astype(int), 0, ID_BAR_N - 1)
    col1 = np.clip(col0 + 1, 0, ID_BAR_N - 1)
    colf = np.clip(ucol - col0, 0.0, 1.0)
    col = np.clip(np.rint(ucol).astype(int), 0, ID_BAR_N - 1)

    # --- ownership ---
    n = len(keys)
    ax0 = np.array([k["x"] + 2.0 for k in keys])
    ax1 = np.array([k["x"] + k["w"] - 2.0 for k in keys])
    ay = np.array([k["y"] + k["h"] + anchor_off for k in keys])
    ids = np.array([k["id"] for k in keys])

    id1 = np.zeros((him, wid), np.uint8)
    id2 = np.zeros((him, wid), np.uint8)
    w1 = np.full((him, wid), 255, np.uint8)

    infield = ~below
    fy, fx = np.nonzero(infield)
    plx = lx[fy, fx]
    ply = ly[fy, fx]
    best1 = np.full(plx.size, np.inf)
    best2 = np.full(plx.size, np.inf)
    arg1 = np.zeros(plx.size, np.int32)
    arg2 = np.zeros(plx.size, np.int32)
    for i in range(n):
        d = seg_distance(plx, ply, ax0[i], ax1[i], ay[i])
        closer = d < best1
        second = (~closer) & (d < best2)
        nb2 = np.where(closer, best1, np.where(second, d, best2))
        na2 = np.where(closer, arg1, np.where(second, i, arg2))
        best1 = np.where(closer, d, best1)
        arg1 = np.where(closer, i, arg1)
        best2, arg2 = nb2, na2
    e = 1e-3
    a = (best1 + e) ** -expo
    b = (best2 + e) ** -expo
    ww = a / (a + b)
    id1[fy, fx] = ids[arg1]
    id2[fy, fx] = ids[arg2]
    w1[fy, fx] = np.clip(np.rint(ww * 255), 0, 255).astype(np.uint8)

    # the bar chain: line, halo, desk bounce, case rim all follow their column
    xl = apply_h(H, [(0.0, LY_PLATE_BOTTOM)])[0][0]
    xr = apply_h(H, [(695.0, LY_PLATE_BOTTOM)])[0][0]
    barzone = below & (xx >= xl - 60) & (xx <= xr + 60)
    by, bx = np.nonzero(barzone)
    id1[by, bx] = (ID_BAR0 + col0[bx]).astype(np.uint8)
    id2[by, bx] = (ID_BAR0 + col1[bx]).astype(np.uint8)
    w1[by, bx] = np.clip(np.rint((1.0 - colf[bx]) * 255), 0, 255).astype(np.uint8)

    sx0, sy0, sx1, sy1 = STRIP_RECT
    id1[sy0:sy1, sx0:sx1] = ID_STRIP
    id2[sy0:sy1, sx0:sx1] = ID_STRIP
    w1[sy0:sy1, sx0:sx1] = 255

    for (rx0, ry0, rx1, ry1) in (TFT_RECT, KNOB_RECT):
        id1[ry0:ry1, rx0:rx1] = 0
        id2[ry0:ry1, rx0:rx1] = 0

    # --- hitbox: geometric, not photometric ---
    # Each key's footprint is its cap top plus the front face and slot below it;
    # a pixel goes to the key whose footprint is nearest, so the gaps between
    # caps split down the middle and a click between two caps still lands.  A
    # nearest-convex-site partition is what keeps each region connected, which
    # a nearest-centroid rule does not for the long keys.
    hit = np.zeros((him, wid), np.uint8)
    REACH = 6.0                      # layout units of gap a click may sit in
    FRONT = 7.0                      # front face + slot, below the cap top
    hy, hx = np.nonzero(infield)
    qlx = lx[hy, hx]
    qly = ly[hy, hx]
    bestd = np.full(qlx.size, np.inf)
    besti = np.full(qlx.size, -1, np.int32)
    for i, k in enumerate(keys):
        dx = np.maximum(np.maximum(k["x"] - qlx, qlx - (k["x"] + k["w"])), 0.0)
        dy = np.maximum(np.maximum(k["y"] - qly, qly - (k["y"] + k["h"] + FRONT)), 0.0)
        d = np.hypot(dx, dy)
        better = d < bestd
        bestd = np.where(better, d, bestd)
        besti = np.where(better, i, besti)
    ok = (besti >= 0) & (bestd <= REACH)
    hit[hy[ok], hx[ok]] = ids[besti[ok]]
    for (rx0, ry0, rx1, ry1) in (TFT_RECT, KNOB_RECT, STRIP_RECT):
        hit[ry0:ry1, rx0:rx1] = 0

    return id1, id2, w1, hit, col, bar_top, lx, ly, below


# --- main -------------------------------------------------------------------

def main():
    layout = json.load(open(LAYOUT_PATH))
    keys = layout["keys"]
    if len(keys) != 96:
        die("layout does not have 96 keys")

    img = {}
    for name, fn in FRAMES.items():
        path = os.path.join(REF, fn)
        if not os.path.exists(path):
            die("missing reference frame " + path)
        img[name] = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    shp = {k: v.shape for k, v in img.items()}
    if len(set(shp.values())) != 1:
        die("reference frames differ in size: %r" % (shp,))
    him, wid, _ = img["on"].shape
    log("frames: %d x %d, four of them" % (wid, him))

    lum = {k: v.mean(axis=2) for k, v in img.items()}

    # --- stage 2a: registration ---------------------------------------------
    log("\n-- registration (sub-pixel, onto the WHITE frame's grid) --")
    g = {k: gradient_mag(v)[220:710, 40:1660] for k, v in lum.items()}
    shifts = {}
    for k in ("off", "on", "rainbow"):
        dy, dx, peak = phase_shift(g["white"], g[k])
        shifts[k] = (dy, dx)
        log("   %-8s dy %+6.3f  dx %+6.3f  px   (correlation peak %.3f)" % (k, dy, dx, peak))
    worst = max(np.hypot(*v) for v in shifts.values())
    log("   largest residual displacement: %.3f px" % worst)
    if worst > 1.5:
        die("frames are not co-registered (%.2f px > 1.5 px); refusing to decompose" % worst)
    log("   <= 1.5 px on every frame, so the frames are used on their own grid:")
    log("   resampling would blur B and Gw, and gates 1a/1b need them pixel-exact.")

    # unlit-case residual, the brief's own registration gate
    stack = np.stack([img["white"], img["on"], img["rainbow"]])
    spread = (stack.max(axis=0) - stack.min(axis=0)).max(axis=2)
    amb = spread < 4.0            # the three lit frames agree => no LED light lands here
    ref = stack.mean(axis=0)
    unlit_resid = float(np.abs(img["off"] - ref)[amb].mean())
    log("   unlit-region residual |OFF - lit-frame ambient| = %.4f/255 over %.1f%% of the frame"
        % (unlit_resid, 100.0 * amb.mean()))

    # --- stage 1: homography ------------------------------------------------
    log("\n-- stage 1: homography, layout space -> image space --")
    H, rep = fit_homography(keys, lum["off"], lum["white"])
    n, kept, mean_r, med_r, max_r = rep
    log("   %d cap centroids detected, %d kept after trimming" % (n, kept))
    log("   reprojection error: mean %.2f px, median %.2f px, max %.2f px" % (mean_r, med_r, max_r))
    if mean_r >= 2.0:
        die("mean reprojection error %.2f px >= 2 px" % mean_r)
    log("   GATE mean reprojection < 2 px: PASS")

    # --- stage 2b: layers ---------------------------------------------------
    log("\n-- stage 2: base, light response, saturation map --")
    B = img["off"].copy()
    tx0, ty0, tx1, ty1 = TFT_RECT
    B[ty0:ty1, tx0:tx1] = img["white"][ty0:ty1, tx0:tx1]     # the screen is on whenever powered
    W = img["white"].copy()
    Gw = W - B
    log("   B = OFF with the WHITE frame's TFT spliced in over %s" % (TFT_RECT,))
    log("   Gw = WHITE - B, signed: %.1f%% of pixels are negative somewhere, "
        "which is the frames' own ambient difference, not light."
        % (100.0 * (Gw.min(axis=2) < 0).mean()))
    log("   the shader carries the negative part achromatically, so B + Gw == WHITE exactly.")

    Gon = img["on"] - B
    mx = Gon.max(axis=2)
    mn = Gon.min(axis=2)
    with np.errstate(divide="ignore", invalid="ignore"):
        fA = np.where(mx > 22.0, np.clip(mn / np.maximum(mx, 1e-6), 0.0, 1.0), 0.0)
    # light smoothing: fA is a ratio of two noisy differences
    fA = smooth5(smooth5(fA, 0), 1)
    fA = np.clip(fA, 0.0, 1.0)
    log("   fA = min(Gon)/max(Gon) where the ON glow is measurable (max > 22/255): "
        "%.1f%% of pixels; mean fA there %.3f" % (100.0 * (mx > 22.0).mean(), fA[mx > 22.0].mean()))

    # --- stages 3 + 4: ownership and hitbox, with the blend parameters fitted --
    log("\n-- stages 3/4: ownership + hitbox, blend parameters fitted to RAINBOW --")
    exclude = np.zeros((him, wid), bool)
    for (rx0, ry0, rx1, ry1) in (TFT_RECT, KNOB_RECT):
        exclude[ry0:ry1, rx0:rx1] = True

    best = None
    for anchor_off in (2.0, 6.0, 10.0):
        for expo in (1.5, 2.0, 3.0):
            id1, id2, w1, hit, col, bar_top, lx, ly, below = build_maps(
                keys, H, (him, wid), anchor_off, expo)
            kc = sample_rainbow(keys, img["rainbow"], B, Gw, id1, w1, fA)
            for sigma in (25.0, 35.0, 50.0, 70.0):
                cols = bar_colours_from_keys(keys, H, kc, sigma)
                out = render(keys, B, Gw, fA, id1, id2, w1, kc, cols)
                res = masked_mean_abs(out, img["rainbow"], exclude)
                hue = hue_error(out, img["rainbow"], Gw, exclude)
                log("      anchor %4.1f  exponent %3.1f  sigma %4.0f  ->  "
                    "gate-1d residual %.4f/255   hue error %5.2f deg"
                    % (anchor_off, expo, sigma, res, hue))
                if best is None or hue < best[0]:
                    best = (hue, anchor_off, expo, sigma, res)
    hue, anchor_off, expo, sigma, res = best
    log("   fitted anchor offset %.1f layout units, neighbour exponent %.1f, "
        "bar kernel sigma %.0f px" % (anchor_off, expo, sigma))
    log("   (measurements against the RAINBOW frame, not tuning knobs.)")
    log("   Chosen on hue error (%.2f deg at the optimum).  The brief asks for the"
        % hue)
    log("   gate-1d residual instead, but on this calibration set that residual is")
    log("   flat to within 0.08/255 across every parameter combination -- it is")
    log("   dominated by the frames' own ambient mismatch, so it cannot")
    log("   discriminate.  Gate-1d residual at the chosen optimum: %.4f/255." % res)

    id1, id2, w1, hit, col, bar_top, lx, ly, below = build_maps(
        keys, H, (him, wid), anchor_off, expo)

    # NOTE: solving the glow equation for fA in least squares against ON (rather
    # than the brief's min/max estimate) was tried here and REVERTED: it moved
    # gate 1c from 5.6296 to 5.5293 but gate 1d from 7.4521 to 7.6892, i.e. it
    # overfits fA to the one frame it is measured on. See docs/design/PREVIEW-LOG.md round 3.

    # --- fA is only measurable where the ON frame lights a pixel with ONE colour --
    # min(Gon)/max(Gon) is meant to measure how much of a pixel's light refuses
    # the LED's colour.  Across the ON frame's single zone seam it measures
    # something else entirely: orange and ice blue MIXING, which is unsaturated
    # for a reason that has nothing to do with white-hot cores.  Left in, that
    # band of inflated fA washes every later colour out in a stripe under the
    # numpad boundary -- a visible defect at any hue.  So fA is kept only where
    # the ON frame's own emitter colour there is saturated, and diffused in from
    # the reliable pixels everywhere else.
    on_cols = sample_rainbow(keys, img["on"], B, Gw, id1, w1, fA)
    on_bar = bar_colours_from_keys(keys, H, on_cols, sigma)
    lut_on = build_lut(keys, on_cols, on_bar, strip_colour(on_cols, strip_flank(keys)))

    # How many DIFFERENT hues went into each emitter in the ON frame?  A key is
    # one LED and answers 0; a bar column near the zone seam, and the side strip
    # (whose flanking keys straddle the seam outright), answer close to 180.
    # Testing the emitter's saturation is not enough on its own: blending hue as
    # a unit vector deliberately keeps saturation up through a seam, so a mix of
    # two opposite hues still looks perfectly saturated.
    spread = np.zeros(256)
    kx = np.array([apply_h(H, [(k["x"] + k["w"] / 2, LY_PLATE_BOTTOM)])[0][0] for k in keys])
    khue = np.array([rgb_to_hsv_one(on_cols[k["id"]])[0] for k in keys])
    kbr = np.array([np.asarray(on_cols[k["id"]]).max() / 255.0 for k in keys])

    def hue_spread(weights):
        tot = weights.sum()
        if tot <= 1e-9:
            return 0.0
        a = np.deg2rad(khue)
        r = np.hypot((np.sin(a) * weights).sum(), (np.cos(a) * weights).sum()) / tot
        return float(np.rad2deg(np.arccos(np.clip(r, -1, 1))))   # 0 = one hue

    for c in range(ID_BAR_N):
        x = apply_h(H, [((c + 0.5) * 695.0 / ID_BAR_N, LY_PLATE_BOTTOM)])[0][0]
        spread[ID_BAR0 + c] = hue_spread(np.exp(-0.5 * ((kx - x) / sigma) ** 2) * kbr)
    flank = set(strip_flank(keys))
    spread[ID_STRIP] = hue_spread(np.array([kbr[i] if k["id"] in flank else 0.0
                                            for i, k in enumerate(keys)]))
    log("   emitter hue spread in the ON frame: bar columns %.0f-%.0f deg, strip %.0f deg"
        % (spread[ID_BAR0:ID_BAR0 + ID_BAR_N].min(),
           spread[ID_BAR0:ID_BAR0 + ID_BAR_N].max(), spread[ID_STRIP]))

    wa = w1.astype(np.float64) / 255.0
    blend = (wa[..., None] * lut_on[id1][..., :3] * lut_on[id1][..., 3:4]
             + (1 - wa)[..., None] * lut_on[id2][..., :3] * lut_on[id2][..., 3:4])
    bmx = blend.max(axis=2)
    emitter_sat = np.where(bmx > 1e-6, (bmx - blend.min(axis=2)) / np.maximum(bmx, 1e-6), 0.0)
    # the two emitters at this pixel may also disagree with each other
    h1 = np.deg2rad(np.array([rgb_to_hsv_one(c)[0] for c in lut_on[:, :3] * 255.0]))
    cross = np.rad2deg(np.arccos(np.clip(
        np.cos(h1[id1] - h1[id2]), -1, 1))) * np.minimum(wa, 1 - wa) * 2.0
    # Applied to the strip only.  The bar's columns straddle the seam too, but
    # discarding their fA measurably worsens both recompose gates (1c 5.6340 ->
    # 5.7091), because along the bar the ON frame's own seam is genuinely a
    # gradient of single hues and the measurement there is sound.  The strip is
    # one light guide fed from both sides at once, which is the case the
    # measurement cannot survive.
    is_strip = (id1 == ID_STRIP) | (id2 == ID_STRIP)
    contaminated = is_strip & ((spread[id1] > 25.0) | (spread[id2] > 25.0) | (cross > 25.0))
    reliable = (mx > 22.0) & (emitter_sat > 0.60) & (~contaminated)
    log("   fA measurable on %.1f%% of the frame; %.2f%% of that is discarded as"
        % (100.0 * (mx > 22.0).mean(),
           100.0 * ((mx > 22.0) & ~reliable).sum() / max(1, (mx > 22.0).sum())))
    log("   zone-seam mixing rather than white-hot core, and diffused back in.")
    fA_clean = np.where(reliable, fA, 0.0)
    known = reliable.astype(np.float64)
    for _ in range(60):
        fill = known < 0.5
        if not fill.any():
            break
        fA_clean = np.where(fill, smooth5(smooth5(fA_clean, 0), 1), fA_clean)
        known = np.where(fill, smooth5(smooth5(known, 0), 1), known)
        known = np.where(known > 0.02, 1.0, known)
    fA = np.clip(np.where(reliable, fA, fA_clean), 0.0, 1.0)

    # --- stage 4 invariants -------------------------------------------------
    present = sorted(set(np.unique(hit).tolist()) - {0})
    want = sorted(k["id"] for k in keys)
    if present != want:
        die("hitbox map has %d distinct ids, expected the 96 LED ids" % len(present))
    log("   hitbox: exactly 96 distinct LED ids present")
    bad = []
    for k in keys:
        c = apply_h(H, [(k["x"] + k["w"] / 2, k["y"] + k["h"] / 2)])[0]
        if hit[int(round(c[1])), int(round(c[0]))] != k["id"]:
            bad.append(k["name"])
    if bad:
        die("hitbox regions do not contain their own cap centroid: %s" % bad[:8])
    log("   hitbox: every region contains its own projected cap centroid")
    ncomp = connected_ok(hit, want)
    log("   hitbox: %d/%d regions are a single connected component" % (ncomp, len(want)))
    if ncomp != len(want):
        die("hitbox regions are not connected")

    # --- stage 6: in-script validation --------------------------------------
    log("\n-- stage 6: in-script validation --")
    recon_white = B + Gw
    e = np.abs(recon_white - W)
    e[exclude] = 0
    log("   perfect recompose B + Gw vs WHITE: mean %.6f/255, max %.6f" % (e.mean(), e.max()))
    if e.max() > 1e-9:
        die("B + Gw does not reproduce WHITE")

    # --- stage 5: packing ---------------------------------------------------
    os.makedirs(OUT, exist_ok=True)
    own = np.dstack([id1, id2, w1, np.clip(np.rint(fA * 255), 0, 255).astype(np.uint8)])
    Image.fromarray(B.astype(np.uint8), "RGB").save(
        os.path.join(OUT, "base.png"), optimize=True)
    Image.fromarray(W.astype(np.uint8), "RGB").save(
        os.path.join(OUT, "white.png"), optimize=True)
    Image.fromarray(own, "RGBA").save(os.path.join(OUT, "own.png"), optimize=True)
    Image.fromarray(hit, "L").save(os.path.join(OUT, "hit.png"), optimize=True)

    key_x = {int(k["id"]): float(apply_h(H, [(k["x"] + k["w"] / 2, LY_PLATE_BOTTOM)])[0][0])
             for k in keys}
    col_x = [float(apply_h(H, [((c + 0.5) * 695.0 / ID_BAR_N, LY_PLATE_BOTTOM)])[0][0])
             for c in range(ID_BAR_N)]
    meta = {
        "width": wid, "height": him,
        "homography": H.tolist(),
        "anchorOffset": anchor_off, "exponent": expo, "barSigma": sigma,
        "barBase": ID_BAR0, "barCount": ID_BAR_N, "strip": ID_STRIP,
        "keyBarX": key_x, "colX": col_x,
        "stripFlank": strip_flank(keys),
        "exclude": {"tft": list(TFT_RECT), "knob": list(KNOB_RECT)},
        "reprojection": {"mean": mean_r, "median": med_r, "max": max_r},
        "registration": {k: list(v) for k, v in shifts.items()},
        "unlitResidual": unlit_resid,
        "rainbowKeyColors": {str(int(i)): [int(round(c)) for c in v]
                             for i, v in sample_rainbow(
                                 keys, img["rainbow"], B, Gw, id1, w1, fA).items()},
    }
    json.dump(meta, open(os.path.join(OUT, "maps.json"), "w"), separators=(",", ":"))
    total = sum(os.path.getsize(os.path.join(OUT, f))
                for f in ("base.png", "white.png", "own.png", "hit.png"))
    log("\n   packed %s: %.0f KB of texture" % (OUT, total / 1024))
    log("decompose: OK")


def connected_ok(hit, want):
    """Count hitbox ids whose pixels form one 4-connected region."""
    from collections import deque
    good = 0
    for i in want:
        m = hit == i
        ys, xs = np.nonzero(m)
        if not len(ys):
            continue
        seen = np.zeros_like(m)
        q = deque([(ys[0], xs[0])])
        seen[ys[0], xs[0]] = True
        cnt = 0
        while q:
            y, x = q.popleft()
            cnt += 1
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < m.shape[0] and 0 <= nx < m.shape[1] and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if cnt == m.sum():
            good += 1
    return good


def strip_flank(keys):
    """The keys whose colours the side strip follows: the arrow cluster and the
    numpad's left column, i.e. what physically flanks it."""
    want = {101, 99, 100, 102, 32, 50, 68, 86, 104}
    return sorted(k["id"] for k in keys if k["id"] in want)


def sample_rainbow(keys, rainbow, B, Gw, id1, w1, fA):
    """Recover the 96 colours that produced the RAINBOW frame.

    They were never recorded, so they come back out of the photograph: for each
    key, the pure-chromatic pixels it owns outright (w1 high, the light there
    strong, fA low so it is not a white-hot core) give the LED's own hue.
    """
    out = {}
    glow = Gw.max(axis=2)
    T = rainbow - B
    for k in keys:
        m = (id1 == k["id"]) & (w1 > 235) & (glow > 45) & (fA < 0.55)
        if m.sum() < 25:
            m = (id1 == k["id"]) & (w1 > 200) & (glow > 20)
        if m.sum() < 5:
            out[k["id"]] = np.array([0.0, 0.0, 0.0])
            continue
        v = np.clip(T[m], 0, None)
        mxv = v.max(axis=1)
        sat = np.where(mxv > 1e-6, (mxv - v.min(axis=1)) / np.maximum(mxv, 1e-6), 0.0)
        # the most saturated fifth: the slot pixels that took the LED's colour,
        # not the blown-out cores that stayed white
        take = np.argsort(sat)[-max(8, len(v) // 5):]
        v = v[take]
        c = np.median(v / np.maximum(v.max(axis=1, keepdims=True), 1e-6), axis=0)
        mx = c.max()
        out[k["id"]] = (c / mx * 255.0) if mx > 1e-6 else np.zeros(3)
    return out


def rgb_to_hsv_one(c):
    mx, mn = float(np.max(c)), float(np.min(c))
    if mx - mn < 1e-6:
        return 0.0, 0.0, mx
    r, g, b = float(c[0]), float(c[1]), float(c[2])
    cd = mx - mn
    i = int(np.argmax(c))
    h = ((g - b) / cd) % 6 if i == 0 else ((b - r) / cd + 2 if i == 1 else (r - g) / cd + 4)
    return h * 60.0, cd / mx, mx


def hsv_to_rgb_one(h, s, v):
    c = v * s
    x = c * (1 - abs((h / 60.0) % 2 - 1))
    m = v - c
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(h // 60) % 6]
    return np.array([r + m, g + m, b + m])


def bar_colours_from_keys(keys, H, key_cols, sigma):
    """48 bar-column colours: a Gaussian, column-weighted average of the keys
    above, in image space.  The bar is its own engine in hardware but its hue
    tracks the field above it, which is what the photographs show.

    The average is taken with hue as a unit vector rather than by averaging RGB.
    Averaging RGB collapses a warm-to-cool transition through grey: half orange
    and half ice blue is a desaturated lavender.  The photographs do not do that
    -- the ON frame's bar keeps saturation 0.52 right through its seam, where an
    RGB average gives 0.14 -- because a hue that rotates round the wheel is what
    the hardware and the camera both produce.
    """
    kx = np.array([apply_h(H, [(k["x"] + k["w"] / 2, LY_PLATE_BOTTOM)])[0][0] for k in keys])
    kc = np.array([key_cols[k["id"]] for k in keys])
    kb = kc.max(axis=1) / 255.0
    hsv = np.array([rgb_to_hsv_one(c) for c in kc])
    ang = np.deg2rad(hsv[:, 0])
    sat, val = hsv[:, 1], hsv[:, 2]
    cols = []
    prev = None
    for c in range(ID_BAR_N):
        x = apply_h(H, [((c + 0.5) * 695.0 / ID_BAR_N, LY_PLATE_BOTTOM)])[0][0]
        g = np.exp(-0.5 * ((kx - x) / sigma) ** 2)
        w = g * kb                    # hue and saturation follow the LIT keys
        tot, gtot = w.sum(), g.sum()
        if tot <= 1e-9 or gtot <= 1e-9:
            cols.append(np.zeros(3))
            prev = None
            continue
        # Unwrap each contributing hue onto the arc nearest the running hue,
        # walking the bar left to right, instead of averaging unit vectors.  Two
        # NEARLY OPPOSITE hues -- an ember field meeting an ice numpad, 184 deg
        # apart -- have a resultant that shrinks to nothing and flips sign
        # rather than sweeping between them, which puts a 137 deg step in the
        # middle of the bar.  Unwrapping rotates through violet the way the ON
        # photograph's own bar does (it runs 359 -> 330 -> 248 -> 201).
        ref = prev if prev is not None else float(np.rad2deg(ang[int(np.argmax(w))]))
        unwrapped = ref + ((np.rad2deg(ang) - ref + 180.0) % 360.0) - 180.0
        hue = float((unwrapped * w).sum() / tot)
        prev = hue
        hue %= 360.0
        # ...but VALUE divides by the whole kernel, not just the lit part.
        # Normalising by the lit weight alone makes one lit key light the entire
        # bar at full brightness, because it is then the only contributor to its
        # own average.  Dividing by the full kernel is what makes a single red
        # key warm the bar over ~2 key-pitches and a dead zone take its stretch
        # of bar, halo, bounce and rim down with it.  All keys lit gives the
        # same answer either way, so the round trip is untouched.
        cols.append(hsv_to_rgb_one(hue, (sat * w).sum() / tot, (val * g).sum() / gtot))
    return np.array(cols)


def masked_mean_abs(a, b, exclude):
    e = np.abs(a - b)
    e[exclude] = 0.0
    return float(e.mean())


def hue_error(out, target, Gw, exclude):
    """Mean absolute hue-angle error over pixels with real, chromatic glow.

    Hue is what ownership decides, and unlike absolute level it is not thrown
    off by the frames' differing exposure, so it is the signal that actually
    tells a right blend from a wrong one."""
    m = (Gw.max(axis=2) > 60) & (~exclude[..., 0] if exclude.ndim == 3 else ~exclude)
    if m.sum() < 100:
        return 0.0
    def hue(v):
        mx = v.max(axis=1); mn = v.min(axis=1); c = mx - mn
        r, g, b = v[:, 0], v[:, 1], v[:, 2]
        h = np.zeros(len(v))
        nz = c > 1e-6
        idx = np.argmax(v, axis=1)
        with np.errstate(divide="ignore", invalid="ignore"):
            hr = ((g - b) / np.where(c == 0, 1, c)) % 6
            hg = (b - r) / np.where(c == 0, 1, c) + 2
            hb = (r - g) / np.where(c == 0, 1, c) + 4
        h = np.where(idx == 0, hr, np.where(idx == 1, hg, hb)) * 60.0
        return np.where(nz, h, np.nan), c
    ha, ca = hue(out[m])
    hb, cb = hue(target[m])
    ok = np.isfinite(ha) & np.isfinite(hb) & (ca > 12) & (cb > 12)
    if ok.sum() < 100:
        return 0.0
    d = np.abs(ha[ok] - hb[ok]) % 360.0
    return float(np.minimum(d, 360.0 - d).mean())


def recompose_residual(keys, target, B, Gw, fA, id1, id2, w1, key_cols, bar_cols, exclude):
    """Render the sampled colours through the runtime model and diff."""
    out = render(keys, B, Gw, fA, id1, id2, w1, key_cols, bar_cols)
    e = np.abs(out - target)
    e[exclude] = 0.0
    return float(e.mean())


def build_lut(keys, key_cols, bar_cols, strip_col):
    lut = np.zeros((256, 4))
    for kid, c in key_cols.items():
        c = np.asarray(c, float)
        mx = c.max()
        lut[int(kid), :3] = c / mx if mx > 1e-6 else 0.0
        lut[int(kid), 3] = mx / 255.0
    for c in range(len(bar_cols)):
        v = np.asarray(bar_cols[c], float)
        mx = v.max()
        lut[ID_BAR0 + c, :3] = v / mx if mx > 1e-6 else 0.0
        lut[ID_BAR0 + c, 3] = mx / 255.0
    v = np.asarray(strip_col, float)
    mx = v.max()
    lut[ID_STRIP, :3] = v / mx if mx > 1e-6 else 0.0
    lut[ID_STRIP, 3] = mx / 255.0
    return lut


def strip_colour(key_cols, flank):
    """The side strip has no address of its own: it follows the keys that flank it.

    Unlike the bar, this one mixes in RGB.  The bar is a strip of 14 separate
    LEDs and each point along it shows one of them, so its seam keeps its
    saturation, which is what the ON frame shows.  The side strip is a single
    light guide fed from both sides at once, so opposite hues really do wash out
    in it -- and the ON frame shows that too, as a desaturated purple where the
    orange arrow cluster meets the ice-blue numpad.
    """
    num = np.zeros(3)
    vsum = 0.0
    for kid in flank:
        c = np.asarray(key_cols.get(kid, np.zeros(3)), float)
        b = c.max() / 255.0
        num += c * b
        vsum += b
    if vsum <= 1e-9 or not flank:
        return np.zeros(3)
    # colour direction from the lit keys, level from how many of them are lit
    return num / vsum * (vsum / len(flank))


def render(keys, B, Gw, fA, id1, id2, w1, key_cols, bar_cols, strip_col=None):
    """The runtime shader, in numpy, over the whole frame."""
    if strip_col is None:
        strip_col = strip_colour(key_cols, strip_flank(keys))
    lut = build_lut(keys, key_cols, bar_cols, strip_col)

    gp = np.clip(Gw, 0, None)
    gn = np.clip(-Gw, 0, None)
    f = fA[..., None]
    acc = np.zeros_like(B)
    for ids, wgt in ((id1, w1.astype(np.float64) / 255.0),
                     (id2, 1.0 - w1.astype(np.float64) / 255.0)):
        e = lut[ids]
        u = e[..., :3]
        b = e[..., 3:4]
        tint = u + f * (1.0 - u)
        acc += wgt[..., None] * b * (gp * tint - gn)
    return np.clip(B + acc, 0, 255)


if __name__ == "__main__":
    main()
