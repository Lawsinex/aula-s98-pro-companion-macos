# Colour calibration

Calibration **never changes what is sent to the keyboard.** The keyboard is the ground
truth; the screen is the thing that lies. So it corrects what the *app draws*, so the
colour wheel and the keyboard preview show what the keys really look like.

Open any colour control and choose **Calibrate**. The left wheel is the **target** —
what you asked for. Press **Show on keyboard**, look at the keys, then set the right
wheel — **what actually happened** — to the colour you actually saw. **Add data point**
records the pair. Each pair is listed with both swatches and can be deleted
individually, or cleared wholesale.

More pairs give a better fit. The samples describe the hardware's distortion directly
(asked → observed) and the app averages them: hue circularly, so observations either
side of red do not cancel, plus saturation and brightness ratios. Everything the app
draws for the keyboard then goes through that correction — the wheel itself, the wheel's
knob, every swatch, the keyboard preview, the per-key canvas and the preset list.

The switch **Show the keyboard's real colours** turns the correction off, which is what
you want while collecting more data points: you need to judge the keys against true
colours, not corrected ones. The two wheels inside the calibration panel are always
uncorrected for the same reason.

Hex values always show the colour being sent, not the corrected appearance. Effects the
firmware generates itself (rainbow, colourful) cannot be corrected from macOS.
