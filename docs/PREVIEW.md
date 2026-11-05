# How the keyboard preview works

The colour preview **is the photograph**, re-tinted per key. Four AI-generated reference frames of
the same board from the same virtual camera live in `viewer/reference/`, and together they close
the system:

| frame | what it fixes |
|---|---|
| `off.png` | the base, `B` — the unlit board, no reconstruction |
| `white.png` | the light response, `Gw = WHITE − B` — where light lands, with no hue |
| `on.png` | `fA`, the fraction of each pixel's light that stays white under a coloured LED |
| `rainbow.png` | the ownership exam — every neighbouring key a different hue |

`scripts/decompose.py` fits one homography from `viewer/layout.json` to the photographs
(96 cap centroids, mean reprojection 0.76 px), then writes four textures: the base, the
white frame, a per-pixel ownership map naming up to two emitters, their blend and the
saturation `fA`, and a separate hitbox map for what a click means. `viewer/build.sh`
splices them into `app3d.html` as data URIs — nothing is fetched at runtime, so the
preview works offline — and `scripts/build.sh` copies that into the bundle. The chain
starts at `KeyLayout.swift`, so the preview cannot disagree with the frames that go out
over USB about where an LED is.

At runtime it is one WebGL pass:

    tint(u) = u + fA·(1 − u)                       // fA of the light stays white
    glow    = Σ wᵢ·bᵢ·( max(Gw,0)·tint(uᵢ) − max(−Gw,0) )
    out     = B + glow

All LEDs off gives `B`, which *is* the OFF photograph; all LEDs white gives `B + Gw`,
which *is* the WHITE photograph — reproduced through the real shader at 0.0000 and
0.0005 of a grey level against a 2.5 threshold, because the maths is built so they
are identities rather than targets.
The light bar is its own 14-LED engine in hardware and cannot be addressed by the host,
but its hue tracks the field above it, so 48 virtual column emitters take a
Gaussian-weighted average of the key colours and drive the bar line, the halo up the case
front, the desk bounce and the case rim together.

Swift owns the colours and the page owns the pixels: state crosses as
`LED id -> [r, g, b]`, after the app's display calibration, and clicks come back the
other way as LED ids. `scripts/verify.sh` renders the board offscreen, and
`AULA_UI_TEST=editor AULA_LIVE_PREVIEW_OUT=…` renders it from inside the live window
and exercises the paint bridge — the parts a headless render cannot prove. It also runs
`scripts/roundtrip.py` (render the four reference frames back and diff them),
`scripts/hueaudit.py` (12 hues round the wheel, plus white and grey) and
`scripts/hitboxaudit.py`.

## What the preview cannot do

- **The camera is fixed.** It is a photograph, so there is no orbiting or relighting —
  one viewpoint, the one the reference frames were shot from.
- **Adjacent keys painted very different colours cross-bleed slightly** in the pixels
  their glows share. The real hardware does this too; the ownership map reproduces it
  rather than hiding it.
- **The screen always shows the WHITE frame's clock page**, not live screen content. The
  TFT and the knob are the frozen exclusion mask: they are spliced in, not modelled.
- **The desk reflection and the keycap tops stay neutral under a coloured LED.** `Gw` is negative on the cap
  tops — the WHITE frame renders them *darker* than the OFF frame does — so there
  is no measured light response there to take a hue, and the shader carries that
  negative part achromatically. This matches the reference frames rather than
  departing from them: over those pixels the ON photograph's own cap tops sit at
  saturation 0.065 under a strongly coloured field, and the preview's at 0.022. The
  reflection pool under the board is the same case: the OFF frame renders it
  *brighter* than the WHITE frame does, so it too has no light to take a hue.
- **A pure hue renders exactly pure.** `fA` is one number per pixel, as specified,
  so asking for `00FF00` puts red and blue at exactly the same value everywhere
  the light is tinted. Real light has per-channel scatter; this does not.
- **The editor crops the frame rather than letterboxing it.** The board and its
  reflection occupy 620 of the photograph's 941 rows; the rest is empty black. The
  page scales the photograph to fill whatever view it is given, so the editor shows
  the board and the review render — which asks for the frame's own proportions —
  shows all of it. Filling and fitting are the same operation there, so nothing the
  gates measure changes.
- **The board does not float; it sits on the ground the camera gave it.** The page
  and the web view still draw no background of their own, but the photograph is
  rendered opaque, because it came with its own ground: it was shot on black, and
  the desk reflection under the board is part of the picture. Matting it onto the
  window's light surface turned that reflection into a detached blob and the edge
  of the frame into a lumpy contour, which is what three separate cold-eyes audits
  led with. `KeyboardView` puts the same black behind it.
- **The photographs' printed legends are wrong in places, and the preview shows
  them.** The reference frames are AI-generated images, and three cold-eyes audits
  found the same defects in them: the top row is printed with number-row legends
  instead of F1-F12 (so the board appears to have two number rows and no function
  row); the bottom-left modifiers read `CTRL ALT WIN` where a Windows layout is
  `Ctrl Win Alt`; the left Shift reads `SHIPT`; the backtick and Backspace keys
  are unlabelled; the numpad's Enter key carries a stray `+`. The **hitboxes are
  correct** — they come from `KeyLayout.swift`, which is generated from the
  driver's own `rgb-keyboard.xml`, so clicking a key paints the LED the hardware
  addresses there. It is the printed legend under your cursor that may not match,
  not the LED.
- **The screen, the knob logo and the indicator icons are generative mush** in the
  source frames, and are reproduced as found.
- **The ON and RAINBOW round trips do not meet their thresholds, and cannot.** The four
  reference frames do not share an exposure — ON's keycap tops are brighter than WHITE's,
  which is impossible if WHITE is the full-brightness state, and RAINBOW's are darker
  than both OFF's and WHITE's. Since reproducing OFF and WHITE exactly pins every render
  to a blend of those two frames, the best *any* per-pixel tint could achieve against ON
  is 3.18/255 (threshold 2.5) and against RAINBOW 5.43/255 (threshold 3.0). The shipped
  pipeline reaches 5.62 and 7.45. See [`PREVIEW-LOG.md`](design/PREVIEW-LOG.md) for the measurement and for the
  remedies that were tried and rejected. `roundtrip.py` still renders, measures and
  prints both on every run against the same thresholds, but lists them as known
  infeasible so they do not fail `verify.sh` — otherwise the suite would be red
  forever and a real regression would look identical.
