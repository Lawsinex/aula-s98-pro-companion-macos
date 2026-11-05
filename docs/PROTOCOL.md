# The AULA S98 Pro USB protocol

Everything this app knows about the keyboard, written down so nobody has to work it out twice.

It was worked out for interoperability, by studying how AULA's Windows driver and firmware behave and by testing against one real keyboard. This repository contains no AULA code or binaries. Treat every detail as unofficial: AULA documents none of it, and it may not hold for other firmware versions.

> **Be careful.** The firmware programs flash straight from HID reports, and related boards have been damaged by guessing at opcodes. See [Do not upload images to the screen](#do-not-upload-images-to-the-screen).

## Commands

**Device.** VID `0x0C45` (SONiX) / PID `0x800A`, USB wired mode. Four USB interfaces; the
config channel is the vendor collection on **usage page `0xFF13`**, the only one declaring
a 64-byte **Feature** report.

**Transport.** Every command is a 64-byte HID Feature report with report ID 0
(`HidD_SetFeature` on Windows, `IOHIDDeviceSetReport` here).

**The one thing that matters:** after each single-packet write the host *must* read the
reply back with a Feature **get** (`IOCTL_HID_GET_FEATURE` on Windows). Without it the
firmware accepts every packet and silently does nothing. Bulk data blocks are the
exception — they stream with no read-back.

**Envelope.** `[0]` is the command class `0x04`, `[1]` is the opcode:

```
04 18   BEGIN
04 <op> select what is being written  ([8] usually a count)
<payload>
04 02   END
04 F0   SAVE      (lighting only)
```

Command packets reply with `byte[3] == 1` as an ACK.

| opcode | meaning | payload |
|---|---|---|
| `0x13` | lighting mode | 16-byte record, below |
| `0x23` | per-key ("user lighting") | 9 × 64 B |
| `0x20` | per-key ("custom lighting") | 3 or 8 × 64 B |
| `0x19`+`0x15` | per-key animation editor | frame list, 3584 B buffer |
| `0x17` | keyboard settings | terminator at byte 62 |
| `0x28` | set the real-time clock | one 64-byte record |
| `0x72` | TFT screen / GIF upload | **do not use** — see below |
| `0xF5` | status query | — |

**Lighting record** (opcode `0x13`):

```
[0] mode   [1][2][3] R,G,B   [8] colourful   [9] brightness 0-5
[10] speed 0-5   [11] direction   [14][15] 0xAA 0x55
```

**Per-key frame** (opcode `0x23`, `[8]` = 9 chunks = 576 bytes). Set light mode `0x80`
first, or the frame is stored but not shown. Each LED is a 4-byte record at `index*4`:

```
[ledIndex][R][G][B]        LED indices 1..123, slot 0 unused
last two bytes = 0xAA 0x55
```

**Clock** (opcode `0x28`). The keyboard renders its own home screen — date, time,
battery, lock indicators — in firmware. It does not want an image; it wants the time:

```
[0] 0   [1] slot   [2] 0x5A magic   [3] year-2000   [4] month   [5] day
[6] hour   [7] minute   [8] second   [10] weekday (0 = Sunday)
[62][63] 0xAA 0x55
```

`[3] = year − 2000` is why a keyboard that has never been synced displays **2000**/01/17.
The sequence is `04 18` → `04 28` → record → `04 02`, with no SAVE.

### Do not upload images to the screen

Opcode `0x72` uploads a 256-byte header plus 240×135 RGB565 frames in 4096-byte blocks,
and the packing was confirmed against `GetImageRGB565Data` in the vendor's `mui.dll`. It
is documented here only so nobody rediscovers it the hard way: **sending it hangs the
keyboard**, and it does the same from AULA's own Windows driver. It is not implemented,
and it should stay that way.

## The front light strip

**Not reachable from the host.** Not "AULA chose not to expose it" — the firmware has
no route from a USB report to the strip at all.

1. `layouts/rgb-keyboard.xml` sets `sidelight="0"` in both `<menu>` and
   `<menu_wireless>`, so the Side Light page never appears for this model.
2. The framework does support one: `language/1033.lan` defines `660=Side Light Mode`
   with modes `661-670` — Flowing Light, Red, Yellow, Green, Ice Blue, Blue, Pink,
   White, Neon, Off.
3. `DeviceDriver.exe` emits only `02 13 15 17 18 19 20 23 28 72 F0 F5`. None is a
   side-light command; `sidelight` appears once, as the XML attribute it reads.
4. Confirmed on hardware with a camera: the strip holds Ice Blue while the keys are
   driven red, green, blue and per-key rainbow, and stays lit when the keys are off.
5. **Decisive, from the firmware** (Cortex-M0 image extracted from
   `S98PRO Firemware.exe`; SONiX SN32F248; image base = flash `0x00000000`):
   - The strip is a **separate 14-LED engine** on the RAM struct at `0x2000018a`
     (`+8` mode, `+9` colour, `+0xA` speed, `+0xC` brightness) with its own palette at
     `0x13F16`: red, orange, yellow, green, **ice blue `00FFFF`**, blue, pink, white —
     exactly the vendor's Side Light list, and exactly the cyan the camera sees.
   - Its **only writers** are the on-board Fn handler (`0x2942`; mode is action `0x9B`,
     colour `0x9C`, brightness `0x99`) and the power-on restore at `0xe2da`.
   - It persists in flash region **`0x8000`**, written only by `0xde74`. The factory
     record there reads mode 0, colour 8, brightness 5, speed 3.
   - **`0x8000` appears nowhere in the USB region table**, and the strip's RAM
     addresses appear in no literal pool on the USB command path.

The strip is real, firmware-driven hardware, adjustable only from the keyboard
(`Fn`+Right Shift mode, `Fn`+Right Ctrl speed, `Fn`+`>` brightness, `Fn`+`/?` colour).
The claim that it has "no data link to the MCU" is wrong; so is the hope that software
can reach it. Two different things, both worth stating plainly.

### What the unused opcodes actually are

The vendor driver sends 12 opcodes; the firmware accepts more. The real table is at
`0x406a`, and it is a **read/write pair map** — mode 1 dumps a region to the host,
mode 2 programs it from the host:

| read | write | region | holds |
|---|---|---|---|
| `0x10` | `0x11` | `0x9400` | key remap layer A |
| `0x12` | `0x13` | `0x9800` | main lighting |
| `0x14` | `0x15` | `0xA000` | — |
| `0x16` | `0x17` | `0x9000` | keyboard config |
| `0x22` | `0x23` | `0x9C00` | per-key frame |
| `0x26` | `0x27` | `0xAC00` | key remap layer B |

So the "unused" opcodes are the **read halves** the vendor driver never calls, and the
keyboard can in principle be asked for its stored state. Both remap regions are 4 bytes
per key, up to `0x8F` entries, guarded by a `0x55AA0000` magic at `region+0x23C`.
Neither is lighting. (Untested on hardware — reading needs the transfer armed first.)

`0x8dc8` is a bare flash **page-erase** (`r0` = address, silently refusing anything
below `0x8000`, 1 KB pages, FMC at `0x40062000`), not a storage routine. The actual
copy is `0x3cae`, which programs 64 bytes straight from the HID report buffer per
packet — so `SAVE (04 F0)` is not what commits.

**Not blind-probing opcodes.** The related F108 Pro's firmware does no bounds checking
on flash writes, and exactly that kind of guessing permanently overwrote its LCD menu
graphics. This keyboard declares the same `gif_maxframes="141"`.

## Gotchas

Each of these cost real debugging time:

1. **Read the reply back.** Covered above. Without the Feature *get*, nothing happens and
   nothing errors.
2. **`header[0]` is the frame count.** The screen buffer is pre-filled with `0xFF`, so
   forgetting this leaves the count at 255 and the upload is rejected.
3. **Retain the `IOHIDManager`.** Let it go out of scope and ARC tears it down, killing
   every device handle it vended — which looks exactly like a disconnect.
4. **Coalesce writes.** One committed lighting change is five HID transactions (~350 ms).
   A colour wheel produces far more updates than the keyboard can consume, so live
   previews are debounced and the device layer keeps only the newest lighting job.
5. **Separate previews from commits.** Drag previews omit `SAVE (04 F0)`; releasing
   a control sends it once. Temporary calibration probes never inherit a queued
   save. This reduces redundant command traffic, but does **not** prove flash-wear
   protection: the firmware evidence above indicates payload receipt can itself
   program flash. Actual retention still needs a hardware power-cycle test.

## App and CLI coordination

The keyboard has a single command state machine. If the app is running (and the clock is
syncing) while you also run `aula-s98`, transactions must not interleave. Both binaries
therefore share a per-user advisory lock around complete operations. A conflicting command
fails cleanly with `keyboard is busy` instead of consuming another process's reply.

## Effects

All twenty are named. The nine AULA's driver names are exact — it calls
`AddString(name, lParam)` where `lParam` is the mode byte. The other eleven are named
from the printed manual, matched by the effect number the keyboard's own LCD shows.
"Effect" below is that LCD number.

| mode | effect | name | animated | uses colour |
|----|----|------|----------|-------------|
| 0 | 20 | Off | no | no |
| 1 | 10 | Static On *(driver)* | no | yes |
| 2 | 11 | Single light up | yes | yes |
| 3 | 12 | Single extinction | yes | yes |
| 4 | 13 | Starlight *(driver)* | yes | yes |
| 5 | 14 | Fluttering *(driver)* | yes | yes |
| 6 | 15 | Flowers are blooming | yes | yes |
| 7 | 16 | Dynamic Breathing *(driver)* | yes | yes |
| 8 | 17 | Spectral cycle | yes | yes |
| 9 | 18 | Colorful Fountain *(driver)* | yes | no |
| 10 | 19 | Rainbow Wave *(driver)* | yes | no |
| 11 | 1 | Following Currents *(driver)* | yes | yes |
| 12 | 2 | Peak Revolving *(driver)* | yes | yes |
| 13 | 3 | Be touch-and-go | yes | yes |
| 14 | 4 | Kill two birds with one stone | yes | yes |
| 15 | 5 | Ripple diffusion | yes | yes |
| 16 | 6 | A continuous flow | yes | yes |
| 17 | 7 | Range upon range of mountains | yes | yes |
| 18 | 8 | Light wind and drizzling rain | yes | yes |
| 19 | 9 | Shuttle back and forth | yes | yes |

The protocol numbers are **not** sequential, and neither list alone was enough: the
driver gives exact name-to-number pairs for nine, the manual gives twenty names in LCD
order with no numbers. `default_mode="11"` in the layout file is Following Currents,
which is how the board ships. Mode `0x80` is special — it means "display the per-key
frame".

## How the manual's list was pinned down

The manual prints its twenty effects in two columns and never says which way to read
them, so the names alone are ambiguous. The Identify tab was used to record, by hand
against the hardware, which LCD effect number each unnamed mode shows
(`data/mode-labels.json`). That gives eleven numbers — 3, 4, 5, 6, 7, 8, 9, 11, 12, 15
and 17 — leaving exactly nine free, and those nine must belong to the nine modes the
driver names.

That constraint settles the reading order:

- **Down the columns is impossible.** It puts *Static constant brightness* and *was
  studded with stars* in slots the recorded data already occupies, when Static On and
  Starlight have to be free.
- **Across the rows fits perfectly**, and every free slot lands on a name that matches
  its mode: *Adrift* / Following Currents, *The path winds along mountain ridges* /
  Peak Revolving, *Static constant brightness* / Static On, *was studded with stars* /
  Starlight, *Flying snow all over the sky* / Fluttering, *Dynamic respiration* /
  Dynamic Breathing, *Colorful spring surging* / Colorful Fountain, *Colorful Vertical
  and Horizontal* / Rainbow Wave, *OFF* / Off.

Nine independent semantic matches out of nine. `AulaLogicTests` asserts the two sets
still partition 1–20 exactly once, so a wrong edit to either table fails the build.

The wording is AULA's own rough translation from the Chinese — *Kill two birds with one
stone* really is what the manual calls effect 4. Only the first letter is normalised.
