"""Can the slack in gates 1a/1b buy gates 1c/1d?

Gw is WHITE - B by construction, so gate 1a is exactly 0 whatever base B is
chosen and only gate 1b's 2.5/255 budget constrains B.  Spend that budget
optimally -- choosing B FREELY per pixel and per channel, which no real pipeline
can do -- and ask what 1c and 1d can then reach together.
"""
import json, numpy as np
from PIL import Image

meta = json.load(open('viewer/photo/maps.json'))
B0 = np.asarray(Image.open('viewer/photo/base.png')).astype(np.float64)
W  = np.asarray(Image.open('viewer/photo/white.png')).astype(np.float64)
N  = np.asarray(Image.open('viewer/reference/on.png').convert('RGB')).astype(np.float64)
R  = np.asarray(Image.open('viewer/reference/rainbow.png').convert('RGB')).astype(np.float64)
him, wid, _ = B0.shape
exc = np.zeros((him, wid), bool)
for k in ('tft', 'knob'):
    x0, y0, x1, y1 = meta['exclude'][k]; exc[y0:y1, x0:x1] = True
m = (~exc)[..., None] & np.ones((1, 1, 3), bool)
o, w, n, r = B0[m], W[m], N[m], R[m]
Ntot = o.size

def dseg(x, a, b):
    lo = np.minimum(a, b); hi = np.maximum(a, b)
    return np.maximum(0.0, np.maximum(lo - x, x - hi))

cands = np.stack([o, n, r, w])

def solve(lam, alpha, beta):
    best = None; sel = None
    for i, b in enumerate(cands):
        c = lam*np.abs(b-o) + alpha*dseg(n, b, w) + beta*dseg(r, b, w)
        if best is None:
            best = c.copy(); sel = np.zeros(c.shape, np.int8)
        k = c < best
        best[k] = c[k]; sel[k] = i
    b = np.choose(sel, cands)
    return (np.abs(b-o).mean(), dseg(n, b, w).mean(), dseg(r, b, w).mean())

print("Spending gate 1b's budget optimally, with a per-pixel-free base:")
print(f"  {'weight on 1c':>12} {'weight on 1d':>12} {'1b |B-OFF|':>11} {'1c':>8} {'1d':>8}   feasible?")
best_feasible = None
for alpha, beta in ((1,0), (0,1), (1,1), (2,1), (1,2), (3,1), (1,3)):
    lo, hi = 0.0, 40.0
    for _ in range(60):                      # bisect lambda to land on 1b == 2.5
        mid = (lo+hi)/2
        f, g, h = solve(mid, alpha, beta)
        if f > 2.5: lo = mid
        else: hi = mid
    f, g, h = solve(hi, alpha, beta)
    ok = (g <= 2.5) and (h <= 3.0)
    if ok: best_feasible = (alpha, beta, f, g, h)
    print(f"  {alpha:12d} {beta:12d} {f:11.4f} {g:8.4f} {h:8.4f}   {'YES' if ok else 'no'}")
print()
if best_feasible is None:
    print("No allocation of gate 1b's entire budget makes 1c and 1d pass together,")
    print("even with a base chosen freely per pixel and per channel.")
else:
    print("A feasible allocation EXISTS on mean-abs:", best_feasible)
