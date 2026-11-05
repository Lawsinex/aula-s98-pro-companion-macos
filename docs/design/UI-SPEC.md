# ANODISED — Unified UI Specification for Aula S98 Pro Companion

> Historical specification. The selected Library Rail redesign in DESIGN.md
> supersedes this document as of 4 October 2026. Protocol and preview invariants
> below remain useful; its orange palette, sidebar and effect-gallery layout do not.

*Synthesis of four explored directions. Spine: **Anodised** (the conventional-inspector-on-black direction, highest `fulfils_asks`). Grafted: width-driven preview sizing and plate deletion (all four), `EditorTab` totality (Stage), pinned notice outside the scroller (Stage), single-scroller panel (all four), `strokeKeys` highlight wiring (Stage), one gutter / one measure (Canvas), single status vocabulary (Console), sectioned preset menu with swatch images (Anodised), snapshot-count arithmetic (Console).*

*Every fatal flaw raised against the four is fixed below or dismissed by name in §11.*

---

## 1. THESIS

The keyboard photograph is the only lit thing in the app. Both surfaces are one continuous `#000000` field with the transparent WKWebView board spanning the full width of whatever contains it — no plate, no radius, no inset — so the photograph's soft matte and its desk reflection dissolve into the app's own ground exactly as the camera shot them. Everything below the board is a quiet, strictly conventional macOS inspector: system sliders, system toggles, system pickers, a source list, one gutter, one measure, one type scale. Structure on black is carried by **borders and typography, never by fill steps** — because no fill light enough to read against `#000000` is dark enough to leave the photograph alone. The app is dark-only at runtime, forced once at the `NSApplication` level so popovers, sheets, alerts, menus and the window titlebar come with it.

---

## 2. DESIGN TOKENS

New file: **`src/InkTheme.swift`**. `scripts/build.sh` and `scripts/verify.sh` both glob `"${project_dir}"/src/*.swift`, so the file is picked up with no script change.

```swift
import SwiftUI

extension Color {
    /// 0xRRGGBB, so the token table reads as the numbers in the spec.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The whole palette, the whole spacing rhythm, the whole type scale.
///
/// Dark-only on purpose. `NSApplication.shared.appearance` is pinned to
/// `.darkAqua` at launch (AulaCompanion.swift), so every AppKit-drawn control, popover,
/// sheet, alert, menu and titlebar comes with us; nothing here has a light mirror
/// to keep in sync, and nothing derives from `Color.primary`, `.secondary` or
/// `.accentColor`.
///
/// Structure is carried by BORDERS, not by fill steps. Against #000000 no fill
/// can reach the 3:1 that a boundary needs without going grey enough to fight the
/// photograph — so `surface`/`well` are quiet planes, and `stroke` (3.42:1) is
/// what actually says "this is a control".
enum Ink {

    // MARK: Surfaces
    static let ground   = Color(hex: 0x000000)   // window + panel body, and the stage
    static let surface  = Color(hex: 0x12_1216)  // cards
    static let well     = Color(hex: 0x1C_1C22)  // control fills, fields, unselected cells
    static let hairline = Color(hex: 0x34_343C)  // grouping rules and card borders
    static let stroke   = Color(hex: 0x61_6169)  // EVERY interactive boundary. 3.42:1 on ground.
    /// Increase Contrast (System Settings › Accessibility › Display) promotes both.
    static let hairlineHi = Color(hex: 0x61_6169)
    static let strokeHi   = Color(hex: 0x8A_8A94)

    // MARK: Ink. Exactly two text colours plus a disabled step. There is no
    // "tertiary": every direction that defined one immediately spent it on
    // load-bearing text at 3.3:1.
    static let text         = Color(hex: 0xF2_F3F5)   // 18.91:1 on ground
    static let textSecond   = Color(hex: 0xA7_ACB6)   //  9.22:1 on ground
    static let textDisabled = Color(hex: 0x7A_7F8A)   //  5.23:1 on ground

    // MARK: Accent — fixed, not the system accent.
    // #FF5A1F is the ember the reference photographs were lit in (it is already
    // the harness default, AulaCompanion.swift:55). Fixed rather than Color.accentColor
    // so the label colour on a filled accent is a measured constant (6.34:1)
    // instead of a per-user gamble that Graphite and Yellow lose.
    static let accent   = Color(hex: 0xFF_5A1F)   // 6.73:1 on ground
    static let onAccent = Color(hex: 0x0A_0A0C)   // 6.34:1 on accent

    // MARK: Signals
    static let ok   = Color(hex: 0x30_D158)   // 10.39:1
    static let warn = Color(hex: 0xFF_B020)   // 11.48:1
    static let bad  = Color(hex: 0xFF_453A)   //  6.16:1

    // MARK: Spacing — 4 / 8 / 12 / 16 / 20 / 28, nothing else.
    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s28: CGFloat = 28

    static let panelGutter: CGFloat = 16     // menu panel, every band
    static let pagePad:     CGFloat = 20     // editor, every section, no exceptions
    static let pageWidth:   CGFloat = 720    // editor, every section, no exceptions
    static let cardPad:     CGFloat = 16
    static let labelColumn: CGFloat = 96     // editor inspector rows
    static let panelLabelColumn: CGFloat = 96

    // MARK: Radii
    static let rControl: CGFloat = 6
    static let rCard:    CGFloat = 10
    static let rSwatch:  CGFloat = 5
    // The stage has no radius. That is the point.

    // MARK: Heights
    static let hairlineWidth: CGFloat = 1
    static let rowControl: CGFloat = 30      // a slider / checkbox row
    static let rowTall:    CGFloat = 34      // a row containing a ColorPopoverButton
    static let rowNav:     CGFloat = 34      // sidebar item
    static let rowCell:    CGFloat = 34      // effect grid cell
    static let button:     CGFloat = 24

    // MARK: Type. 11pt is the floor — AppKit's own smallest label size, and one
    // point above what this codebase currently uses for status text and badges.
    static func caption(_ w: Font.Weight = .regular) -> Font { .system(size: 11, weight: w) }
    static func mono(_ size: CGFloat = 11) -> Font { .system(size: size, design: .monospaced) }
    static func body(_ w: Font.Weight = .regular) -> Font { .system(size: 12, weight: w) }
    static func row(_ w: Font.Weight = .regular) -> Font { .system(size: 13, weight: w) }
    static let panelTitle  = Font.system(size: 15, weight: .semibold)
    static let sidebarTitle = Font.system(size: 16, weight: .semibold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    static let clockTime    = Font.system(size: 30, weight: .medium, design: .monospaced)

    // MARK: Fixed geometry
    static let panelWidth:  CGFloat = 410
    static let panelHeight: CGFloat = 660
    /// 410 / (1672/620) = 152.03. Pinned, never derived at layout time.
    static let panelStageHeight: CGFloat = 152
    static let sidebarWidth: CGFloat = 176
    static let stageMaxHeight: CGFloat = 320
}
```

**Contrast contract for anything drawing a border:**

```swift
// Every component that draws a boundary does exactly this. Two lines, no
// environment key, no ButtonStyle — a ButtonStyle is not a view and never
// receives injected environment values.
@Environment(\.colorSchemeContrast) private var contrast
private var borderColor: Color { contrast == .increased ? Ink.strokeHi : Ink.stroke }
private var ruleColor:   Color { contrast == .increased ? Ink.hairlineHi : Ink.hairline }
```

---

## 3. MENU PANEL — 410 × 660

### Height budget (exact, sums to 660)

| Band | Height | Scrolls? |
|---|---|---|
| Identity bar | 50 | no |
| **Stage** (full bleed) | **152** | no |
| Control scroller | **385** (351 when the notice is up) | **yes — the panel's only scroller** |
| PinnedNotice (conditional) | 34 | no |
| Hairline | 1 | no |
| Footer | 72 | no |

Panel content width = 410 − 2×16 = **378**. Card inner width = 378 − 32 = **346**.

Scroller content, top to bottom: 16 pad → "Effect" header row 18 → 8 → EffectGrid (3 columns × 7 rows at 34pt + 6pt spacing = **274**) → 16 → Controls card (**90** for a static mode, **152** for an animated one) → 12 → action row 26 → 16 pad. Total **476–538** against a 385pt viewport. At rest the whole 20-mode grid plus the top of the Colour row is visible; brightness, speed and the action row are one short scroll. That is one scroller, and the four things that must never be hidden — the board, the notice, the status, Quit — are all outside it.

### How the preview goes full bleed and fades

Three changes, all required together:

1. **Sized by width, never by height.** `.frame(width: 410, height: 152)` on `KeyboardView`, with `.padding` of zero on that band. Today's `.frame(height: 104)` combined with `KeyboardView`'s internal `.aspectRatio(kPreviewDisplayAspect /* 1672/620 = 2.6968 */, .fit)` resolves the *width* from the height: 104 × 2.6968 = 280.5pt inside a 378pt leading-aligned column. That — not the 16pt padding — is the whole defect. The height is **pinned as a constant**, not derived, so a budget overrun elsewhere can never squeeze the board back into a letterbox.
2. **The plate is deleted.** `KeyboardView` loses `.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))` (AppViews.swift:151-154) and the comment at :146-150 that admits it is a patch for a light window. It also loses its internal `.aspectRatio(kPreviewDisplayAspect, .fit)` — frame ownership moves to the caller. With the ground at exactly `#000000` there is nothing behind the transparent page at all, so the matte and the desk reflection run out into the panel with no terminating edge.
3. **The fade is an overlay, never a mask.** A `.mask()` over an `NSViewRepresentable`-hosted WKWebView is a layer mask on a hosted AppKit view and is unreliable across compositing paths. A 28pt `LinearGradient(.clear → Ink.ground)` overlaid on the bottom edge is pixel-identical here, touches nothing about the web view, and gives the overlaid caption a ground to sit on.

`MenuBarExtra(.window)` masks its own window corners at roughly 5pt. The photograph is black at both top corners, so this is invisible. **Do not add a `clipShape` to "fix" it** — any shape you add gives the preview back the edge this design exists to remove.

Offscreen, `KeyboardView`'s `snapshotMode` branch still substitutes `KeyboardFlatView`, whose internal `.aspectRatio(kLayoutSize.width / kLayoutSize.height /* 695/211 = 3.294 */, .fit)` is **left exactly as it is**. Inside a 410 × 152 box it resolves width-limited to 410 × 124.5, centred, with 13.75pt of `Ink.ground` above and below. Full width is preserved; the vertical letterbox is into the same black the board dissolves into. No change to `KeyboardFlatView`.

### `MenuPanelView`

```swift
struct MenuPanelView: View {
    @ObservedObject var model: AppModel

    private var effectName: String { model.modeName(model.currentMode) }

    var body: some View {
        VStack(spacing: 0) {

            // 1. Identity, 50pt. No divider under it: the black runs unbroken
            //    from y=0 to y=202 and the board floats up into the title.
            VStack(alignment: .leading, spacing: 2) {
                Text("AULA S98 Pro").font(Ink.panelTitle).foregroundStyle(Ink.text)
                Text("Native USB control").font(Ink.caption()).foregroundStyle(Ink.textSecond)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Ink.panelGutter)
            .frame(height: 50)

            // 2. The stage. Full bleed, no padding, no plate, no radius.
            //    Width drives it; the height is a pinned constant.
            InkStage(caption: effectName,
                     trailing: model.currentMode.usesColor
                        ? model.calibratedOutputColor.hex : nil,
                     scrim: 28) {
                KeyboardView(colors: model.effectPreview, effectName: effectName)
            }
            .frame(width: Ink.panelWidth, height: Ink.panelStageHeight)

            // 3. The panel's one and only scroller. The inner VScroll(height: 150)
            //    that used to wrap the effect grid is deleted outright.
            VScroll {
                VStack(alignment: .leading, spacing: 0) {

                    HStack(spacing: Ink.s8) {
                        Text("Effect").font(Ink.body(.medium)).foregroundStyle(Ink.textSecond)
                        Spacer(minLength: Ink.s8)
                        Text(effectName)
                            .font(Ink.body(.medium)).foregroundStyle(Ink.text)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(height: 18)

                    EffectGrid(model: model, columns: 3).padding(.top, Ink.s8)

                    InkCard {
                        ColorPopoverButton(
                            label: "Colour",
                            color: Binding(get: { model.light.color },
                                           set: { model.light.color = $0 }),
                            swatches: model.recentColors,
                            onSaveSwatch: { model.saveColor($0) },
                            onRemoveSwatch: model.removeSavedColor,
                            onClearSwatches: model.clearSavedColors,
                            enabled: model.currentMode.usesColor,
                            onPreview: model.previewMode,
                            onCommit: model.commitMode,
                            calibration: $model.calibration,
                            calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                            onCalibrationPreview: model.previewRawColor,
                            onCalibrationCommit: model.commitMode)

                        SteppedSlider(label: "Brightness", value: model.light.brightness,
                                      enabled: model.light.mode != 0) { value, preview in
                            model.updateBrightness(value, preview: preview)
                        }

                        // Selectable here, so adjustable here. The panel could
                        // already pick Rainbow Wave and then had nowhere to set
                        // its speed.
                        if model.currentMode.animated {
                            SteppedSlider(label: "Speed", value: model.light.speed,
                                          enabled: true) { value, preview in
                                model.updateSpeed(value, preview: preview)
                            }
                            HStack(spacing: Ink.s20) {
                                Toggle("Reverse", isOn: Binding(
                                    get: { model.light.reverse }, set: model.setReverse))
                                Toggle("Cycle colours", isOn: Binding(
                                    get: { model.light.colorful }, set: model.setColorful))
                                Spacer(minLength: 0)
                            }
                            .toggleStyle(.checkbox)
                            .font(Ink.caption())
                            .frame(height: Ink.rowControl)
                        }
                    }
                    .padding(.top, Ink.s16)

                    HStack(spacing: Ink.s8) {
                        InkButton("Lights off", icon: "lightbulb.slash",
                                  action: model.turnLightsOff)
                            .disabled(model.light.mode == 0)
                        PresetMenu(model: model)
                        InkButton("Sync clock", icon: "clock.arrow.circlepath") {
                            model.clock.syncNow()
                        }
                        .help("Set the keyboard's clock to this Mac's current time")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, Ink.s12)
                }
                .padding(.horizontal, Ink.panelGutter)
                .padding(.vertical, Ink.s16)
            }
            .frame(maxHeight: .infinity)

            // 4. Pinned OUTSIDE the scroller. The one element that exists to be
            //    noticed can no longer be the first thing pushed below the fold.
            if model.lightHasUnappliedChanges {
                InkNotice("Last change is not confirmed on the keyboard",
                          actionTitle: "Apply again", action: model.commitMode)
                    .padding(.horizontal, Ink.panelGutter)
                    .padding(.bottom, Ink.s8)
            }

            InkRule()

            // 5. Footer, 72pt. Connection state is stated ONCE per surface, here.
            VStack(spacing: Ink.s8) {
                HStack(spacing: Ink.s8) {
                    ConnectionDot(device: model.device)
                    Text(model.device.status)
                        .font(Ink.mono()).foregroundStyle(Ink.textSecond)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Ink.s8)
                    if model.device.phase == .disconnected || model.device.phase == .failed {
                        InkButton("Retry") { model.device.retryConnection() }
                    }
                }
                .frame(height: 20)

                HStack(spacing: Ink.s8) {
                    InkButton("Open editor", icon: "rectangle.inset.filled", tone: .accent) {
                        EditorWindowController.shared.show(model: model)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    Spacer()
                    InkButton("Quit") { NSApp.terminate(nil) }
                }
            }
            .padding(.horizontal, Ink.panelGutter)
            .padding(.vertical, 10)
        }
        .frame(width: Ink.panelWidth, height: Ink.panelHeight)
        .background(Ink.ground)
        .foregroundStyle(Ink.text)
    }
}
```

**Return is fixed.** `.keyboardShortcut(.defaultAction)` comes off "Open full editor". The rule across the whole app: **Return confirms; it never navigates.** `.defaultAction` is allowed only on a transient container's confirm button (the rename sheet, the delete alert) and on a section's single primary commit (Settings → Apply to keyboard; the calibrator → Add data point). Opening the editor is ⌘E — bound both on the panel button *and* as a `CommandMenu` item, because `.keyboardShortcut` inside `MenuBarExtra(.window)` is not fully dependable on macOS 13 and the shortcut it replaces demonstrably works today.

---

## 4. EDITOR — 840 × 720, min 700 × 600

### Navigation model

A persistent **176pt source list** replaces the five-segment picker. Four rows — Lighting, Clock, Presets, Settings — each 34pt with a 20pt icon gutter, 6pt radius, selected row filled `Ink.accent` with an `Ink.onAccent` label (6.34:1, measured, not luck). Each row carries a 5pt `Ink.accent` pip when that section has unapplied work: Lighting reads `lightHasUnappliedChanges || keysHaveUnappliedChanges`, Presets reads `presets.lastError != nil`, Settings reads `configHasUnappliedChanges`. The segmented picker could show none of that.

Above the nav sits the identity block ("AULA S98 Pro" / "Lighting and keyboard control"). Below it, pinned to the bottom, the **DeviceBlock**: `ConnectionDot`, the device status string on two lines, Retry when disconnected or failed, and Quit. That is the *only* statement of connection state in the window — the header `ConnectionBadge` and the footer `StatusFooter`, two icon vocabularies for one fact 600pt apart, both collapse into it, and the detail column has no footer at all.

**The tab model becomes total.** No `default:` arm can silently alias a stray index onto Settings:

```swift
enum EditorTab: Int, CaseIterable, Identifiable {
    case lighting = 0, clock = 1, presets = 2, settings = 3
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .lighting: return "Lighting"
        case .clock:    return "Clock"
        case .presets:  return "Presets"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .lighting: return "paintbrush.pointed"
        case .clock:    return "clock"
        case .presets:  return "square.stack.3d.up"
        case .settings: return "gearshape"
        }
    }
    /// The one place an out-of-range index is resolved.
    static func clamped(_ raw: Int) -> EditorTab { EditorTab(rawValue: raw) ?? .lighting }
}
```

Applied at all three unvalidated entry points: `AulaCompanion.swift:44` (`AULA_TAB`), `EditorWindowController.show(model:tab:)`, and `EditorView.init`. `AppModel.selectedTab` stays an `Int` (it is `@Published` and bound by the sidebar) but is only ever written through `EditorTab.clamped(_:).rawValue`.

⌘1–⌘4 keep their existing `CommandMenu` bindings with **no renumbering**. The sidebar rows carry **no** `.keyboardShortcut` — double ownership of ⌘1–⌘4 between the CommandMenu and the rows is a real conflict.

### Layout

```
┌────────────┬─┬──────────────────────────────────────────────┐
│ identity 66│ │ SectionBar 44                                │
│ ───────────│ │ ────────────────────────────────────────────  │  hairline
│ Lighting ● │s│                                              │
│ Clock      │p│  [Lighting only] STAGE — full bleed, 663×246 │  outside the scroller
│ Presets    │i│                                              │
│ Settings ● │n│  VScroll → InkPage(pad 20, maxWidth 720)     │  the only scroller
│            │e│                                              │
│ ───────────│ │                                              │
│ DeviceBlock│ │  [InkNotice, pinned]                         │  outside the scroller
└────────────┴─┴──────────────────────────────────────────────┘
   176        1                    663 (523 at the 700 minimum)
```

**One inset, one measure, applied once by `InkPage`.** Today the four tabs start at 18/24/20/24 and cap at uncapped/700/820/720, so the body jumps sideways on every tab switch while the chrome stays put. Now every section is `.padding(20)` inside `.frame(maxWidth: 720, alignment: .leading)`, enforced by the component rather than by convention.

**Stage geometry.** `.frame(maxWidth: .infinity).aspectRatio(kPreviewDisplayAspect, contentMode: .fit).frame(maxHeight: 320).layoutPriority(1)`. At 840 the detail column is 663 → **663 / 2.6968 = 245.9 → 246pt**. At the 700 minimum, detail 523 → **194pt**. The `layoutPriority(1)` wins the height negotiation against the fully-flexible `VScroll` below it; the `maxHeight` cap only engages above roughly 863pt of detail width. **No `GeometryReader` anywhere on the snapshot path** — one inside `.fixedSize(horizontal: false, vertical: true)` has zero ideal height and would collapse the entire editor render.

The stage is **Lighting-only**, mounted inside the Lighting section. It is *not* persistent chrome across all four sections: that would tear down and rebuild a WebGL WKWebView on every tab switch (`verify.sh:186` waits 6 seconds for one to paint) in order to show a cropped 96pt strip on the Clock page. Lighting already owns the only `KeyboardView` today, so this is no regression.

### 4.1 Lighting

`SectionBar("Lighting")` with the Effect / Per-key segmented picker trailing (200pt). Then the stage, full bleed, with two overlaid captions on the scrim:

- **bottom-left** — `model.lightingSource.summary` ("A built-in animation runs on the keyboard itself." / "Your own colour for every key, uploaded as one frame.")
- **bottom-right** — the calibration/paint state: `"Click or drag to paint · Tab to focus individual keys"` / `"Preview · the animation itself plays on the keyboard"` / `"Preview corrected from N data point(s)"` / `"Preview showing true colours · correction is switched off"`

Both audited strings live on the object they describe and cost zero layout height.

In per-key mode the same board becomes the paint target at the identical position and size, and **finally receives a non-empty highlight set** (§5, `AppModel.strokeKeys`) so `KeyCapView`'s 1.6pt selection stroke and `KeyboardWebController.kbSetHighlight` — both fully implemented and never once passed a non-empty set — start confirming that a click landed where you meant it.

**Effect source inspector** — two cards.

*Card "Effect"* (detail: "Runs on the keyboard. Changes apply when a control is released.")
`EffectGrid(model:columns: 4)` — 20 modes, 5 rows × 34 + 4 × 6 = 194pt, all visible, no inner scroller ever. Cell width 143 at 840, 108 at the 700 minimum. Then `InkRow("Colour")` with the `ColorPopoverButton` (260pt), `SteppedSlider("Speed")`, and an `InkRow("Animation")` carrying the Reverse direction and Cycle colours checkboxes. Card height ≈ 388.

*Card "Output"*
`SteppedSlider("Brightness")` and an `InkRow("Power")` with **Turn lights off** (disabled at mode 0). Card ≈ 146.

*Pinned below the scroller:* `InkNotice("Not confirmed on the keyboard", actionTitle: "Apply again")`.

**Per-key source inspector** — two cards, every row fitting the 351pt control column at the 700pt minimum (this is where a single wide tool rail overflows by ~490pt and cannot reflow):

*Card "Paint"* (detail: "Every tool uploads one complete, verified frame.")

| Row | Contents | Width at min |
|---|---|---|
| Brush | `ColorPopoverButton("Brush")` 220 + Erase button-toggle 70 | 298 ✓ |
| History | Undo 76 + Redo 76 (both disabled-aware) | 160 ✓ |
| Fill | Fill all 66 · Rainbow 66 · Random 66 · Clear 54 | 270 ✓ |
| Gradient from | `ColorPopoverButton("Gradient start")` 240 | 240 ✓ |
| Gradient to | `ColorPopoverButton("Gradient end")` 240 | 240 ✓ |
| *(unlabelled)* | Apply gradient 110 | 110 ✓ |

*Card "Output"*: Brightness (routed with `forPerKey: true`), and a "Save as" row — `TextField("Preset name")` 200 + Save preset, disabled while blank.

### 4.2 Clock

One card. Date at 12pt `Ink.textSecond` over the time at **30pt monospaced `.monospacedDigit()`**, inside the existing `TimelineView(.periodic(from: Date(), by: 1))`. Then the auto-sync `Toggle(.switch)` with its "Syncs at launch, every 30 minutes, and after wake, time-zone, or system-clock changes." line, **Sync now** with `model.clock.lastSync` beside it, and the picture-upload safety note as a closing `InkNotice` in `Ink.warn` with the `shield.checkered` glyph. Every clock feature intact.

**Determinism:** in `snapshotMode` the TimelineView is replaced by a fixed `Date(timeIntervalSince1970: 1_700_000_000)`, and `lastSync` renders as the constant string `"Not synced yet"`. Without this the Clock hash differs run to run, which passes the distinctness check vacuously and could never catch a structural regression in that tab.

### 4.3 Presets

`SectionBar("Presets")` with trailing: `TextField("New preset name")` 180 + **Save current effect** + an `ellipsis.circle` Menu carrying **Import…** and **Export…**. Both file operations keep their `NSSavePanel`/`NSOpenPanel`, the 1 MB cap, the legacy-format fallback and the result alerts — they simply stop sitting at the same visual weight as the primary Save, and they now live next to the objects they act on.

Body: card **"Built-in"** (5 `PresetRow`s), card **"Your presets"** (rows, or the empty-state line "No custom presets yet" / "Save the current effect here or a layout from Per-key."), and `model.presets.lastError` as an `InkNotice`.

`PresetRow` gains a `compact` flag but keeps every fact: 34×24 swatch at `rSwatch` with a 1pt `stroke` border and `model.displayColor(preset.swatch)`, name at 13pt, **"Built-in"** as a real 11pt bordered pill in `Ink.textSecond`, summary at 11pt, **Apply always visible at full opacity** (never hover-gated), and the ellipsis Menu with Replace with current / Rename… / Delete. Rename sheet (Return confirms, blank rejected) and the destructive Delete alert naming the preset are unchanged.

### 4.4 Settings

Three cards.

**Keyboard behaviour** — detail line is the audited "These values have not yet been confirmed from this Mac." / "These are the last settings confirmed by this Mac." Rows: Sleep after (Picker 150), Key response (Picker 150), the three Disable checkboxes. Then a rule, then **Reset form to defaults** / "Not applied" / **Apply to keyboard** (`.keyboardShortcut(.defaultAction)` — this section's single primary commit).

**LED colour calibration** — the Standard-RGB-vs-Custom-profile line with its Applied/Uncorrected badge, the sentence pointing at any Colour or Brush control, an `InkRow("Live tests")` with Red/Green/Blue/White, **Reset calibration**, the "Shown on screen as" swatch + hex, **Reapply current effect**, and both explanatory paragraphs. Plus one new row (§7): **Effect names** — visible only when `model.modeLabels` is non-empty, reading `"N custom effect name(s) recorded"` with a **Use the manual's names** button that clears every override. That is the escape hatch the Identify tab used to be.

The dual-wheel calibrator itself **stays exactly where it is** — inside the colour popover behind the Calibrate/Done toggle (`ColorPopover.swift:130-136`, branch at `:145`). Snapshot renders 7 and 8 are distinguished by nothing except `ColorEditorSnapshot`'s `startCalibrating` flag; promoting the calibrator to its own panel merges those two hashes.

**Application** — Start Aula S98 Pro Companion at login with the requires-approval `InkNotice`, Reveal log in Finder, and the version string. Then the About paragraph at 11pt `Ink.textSecond`, `.frame(maxWidth: 560)`.

### Editor shell

```swift
struct EditorView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel, initialTab: Int? = nil) {
        self.model = model
        if let initialTab { model.selectedTab = EditorTab.clamped(initialTab).rawValue }
    }

    private var tab: EditorTab { EditorTab.clamped(model.selectedTab) }

    var body: some View {
        HStack(spacing: 0) {
            InkSidebar(model: model)
                .frame(width: Ink.sidebarWidth)
            InkRule(.vertical)
            Group {
                // Total: every case is named, so there is no `default:` arm for a
                // stray index to alias onto.
                switch tab {
                case .lighting: LightingSection(model: model)
                case .clock:    ClockSection(model: model)
                case .presets:  PresetsSection(model: model)
                case .settings: SettingsSection(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 700, minHeight: 600)
        .background(Ink.ground)
        .foregroundStyle(Ink.text)
    }
}
```

### Lighting section

```swift
private struct LightingSection: View {
    @ObservedObject var model: AppModel
    @State private var erasing = false
    @State private var presetName = ""

    private var isPerKey: Bool { model.lightingSource == .perKey }
    private var unapplied: Bool {
        isPerKey ? model.keysHaveUnappliedChanges : model.lightHasUnappliedChanges
    }

    var body: some View {
        VStack(spacing: 0) {
            InkSectionBar("Lighting") {
                Picker("Lighting source", selection: $model.lightingSource) {
                    ForEach(LightingSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            InkRule()

            // Full bleed across the whole detail column, outside the scroller,
            // sized by width. Fixed viewer, scrolling inspector.
            InkStage(caption: model.lightingSource.summary,
                     trailing: canvasCaption,
                     scrim: 40) {
                if isPerKey {
                    KeyboardView(colors: model.displayColors(model.keys),
                                 highlight: model.strokeKeys,     // finally non-empty
                                 effectName: "Per-key",
                                 onPaint: { model.paintKey($0, erase: erasing) },
                                 onPaintEnded: model.endPainting)
                } else {
                    KeyboardView(colors: model.effectPreview,
                                 effectName: model.modeName(model.currentMode))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(kPreviewDisplayAspect, contentMode: .fit)
            .frame(maxHeight: Ink.stageMaxHeight)
            .layoutPriority(1)

            VScroll {
                InkPage {
                    if isPerKey { paintCard; perKeyOutputCard }
                    else        { effectCard; effectOutputCard }
                }
            }
            .frame(maxHeight: .infinity)

            if unapplied {
                InkNotice("Not confirmed on the keyboard",
                          actionTitle: isPerKey ? "Upload again" : "Apply again") {
                    if isPerKey { model.applyKeys() } else { model.commitMode() }
                }
                .padding(.horizontal, Ink.pagePad)
                .padding(.bottom, Ink.s8)
            }
        }
    }

    private var canvasCaption: String {
        if isPerKey { return "Click or drag to paint · Tab to focus individual keys" }
        if model.calibration.samples.isEmpty {
            return "Preview · the animation itself plays on the keyboard"
        }
        return model.calibrationPreviewEnabled
            ? "Preview corrected from \(model.calibration.samples.count) data point(s)"
            : "Preview showing true colours · correction is switched off"
    }

    // MARK: Effect

    private var effectCard: some View {
        InkCard(title: "Effect",
                detail: "Runs on the keyboard. Changes apply when a control is released.") {
            EffectGrid(model: model, columns: 4)

            InkRow("Colour") {
                ColorPopoverButton(
                    label: "Colour",
                    color: Binding(get: { model.light.color },
                                   set: { model.light.color = $0 }),
                    swatches: model.recentColors,
                    onSaveSwatch: { model.saveColor($0) },
                    onRemoveSwatch: model.removeSavedColor,
                    onClearSwatches: model.clearSavedColors,
                    enabled: model.currentMode.usesColor,
                    onPreview: model.previewMode,
                    onCommit: model.commitMode,
                    calibration: $model.calibration,
                    calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                    onCalibrationPreview: model.previewRawColor,
                    onCalibrationCommit: model.commitMode)
                    .frame(width: 260)
                Spacer(minLength: 0)
            }

            SteppedSlider(label: "Speed", value: model.light.speed,
                          enabled: model.currentMode.animated) { value, preview in
                model.updateSpeed(value, preview: preview)
            }

            InkRow("Animation") {
                Toggle("Reverse direction", isOn: Binding(
                    get: { model.light.reverse }, set: model.setReverse))
                    .disabled(!model.currentMode.animated)
                Toggle("Cycle colours", isOn: Binding(
                    get: { model.light.colorful }, set: model.setColorful))
                Spacer(minLength: 0)
            }
            .toggleStyle(.checkbox)
        }
    }

    private var effectOutputCard: some View {
        InkCard(title: "Output") {
            SteppedSlider(label: "Brightness", value: model.light.brightness,
                          enabled: model.light.mode != 0) { value, preview in
                model.updateBrightness(value, preview: preview)
            }
            InkRow("Power") {
                InkButton("Turn lights off", icon: "lightbulb.slash",
                          action: model.turnLightsOff)
                    .disabled(model.light.mode == 0)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Per-key

    private var paintCard: some View {
        InkCard(title: "Paint",
                detail: "Every tool uploads one complete, verified frame.") {
            InkRow("Brush") {
                ColorPopoverButton(
                    label: "Brush", color: $model.brush,
                    swatches: model.recentColors,
                    onSaveSwatch: { model.saveColor($0) },
                    onRemoveSwatch: model.removeSavedColor,
                    onClearSwatches: model.clearSavedColors,
                    calibration: $model.calibration,
                    calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                    onCalibrationPreview: model.previewRawColor,
                    onCalibrationCommit: model.applyKeys)
                    .frame(width: 220)
                Toggle(isOn: $erasing) { Label("Erase", systemImage: "eraser") }
                    .toggleStyle(.button)
                Spacer(minLength: 0)
            }

            InkRow("History") {
                InkButton("Undo", icon: "arrow.uturn.backward") { model.undoKeys() }
                    .disabled(!model.canUndoKeys)
                InkButton("Redo", icon: "arrow.uturn.forward") { model.redoKeys() }
                    .disabled(!model.canRedoKeys)
                Spacer(minLength: 0)
            }

            InkRow("Fill") {
                InkButton("Fill all") { model.replaceKeys(with: Paint.solid(model.brush)) }
                InkButton("Rainbow")  { model.replaceKeys(with: Paint.rainbowHorizontal()) }
                InkButton("Random")   { model.replaceKeys(with: Paint.random()) }
                InkButton("Clear")    { model.replaceKeys(with: [:]) }
                Spacer(minLength: 0)
            }

            // Stacked, not three-across: three 200pt controls in one row overflow
            // the 351pt control column at the 700pt minimum with no way to reflow.
            InkRow("Gradient from") {
                ColorPopoverButton(label: "Gradient start", color: $model.gradientStart,
                                   swatches: model.recentColors,
                                   onSaveSwatch: { model.saveColor($0) },
                                   onRemoveSwatch: model.removeSavedColor,
                                   onClearSwatches: model.clearSavedColors,
                                   calibration: $model.calibration,
                                   calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                                   onCalibrationPreview: model.previewRawColor,
                                   onCalibrationCommit: model.applyKeys)
                    .frame(width: 240)
                Spacer(minLength: 0)
            }
            InkRow("Gradient to") {
                ColorPopoverButton(label: "Gradient end", color: $model.gradientEnd,
                                   swatches: model.recentColors,
                                   onSaveSwatch: { model.saveColor($0) },
                                   onRemoveSwatch: model.removeSavedColor,
                                   onClearSwatches: model.clearSavedColors,
                                   calibration: $model.calibration,
                                   calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                                   onCalibrationPreview: model.previewRawColor,
                                   onCalibrationCommit: model.applyKeys)
                    .frame(width: 240)
                Spacer(minLength: 0)
            }
            InkRow("") {
                InkButton("Apply gradient") {
                    model.replaceKeys(with: Paint.gradient(model.gradientStart,
                                                           model.gradientEnd))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var perKeyOutputCard: some View {
        InkCard(title: "Output") {
            SteppedSlider(label: "Brightness", value: model.light.brightness,
                          enabled: true) { value, preview in
                model.updateBrightness(value, preview: preview, forPerKey: true)
            }
            InkRow("Save as") {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                InkButton("Save preset") {
                    if model.savePreset(named: presetName, perKey: true) { presetName = "" }
                }
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
        }
    }
}
```

---

## 5. NEW COMPONENTS

All in `src/AppViews.swift` unless noted. `Ink` lives in `src/InkTheme.swift`.

### `InkRule` — replaces every `Divider()`

```swift
struct InkRule: View {
    enum Axis { case horizontal, vertical }
    @Environment(\.colorSchemeContrast) private var contrast
    var axis: Axis = .horizontal
    init(_ axis: Axis = .horizontal) { self.axis = axis }

    var body: some View {
        Rectangle()
            .fill(contrast == .increased ? Ink.hairlineHi : Ink.hairline)
            .frame(width: axis == .vertical ? Ink.hairlineWidth : nil,
                   height: axis == .horizontal ? Ink.hairlineWidth : nil)
    }
}
```

`Divider()` at its default opacity is effectively invisible on `#000000`; this is 1.70:1 (6.14:1 under Increase Contrast) and is the app's single structural line.

### `InkStage` — the shared full-bleed preview

```swift
/// The preview region: pitch-black ground, no plate, no radius, no inset, a
/// bottom fade into the ground, and up to two 11pt captions floating on the fade.
///
/// The fade is an OVERLAY, not a .mask(). A layer mask over an
/// NSViewRepresentable-hosted WKWebView is unreliable across compositing paths;
/// an overlay fading to an opaque literal black is pixel-identical here and
/// touches nothing about the web view.
struct InkStage<Content: View>: View {
    var caption: String = ""
    var trailing: String? = nil
    var scrim: CGFloat = 28
    @ViewBuilder let content: Content

    var body: some View {
        content
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: scrim)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: Ink.s8) {
                    if !caption.isEmpty {
                        Text(caption).font(Ink.caption()).foregroundStyle(Ink.text)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: Ink.s8)
                    if let trailing {
                        Text(trailing).font(Ink.mono()).foregroundStyle(Ink.textSecond)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Ink.panelGutter)
                .padding(.bottom, Ink.s8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)   // the board itself is already labelled
            }
            .background(Ink.ground)
    }
}
```

### `InkCard` — replaces `ControlSurface` and `SectionTitle`

```swift
struct InkCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var title: String? = nil
    var detail: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.s8) {
            if title != nil || detail != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title).font(Ink.sectionTitle).foregroundStyle(Ink.text)
                    }
                    if let detail {
                        Text(detail).font(Ink.caption()).foregroundStyle(Ink.textSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, Ink.s4)
            }
            content
        }
        .padding(Ink.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.rCard, style: .continuous)
            .fill(Ink.surface))
        .overlay(RoundedRectangle(cornerRadius: Ink.rCard, style: .continuous)
            .strokeBorder(contrast == .increased ? Ink.hairlineHi : Ink.hairline,
                          lineWidth: Ink.hairlineWidth))
    }
}
```

Use `.strokeBorder`, never `.stroke` — `.stroke` straddles the path and leaves a half-pixel haze on black.

The card's `#121216` fill is **1.12:1** against the ground. That is stated honestly: the card is identified by its **title** and its **1pt border**, not by its fill. Nothing in the design depends on perceiving the fill step.

### `InkPage` — one inset, one measure, applied once

```swift
struct InkPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Ink.s16) { content }
            .padding(Ink.pagePad)
            .frame(maxWidth: Ink.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

### `InkRow` — the label/control unit

```swift
/// A fixed 96pt leading label column and a flexible control. A plain HStack, not
/// Grid + LabeledContent: LabeledContent renders its own label/content pair inside
/// ONE grid cell, so a Grid's column sizing would not align anything.
struct InkRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(Ink.body())
                .foregroundStyle(Ink.textSecond)
                .frame(width: Ink.labelColumn, alignment: .leading)
            content
        }
        .frame(minHeight: Ink.rowControl)
        .accessibilityElement(children: .contain)
    }
}
```

### `InkButton` — a View, not a ButtonStyle

```swift
/// A View wrapper, deliberately NOT a ButtonStyle: a ButtonStyle is not a view
/// and never receives environment values, so `@Environment(\.isEnabled)` and any
/// injected token inside one silently return their defaults forever.
struct InkButton: View {
    enum Tone { case normal, accent, destructive }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    var icon: String? = nil
    var tone: Tone = .normal
    let action: () -> Void

    init(_ title: String, icon: String? = nil, tone: Tone = .normal,
         action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tone = tone; self.action = action
    }

    private var fill: Color {
        guard isEnabled else { return Ink.well }
        return tone == .accent ? Ink.accent : Ink.well
    }
    private var ink: Color {
        guard isEnabled else { return Ink.textDisabled }
        switch tone {
        case .accent:      return Ink.onAccent       // 6.34:1, measured
        case .destructive: return Ink.bad
        case .normal:      return Ink.text
        }
    }
    private var border: Color {
        guard isEnabled else { return contrast == .increased ? Ink.hairlineHi : Ink.hairline }
        return tone == .accent ? .clear : (contrast == .increased ? Ink.strokeHi : Ink.stroke)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
                Text(title).font(Ink.caption(tone == .accent ? .semibold : .regular))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .frame(height: Ink.button)
            .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                .strokeBorder(border, lineWidth: Ink.hairlineWidth))
            .contentShape(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
```

Disabled state is an explicit **colour** (`Ink.textDisabled`, 5.23:1 on ground), never `.opacity(0.35)` on the whole control — an 0.35 opacity multiplier is what puts the colour button's hex readout at 2.8:1 for the 11 of 20 modes that do not use colour.

### `InkNotice` — the one advisory row

```swift
/// One component for: the panel's unapplied warning, Lighting's not-confirmed
/// row, presets.lastError, the Clock safety notice and the login-approval
/// guidance — five bespoke Labels today. ALWAYS mounted outside a scroller.
struct InkNotice: View {
    let text: String
    var systemImage: String = "exclamationmark.circle"
    var tint: Color = Ink.warn
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(_ text: String, systemImage: String = "exclamationmark.circle",
         tint: Color = Ink.warn, actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.text = text; self.systemImage = systemImage; self.tint = tint
        self.actionTitle = actionTitle; self.action = action
    }

    var body: some View {
        HStack(spacing: Ink.s8) {
            Rectangle().fill(tint).frame(width: 2)
            Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(tint)
            Text(text).font(Ink.caption()).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Ink.s8)
            if let actionTitle, let action { InkButton(actionTitle, action: action) }
        }
        .padding(.horizontal, Ink.s12)
        .padding(.vertical, Ink.s8)
        .frame(minHeight: 34)
        .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
            .fill(tint.opacity(0.10)))
        .accessibilityElement(children: .combine)
    }
}
```

### `ConnectionDot` — the single status vocabulary

```swift
/// Replaces ConnectionBadge AND StatusFooter's second, contradictory icon set.
/// Appears exactly once per surface: the panel footer, and the editor sidebar's
/// DeviceBlock. The status sentence and Retry sit beside it, never elsewhere.
private struct ConnectionDot: View {
    @ObservedObject var device: AulaDevice

    var body: some View {
        HStack(spacing: 6) {
            if device.phase == .applying || device.phase == .connecting
                || device.phase == .searching {
                ProgressView().controlSize(.small).scaleEffect(0.6)
                    .frame(width: 8, height: 8)
            } else {
                Circle().fill(tint).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(Ink.stroke, lineWidth: 0.5))
            }
            Text(label).font(Ink.caption(.medium)).foregroundStyle(Ink.textSecond)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard connection: \(label)")
    }

    private var tint: Color {
        switch device.phase {
        case .ready:   return Ink.ok
        case .failed:  return Ink.warn
        default:       return Ink.textDisabled
        }
    }

    private var label: String {
        switch device.phase {
        case .ready: return "Connected"
        case .applying: return "Applying"
        case .connecting, .searching: return "Connecting"
        case .failed: return "Needs attention"
        case .disconnected: return "Offline"
        }
    }
}
```

### `InkSidebar` / `InkNavRow` / `DeviceBlock`

```swift
private struct InkNavRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let tab: EditorTab
    let dirty: Bool
    @Binding var selection: Int

    private var selected: Bool { EditorTab.clamped(selection) == tab }

    var body: some View {
        Button { selection = tab.rawValue } label: {
            HStack(spacing: Ink.s8) {
                Image(systemName: tab.symbol).font(.system(size: 13))
                    .frame(width: 20, alignment: .center)
                Text(tab.title).font(Ink.row(selected ? .semibold : .regular))
                Spacer(minLength: 6)
                if dirty { Circle().fill(selected ? Ink.onAccent : Ink.accent)
                                   .frame(width: 5, height: 5) }
            }
            .foregroundStyle(selected ? Ink.onAccent : Ink.text)
            .padding(.horizontal, Ink.s8)
            .frame(height: Ink.rowNav)
            .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                .fill(selected ? Ink.accent : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable()
        // Arrow keys move between sections while a row has focus. NO
        // .keyboardShortcut here: CommandMenu already owns ⌘1–⌘4.
        .onMoveCommand { direction in
            switch direction {
            case .up:   selection = max(0, selection - 1)
            case .down: selection = min(EditorTab.allCases.count - 1, selection + 1)
            default:    break
            }
        }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(dirty ? "Has changes that are not on the keyboard" : "")
    }
}

private struct InkSidebar: View {
    @ObservedObject var model: AppModel

    private var lightingDirty: Bool {
        model.lightHasUnappliedChanges || model.keysHaveUnappliedChanges
    }

    private func dirty(_ tab: EditorTab) -> Bool {
        switch tab {
        case .lighting: return lightingDirty
        case .clock:    return false
        case .presets:  return model.presets.lastError != nil
        case .settings: return model.configHasUnappliedChanges
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AULA S98 Pro").font(Ink.sidebarTitle).foregroundStyle(Ink.text)
                Text("Lighting and keyboard control")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Ink.s16).padding(.vertical, Ink.s12)
            .frame(minHeight: 66, alignment: .leading)

            InkRule()

            // A plain VStack of buttons shaped like an AppKit source list, NOT a
            // List and NOT NavigationSplitView: both are ScrollViews, and
            // ImageRenderer gives a ScrollView no viewport, so all four tab
            // renders would collapse to chrome. Four rows never overflow 600pt,
            // so no scroller is needed at all.
            VStack(spacing: 2) {
                ForEach(EditorTab.allCases) { tab in
                    InkNavRow(tab: tab, dirty: dirty(tab), selection: $model.selectedTab)
                }
            }
            .padding(.horizontal, 10).padding(.top, Ink.s12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sections")

            Spacer(minLength: Ink.s12)
            InkRule()
            DeviceBlock(device: model.device)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.ground)
    }
}

private struct DeviceBlock: View {
    @ObservedObject var device: AulaDevice

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.s8) {
            ConnectionDot(device: device)
            Text(device.status)
                .font(Ink.mono()).foregroundStyle(Ink.textSecond)
                .lineLimit(2).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if device.phase == .disconnected || device.phase == .failed {
                    InkButton("Retry") { device.retryConnection() }
                }
                InkButton("Quit") { NSApp.terminate(nil) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Ink.s16).padding(.vertical, Ink.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

### `InkSectionBar`

```swift
struct InkSectionBar<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title; self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: Ink.s12) {
            Text(title).font(Ink.sectionTitle).foregroundStyle(Ink.text)
            Spacer(minLength: Ink.s12)
            trailing
        }
        .padding(.horizontal, Ink.pagePad)
        .frame(height: 44)
    }
}
```

### `PresetMenu` + `PresetSwatchImage`

```swift
/// A preset described the same way on both surfaces. The panel's flat, anonymous
/// Button list is replaced by two Sections with the same calibration-corrected
/// swatch the editor's PresetRow shows.
enum PresetSwatchImage {
    static func make(_ color: RGB8) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: 3, yRadius: 3)
        NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                blue: CGFloat(color.b) / 255, alpha: 1).setFill()
        path.fill()
        NSColor(white: 0.4, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        return image
    }
}

private struct PresetMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(PresetStore.builtIns) { preset in
                    Button { model.apply(preset) } label: {
                        Label { Text(preset.name) }
                        icon: { Image(nsImage: PresetSwatchImage.make(
                            model.displayColor(preset.swatch) )) }
                    }
                }
            }
            if !model.presets.userPresets.isEmpty {
                Section("Your presets") {
                    ForEach(model.presets.userPresets) { preset in
                        Button { model.apply(preset) } label: {
                            Label { Text(preset.name) }
                            icon: { Image(nsImage: PresetSwatchImage.make(
                                model.displayColor(preset.swatch) )) }
                        }
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "square.stack")
                .font(Ink.caption()).foregroundStyle(Ink.text)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
```

### `AppModel.strokeKeys` — wiring the dead highlight path

```swift
// In AppModel:
/// The keys touched by the stroke in progress. KeyCapView has drawn a 1.6pt
/// selection stroke and KeyboardWebController has shipped kbSetHighlight since
/// they were written, and no shipping call site has ever passed a non-empty set.
@Published private(set) var strokeKeys: Set<Int> = []
private var strokeClearWork: DispatchWorkItem?

// paintKey(_:erase:) — after the guard:
    strokeClearWork?.cancel()
    strokeKeys.insert(id)

// endPainting() — at the top, before the baseline guard:
    strokeClearWork?.cancel()
    let clear = DispatchWorkItem { [weak self] in self?.strokeKeys = [] }
    strokeClearWork = clear
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: clear)

// replaceKeys(with:) — at the top:
    strokeClearWork?.cancel()
    strokeKeys = []
```

No bridge change, no new JS, no hover event. Deterministic offscreen: a fresh snapshot model has an empty set.

### `EffectGrid` — restyled, same API plus `columns`

Keep the component and its behaviour verbatim; change only the chrome:

- Cell: `Ink.well` fill, 1pt `Ink.stroke` border, `Ink.rControl` radius, `minHeight: Ink.rowCell` (34).
- Label: **11pt**, `lineLimit(2)`, `minimumScaleFactor(0.85)` (up from 10pt / 0.7, which rendered "Colorful vertical and horizontal" at 7pt).
- Selected: `Ink.accent` fill, `Ink.onAccent` label, no border.
- The per-mode indicator dot is unchanged **except** that when the cell is selected it gains a 1pt `Ink.onAccent` ring, so a colour dot that happens to match the accent cannot vanish on exactly the cell you are looking at.
- `.help()`, `.accessibilityLabel`, `.accessibilityHint` and `.isSelected` unchanged.
- The `compact` parameter is deleted; `columns` alone drives density (3 in the panel, 4 in the editor).

### `SteppedSlider` — kept, restyled

Keep the real `Slider`, its `(Int, Bool)` preview/commit contract, its `.accessibilityValue("N of 5")` and its arrow-key adjustment. Change only: label width 72 → `Ink.labelColumn` (96) so it aligns with `InkRow`; label 12pt `Ink.textSecond`; value 11pt monospaced in a 20pt trailing column; disabled uses `Ink.textDisabled` rather than `.opacity(0.42)`.

**Do not** replace it with a row of dots. Six 7pt dots discards arrow-key adjustment, the VoiceOver adjustable trait and any usable hit target, in the app's single most-used control.

### `ColorPopoverButton` / `ColorEditor` — bounded restyle

Structure untouched (snapshot gates 7 and 8 depend on the `Calibrate`/`Done` toggle at `:130-136` and the `if calibrationMode` branch at `:145`). Changes only:

| Line | From | To |
|---|---|---|
| `:41`, `:141`, `:213`, `:302`, `:502`, `:695`, `:732` | `Color.primary.opacity(0.2…0.25)` | `Ink.stroke` |
| `:56` | `.fill(Color.primary.opacity(0.065))` | `.fill(Ink.well)` + `.strokeBorder(Ink.stroke, lineWidth: 1)` |
| `:58` | `.opacity(enabled ? 1 : 0.45)` | keep swatch/chevron at full; label + hex take `Ink.textDisabled` |
| `:234`, `:240` | `Color.primary.opacity(0.15…0.6)` | `Ink.stroke` / `Ink.textSecond` |
| all `.foregroundStyle(.secondary)` | — | `Ink.textSecond` |
| all 9pt / 10pt text | — | 11pt |
| `:276-277` | `.padding(16).frame(width: 320)` | add `.background(Ink.surface)` |
| `:771` | `.background(Color(nsColor: .windowBackgroundColor))` | `.background(Ink.ground)` |

Never pass `label: ""` — `ColorPopover.swift:59` uses it as the accessibility label.

### Retired

`ControlSurface`, `SectionTitle`, `ConnectionBadge`, `StatusFooter`, `EffectIdentificationView`, `EffectGrid.compact`.

---

## 6. FEATURE MAP

| # | Audited feature | Now lives at |
|---|---|---|
| 1 | Menu-bar icon reflects live connection | Unchanged (`AulaCompanion.swift:204-207`) |
| 2 | Panel identity: "AULA S98 Pro" + "Native USB control" | Panel identity bar, 50pt (both strings kept) |
| 3 | ConnectionBadge, 5 phases | `ConnectionDot` — panel footer; editor sidebar `DeviceBlock` |
| 4 | Read-only preview of the current effect frame | Panel `InkStage`, 410 × 152, full bleed |
| 5 | Current effect name readout | Panel "Effect" header row **and** the stage's bottom-left caption |
| 6 | Effect grid, 20 modes, dot, selection, tooltip, a11y hint | `EffectGrid` — panel 3 columns, editor Lighting 4 columns |
| 7 | Colour picker button (swatch, label, hex, calibrated fill) | Panel Controls card; editor Effect card; Paint card (Brush); Gradient from / Gradient to rows |
| 8 | Circular colour wheel + arrow nudge + VO sliders + LRU cache | `ColorPopover.swift` — unchanged |
| 9 | Colour brightness slider + hue°/sat% readout | `ColorPopover.swift` — unchanged, 11pt |
| 10 | Saved swatches (12, +, Remove, Clear, right-click) | `ColorPopover.swift` — unchanged |
| 11 | Hex entry + Apply + invalid indicator | `ColorPopover.swift` — unchanged |
| 12 | "Show the keyboard's real colours" toggle | `ColorPopover.swift` — unchanged |
| 13 | Calibrate / Done switch | `ColorPopover.swift:130-136` — **must not move** |
| 14 | Dual-wheel calibration | `ColorPopover.swift:556-701` — unchanged |
| 15 | Show on keyboard / Add data point / sample list / Clear all / summary | `ColorPopover.swift` — unchanged |
| 16 | Uncommitted colour committed on popover close | `ColorPopover.swift:278-284` — unchanged |
| 17 | Brightness 0–5, live preview, commit on release | Panel Controls card; editor Output card (both sources) |
| 18 | Lights off | Panel action row; editor Effect-source **Output → Power** row |
| 19 | Presets quick-apply (panel) | `PresetMenu` — now sectioned Built-in / Your presets, each with a swatch |
| 20 | Sync keyboard clock now | Panel action row; Clock section |
| 21 | Unapplied-change warning + Apply again (panel) | `InkNotice`, **pinned outside the scroller** |
| 22 | StatusFooter: phase, status string (truncated middle), Retry | Panel footer row 1; editor `DeviceBlock`. Phase is the dot's colour. |
| 23 | Open full editor | Panel footer, **⌘E** (button + CommandMenu). `.defaultAction` removed. |
| 24 | Quit | Panel footer; editor `DeviceBlock` |
| 25 | Fixed panel geometry | 410 × **660** (was 600) |
| 26 | Editor 840×720, min 700×600, autosave, single instance | `EditorWindow.swift` — unchanged, plus `appearance = .darkAqua` |
| 27 | Tab picker | `InkSidebar`, 176pt, 4 rows + change pips |
| 28 | ⌘1–⌘4 open a tab | `CommandMenu` unchanged; ⌘5 / Identify deleted; **⌘E** added |
| 29 | Lighting-source picker + summary line | `InkSectionBar` trailing picker; summary is the stage's bottom-left caption |
| 30 | Per-key canvas: click, drag, Tab-focus, one undo per stroke | The stage in per-key mode — same position, same size |
| 31 | Canvas caption reporting calibration state | Stage bottom-right caption |
| 32 | Speed 0–5, disabled for non-animated | Panel Controls card (**new to the panel**); editor Effect card |
| 33 | Reverse direction | Panel Controls card (**new**); editor Effect card → Animation row |
| 34 | Cycle colours | Panel Controls card (**new**); editor Effect card → Animation row |
| 35 | Brush colour picker | Paint card → Brush row |
| 36 | Erase toggle | Paint card → Brush row |
| 37 | Undo / Redo (30-deep) | Paint card → History row (**not** a global ⌘Z — see §11) |
| 38 | Fill all | Paint card → Fill row |
| 39 | Rainbow fill | Paint card → Fill row |
| 40 | Random fill | Paint card → Fill row |
| 41 | Clear all keys | Paint card → Fill row |
| 42 | Two-colour gradient + Apply | Paint card → Gradient from / Gradient to / Apply gradient rows |
| 43 | Save per-key layout as named preset | Per-key Output card → Save as row |
| 44 | Unapplied warning both sources + Upload/Apply again | `InkNotice` pinned below the Lighting scroller |
| 45 | Clock: live date + seconds time | Clock card, 30pt monospaced digits (fixed date in `snapshotMode`) |
| 46 | Automatic clock sync toggle + explanation | Clock card |
| 47 | Sync now + last-sync line | Clock card |
| 48 | Clock safety notice | Clock card footer, `InkNotice` in `Ink.warn` |
| 49 | Built-in presets (5) with swatch, summary, Apply | Presets → card "Built-in" |
| 50 | User presets + empty state | Presets → card "Your presets" |
| 51 | PresetRow: swatch, name, Built-in badge, summary, Apply, overflow | `PresetRow` — badge now an 11pt pill; Apply always visible |
| 52 | Replace with current | `PresetRow` overflow menu |
| 53 | Rename… (sheet, ⏎, blank rejected) | Unchanged |
| 54 | Delete (alert naming the preset) | Unchanged |
| 55 | Save current effect as preset | `InkSectionBar` trailing: name field + Save current effect |
| 56 | Export to JSON (NSSavePanel + alert) | Section bar `ellipsis.circle` menu |
| 57 | Import from JSON (1 MB cap, legacy fallback, alert) | Section bar `ellipsis.circle` menu |
| 58 | Preset store error banner | `InkNotice` + the sidebar's Presets change pip |
| 59 | Sleep after | Settings → Keyboard behaviour |
| 60 | Key response | Settings → Keyboard behaviour |
| 61 | Disable Win / Alt+F4 / Alt+Tab | Settings → Keyboard behaviour |
| 62 | Reset form / "Not applied" / Apply to keyboard (⏎) | Settings → Keyboard behaviour |
| 63 | "confirmed from this Mac" line | Keyboard behaviour card's `detail:` |
| 64 | Calibration status + Applied/Uncorrected badge | Settings → LED colour calibration |
| 65 | Live tests R / G / B / W | Settings → LED colour calibration |
| 66 | Reset calibration | Settings → LED colour calibration |
| 67 | "Shown on screen as" swatch + hex | Settings → LED colour calibration |
| 68 | Reapply current effect | Settings → LED colour calibration |
| 69 | Start at login + approval guidance | Settings → Application (`InkNotice`) |
| 70 | Reveal log in Finder | Settings → Application |
| 71 | App version string | Settings → Application |
| 72 | About text | Settings, closing paragraph, `maxWidth: 560` |
| 73 | `snapshotMode`: `VScroll` → stack, `KeyboardView` → flat | Preserved verbatim; see §9 |
| 74 | Identify tab | **Removed** (§7) — its data product survives as the baked-in names + the new Settings escape hatch |

---

## 7. IDENTIFY REMOVAL

**Labels are still READ.** `labelForMode()` keeps consulting `modeLabels` exactly as it does today. This is the owner's instruction and it overrides the unanimous "option (a)" recommendation from all four directions — and it is also the *lower-risk* choice, because it leaves `tests/AulaLogicTests.swift:344-368` compiling and passing untouched, and `verify.sh:17-22` runs those tests before a single pixel is rendered.

The one thing option (b) owes the user is an escape hatch, since a wrong hand-typed label would otherwise haunt them with no UI to inspect or clear it. That is the **Effect names** row in Settings → LED colour calibration:

```swift
// In SettingsSection's calibration card, after "Reset calibration":
if !model.modeLabels.isEmpty {
    InkRow("Effect names") {
        Text("\(model.modeLabels.count) custom effect name\(model.modeLabels.count == 1 ? "" : "s") recorded")
            .font(Ink.caption()).foregroundStyle(Ink.textSecond)
        Spacer(minLength: Ink.s8)
        InkButton("Use the manual's names") {
            for mode in model.modeLabels.keys { model.clearModeLabel(for: mode) }
        }
        .help("Discard your recorded names and fall back to the keyboard manual's twenty effect names")
    }
}
```

Six lines. It uses `clearModeLabel` (already public, already tested), it is invisible for every user who never used Identify, and it closes the audit's PRIMARY RISK without keeping the tab.

### Exact edit list

| File | Line(s) | Edit |
|---|---|---|
| `src/AppViews.swift` | 612 | Delete `Text("Identify").tag(4)` — the whole `Picker` goes anyway (replaced by `InkSidebar`) |
| `src/AppViews.swift` | 620-628 | Replace the `switch` with the total `EditorTab` switch; **no `default:` arm** |
| `src/AppViews.swift` | **882-1058** | Delete `EffectIdentificationView` entirely, including `modeButton(_:)`, `effectButton(_:)`, `linkRow(_:)`, `selectedMode`, `notice`, `effectNumbers`, `activeMode`, `alreadyNamed`, `unnamedCount` |
| `src/AulaCompanion.swift` | 219-220 | Delete the `Button("Identify")` entry and its ⌘5. **No renumbering** — Lighting/Clock/Presets/Settings keep ⌘1–⌘4 |
| `src/AulaCompanion.swift` | 209-222 | Add `Divider()` then `Button("Open Editor") { EditorWindowController.shared.show(model: model) }.keyboardShortcut("e", modifiers: .command)` |
| `src/AulaCompanion.swift` | 44 | `let tab = EditorTab.clamped(Int(environment["AULA_TAB"] ?? "0") ?? 0).rawValue` |
| `src/EditorWindow.swift` | 14 | `if let tab { model.selectedTab = EditorTab.clamped(tab).rawValue }` |
| `src/AppViews.swift` | 589-592 | `EditorView.init` clamps identically |
| `scripts/verify.sh` | 62 | `for tab in 0 1 2 3; do` |
| `scripts/verify.sh` | 70-76 | Replace the `AULA_DARK` block (§9) |
| `scripts/verify.sh` | 87, 160 | **Unchanged** — the count stays at 9 |
| `src/AulaDevice.swift` | 349 | Reword the doc comment: `/// Recorded so every mode can report the effect number its LCD shows, not to rename anything.` |
| `README.md` | 52 | Delete the Identify bullet |
| `README.md` | 84-93 | Rewrite "Identifying unnamed effects" in the past tense: the mapping is complete and baked in (`kKeyboardEffects`, `kNamedModeEffects`, `kManualEffectNames`); custom names recorded before the tab was retired are still honoured and can be discarded from Settings › LED colour calibration › Effect names |
| `README.md` | 159 | Keep — reword "The Identify tab was used to record…" to past tense |

### Kept, deliberately

- **`~/Library/Application Support/Aula S98 Pro Companion/mode-labels.json`** — never deleted, still read at `AppModel.swift:85-91`, still written at `:93-98`, still migrated at `:131-135`.
- **`AppModel.setModeLabel`, `clearModeLabel`, `nextUnnamedMode`, `recordedEffectNumber`, `modeLabels`, `StoredWorkspace.modeLabels`** — all kept. `setModeLabel` and `nextUnnamedMode` have no UI caller, but Swift emits no warning for an unused internal method on a class, so `-warnings-as-errors` does not fire, and `tests/AulaLogicTests.swift:344-368` exercises every one of them. **Zero test changes.**
- **The baked-in maps** `kManualEffectNames` (20), `kNamedModeEffects` (9), `kKeyboardEffects` (11) — byte-for-byte. `tests:90-118` asserts they partition 1…20 exactly.
- **The CLI `aula-s98 identify`** (`src/aula-s98.c:272, 341, 387-389, 450`) — a different feature (it steps the hardware through modes so you can read the LCD), and `verify.sh:30` checks its `--help` text.

---

## 8. ACCESSIBILITY AND CONTRAST

### Measured ratios (WCAG 2.1 relative luminance, sRGB)

| Foreground | on `ground` #000000 | on `surface` #121216 | on `well` #1C1C22 | Verdict |
|---|---|---|---|---|
| `text` #F2F3F5 | **18.91:1** | **16.83:1** | **15.27:1** | AAA |
| `textSecond` #A7ACB6 | **9.22:1** | **8.20:1** | **7.44:1** | AAA |
| `textDisabled` #7A7F8A | **5.23:1** | **4.65:1** | 4.22:1 | AA (and 1.4.3-exempt as inactive) |
| `accent` #FF5A1F | **6.73:1** | **5.99:1** | — | AA |
| `warn` #FFB020 | **11.48:1** | 10.22:1 | — | AAA |
| `ok` #30D158 | **10.39:1** | 9.24:1 | — | AAA |
| `bad` #FF453A | **6.16:1** | 5.48:1 | — | AA |
| `onAccent` #0A0A0C **on accent** | **6.34:1** | — | — | AA — fixed, not per-user |

| Boundary | vs `ground` | vs `surface` | Requirement |
|---|---|---|---|
| `stroke` #616169 — every interactive boundary | **3.42:1** | **3.04:1** | 1.4.11 ≥ 3:1 ✓ |
| `hairline` #34343C — grouping rules, card borders | 1.70:1 | 1.61:1 | Decorative by declaration ✓ |
| Increase Contrast: `strokeHi` #8A8A94 | **6.14:1** | 5.47:1 | ✓ |

**Stated honestly:** `surface` at 1.12:1 and `well` at 1.24:1 against `#000000` are *not* perceivable boundaries, and this design does not ask them to be. Every card is identified by its **17pt title** plus a 1pt border; every interactive control is identified by a **3.04:1 minimum** `stroke` border, a filled `accent` background, or both. Nothing in the app conveys meaning through a fill step alone. That is the answer to the failure mode all four directions shared — replacing eight invisible `Color.primary.opacity` washes with three-to-four invisible near-blacks.

**Increase Contrast is honoured**, despite frozen tokens: every component drawing a boundary reads `@Environment(\.colorSchemeContrast)` and promotes `hairline → hairlineHi` and `stroke → strokeHi`. This recovers what `Color.primary` / `Divider()` gave for free.

**Type floor is 11pt** everywhere — AppKit's own smallest standard label, and one point above the 10pt and 9pt this codebase currently uses for status text, badges, captions and the "Built-in" marker.

### Keyboard navigation

| Surface | Behaviour |
|---|---|
| Panel | Tab cycles the effect grid, colour button, sliders, checkboxes, action row, footer. **⌘E** opens the editor (button + `CommandMenu`). Escape dismisses. Return is bound to nothing here — the panel commits nothing. |
| Editor sidebar | Each row `.focusable()`; ↑/↓ move between sections via `onMoveCommand`; ⌘1–⌘4 from the `CommandMenu` (rows carry no shortcut, so there is no double ownership). |
| Effect grid | Tab-focusable buttons; Space/Return activates; `.isSelected` trait on the current mode. |
| Per-key canvas | Tab focuses individual keys (`KeyCapView`'s `Button` path); Space paints. `strokeKeys` now draws the 1.6pt selection stroke so a keyboard user can see where focus landed. |
| Sliders | Real `Slider`s — arrow keys adjust, `.accessibilityValue("N of 5")`. |
| Colour wheel | Arrow-key nudge (`onMoveCommand`) and a two-slider `accessibilityRepresentation` (Hue °, Saturation %) — unchanged. |
| Return | Only: Settings → Apply to keyboard; rename sheet → Rename; delete alert; calibrator → Add data point. One primary commit per surface, and Return never navigates. |

### VoiceOver

- `InkRow` is `.accessibilityElement(children: .contain)`; the control inside carries its own label, so nothing is double-announced.
- `ConnectionDot` combines to "Keyboard connection: Connected".
- `InkNotice` combines to one element; its action button stays separately focusable.
- `InkStage`'s overlaid captions are `.accessibilityHidden(true)` — the board itself is already labelled "AULA S98 Pro lighting preview" / "Per-key lighting editor" by `KeyboardView`.
- Sidebar rows carry `.isSelected` plus an `.accessibilityHint` of "Has changes that are not on the keyboard" when the pip is lit.
- Every `ColorPopoverButton` keeps a real, distinct `label:` — never `""`, which `ColorPopover.swift:59` uses as the accessibility label. The two gradient pickers stay "Gradient start" and "Gradient end".
- `EffectGrid` keeps `.accessibilityLabel(name)` and `.accessibilityHint("Uses the chosen colour" / "Generates its own colours")`.

---

## 9. SNAPSHOT SAFETY

### The nine renders after the rebuild

| # | Invocation | What it proves |
|---|---|---|
| 1 | `AULA_TAB=0` | Lighting, effect source: sidebar, stage, 20-cell grid, colour, speed, animation |
| 2 | `AULA_TAB=1` | Clock |
| 3 | `AULA_TAB=2` | Presets |
| 4 | `AULA_TAB=3` | Settings |
| **5** | **`AULA_TAB=0 AULA_SOURCE=perkey`** | **NEW.** The per-key paint inspector — brush, erase, undo/redo, fill tools, both gradient pickers, the save field. `LightingView` always defaulted to `.effect` offscreen, so none of this has *ever* been rendered. |
| 6 | `AULA_SNAPSHOT_PANEL=colour` | Wheel + swatches + hex |
| 7 | `AULA_SNAPSHOT_PANEL=calibration` | Dual-wheel calibrator |
| 8 | `AULA_SNAPSHOT_PANEL=menu` | The panel |
| **9** | **`AULA_SNAPSHOT_PANEL=menu AULA_MODE=0`** | **NEW.** The panel with the lights off: a different selected cell, an unlit stage, and colour + brightness + speed all in their disabled states. |

Count stays **9**. `verify.sh:87` (`-ne 9`) and the banner at `:160` need **no edit**.

### `verify.sh` diff

```sh
# line 62
for tab in 0 1 2 3; do

# replace lines 70-76 (the AULA_DARK block) with:
# The per-key source, which no render has ever reached: LightingView defaults to
# .effect offscreen, so the whole paint inspector was untested by the render smokes.
output="${verify_dir}/tab-0-perkey.png"
AULA_SNAPSHOT=1 AULA_TAB=0 AULA_SOURCE=perkey AULA_SNAPSHOT_OUT="${output}" \
  "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
test -s "${output}"
render_hashes="${render_hashes}$(md5 -q "${output}")\n"

# and after the panel loop at line 84, add:
output="${verify_dir}/panel-menu-off.png"
AULA_SNAPSHOT=1 AULA_SNAPSHOT_PANEL=menu AULA_MODE=0 AULA_SNAPSHOT_OUT="${output}" \
  "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
test -s "${output}"
render_hashes="${render_hashes}$(md5 -q "${output}")\n"

# after the distinctness check at line 90, add:
AULA_APP="${app}/Contents/MacOS/Aula S98 Pro Companion" python3 "${script_dir}/groundaudit.py" \
  "${verify_dir}"/tab-*.png "${verify_dir}/panel-menu.png" "${verify_dir}/panel-menu-off.png"
```

### `AulaCompanion.swift` snapshot-block diff

```swift
// Replace `let dark = environment["AULA_DARK"] == "1"` (line 46) with:
if environment["AULA_SOURCE"] == "perkey" { activeModel.lightingSource = .perKey }
if let raw = environment["AULA_MODE"], let m = Int(raw), (0...19).contains(m) {
    activeModel.light.mode = m       // persistsWorkspace is false here, so this is inert on disk
}

// panel == "menu"  (line 104-108):
renderer = ImageRenderer(content: AnyView(
    MenuPanelView(model: activeModel)
        .environment(\.snapshotMode, true)
        .environment(\.colorScheme, .dark)          // unconditional: the app is dark-only
        .background(Ink.ground)))

// colour / calibration (line 110-112):
renderer = ImageRenderer(content: AnyView(
    ColorEditorSnapshot(startCalibrating: panel == "calibration")
        .environment(\.colorScheme, .dark)))

// editor (line 116-125):
renderer = ImageRenderer(content: AnyView(
    EditorView(model: activeModel, initialTab: tab)
        .environment(\.snapshotMode, true)
        .environment(\.colorScheme, .dark)
        .frame(width: 840)
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.ground)))
```

`.environment(\.colorScheme, .dark)` is **injected by the host, never by the view**. Nothing inside `MenuPanelView` or `EditorView` sets `preferredColorScheme` or `colorScheme`, so the renderer's injection stays authoritative and the AppKit-drawn Sliders, Toggles, Pickers and TextFields paint their dark variants against the black ground offscreen exactly as they do at runtime.

### `scripts/groundaudit.py` — what replaces the dark render's job

The dark render existed because "the tab bodies once came out white-on-white offscreen because nothing painted a background." That regression is now structurally impossible (both roots paint `Ink.ground` explicitly), and it is directly asserted rather than inferred:

```python
#!/usr/bin/env python3
"""Ask #1, tested directly: every editor and panel render must be painted on a
literally pitch-black ground AND must actually contain a UI.

Pixel (0,0) == #000000 alone is satisfied by a completely blank frame — which is
exactly the vacuous pass the distinctness check exists to catch — so the colour
count is asserted alongside it."""
import subprocess, sys, tempfile, os

def rgba(path):
    out = tempfile.mktemp(suffix=".rgba")
    subprocess.run(["sips", "-s", "format", "png", path, "--out", out],
                   check=True, capture_output=True)
    from PIL import Image                      # falls back below if unavailable
    return Image.open(out).convert("RGB")

fail = []
for path in sys.argv[1:]:
    img = rgba(path)
    w, h = img.size
    corners = [img.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    if any(c != (0, 0, 0) for c in corners):
        fail.append(f"{os.path.basename(path)}: ground is {corners}, expected pitch black")
    distinct = len(set(img.getdata()))
    if distinct < 200:
        fail.append(f"{os.path.basename(path)}: only {distinct} distinct colours — the view collapsed")
    print(f"{os.path.basename(path):24s} ground=#000000 colours={distinct}")

if fail:
    for line in fail:
        print("FAIL " + line, file=sys.stderr)
    sys.exit(1)
```

*(If Pillow is not available on the machine, read the PNG via `sips -g` plus a raw `.rgba` dump; the three sibling gates already require `python3`.)*

### Snapshot-only plumbing that must not be dropped

1. **`VScroll` stays the only scrolling primitive on the snapshot path.** No bare `ScrollView`, `List`, `Form`, `NavigationSplitView`, `ScrollViewReader`, `.scrollPosition`, or `LazyVStack`-inside-a-scroller anywhere in either surface. This is exactly why `InkSidebar` is a plain `VStack` of buttons and why `InkRow` is an `HStack` rather than a `Form` row. `LazyVGrid` inside a `VScroll` is safe — the existing `EffectGrid` already does it and renders.
2. **`KeyboardView`'s `snapshotMode` branch stays**, and `KeyboardFlatView`'s internal `.aspectRatio(695/211, .fit)` is left untouched. Inside the stage box it resolves width-limited (410 × 124.5 in the panel, 840 × 255 offscreen in the editor) with `Ink.ground` above and below. Full width is preserved offscreen and on screen.
3. **No `GeometryReader` on the snapshot path.** One inside `.fixedSize(horizontal: false, vertical: true)` has zero ideal height and collapses the entire editor render.
4. **Renders 6 and 7 are distinguished only by `ColorEditorSnapshot`'s `startCalibrating` flag.** The `Calibrate`/`Done` toggle stays where it is; `ColorEditorSnapshot` (`:749-773`) is updated in the same commit as any `ColorEditor` change.
5. **Render 8 stays distinct from render 1** by construction: 410pt fixed frame, 3-column grid, no sidebar, versus an 840pt window with a 176pt source list and a 4-column grid. Do not later refactor `MenuPanelView` into a thin wrapper around `LightingSection`.
6. **Determinism.** In `snapshotMode`: the Clock renders `Date(timeIntervalSince1970: 1_700_000_000)` and `lastSync` renders the constant `"Not synced yet"`; `SettingsSection` reads `startsAtLogin = false` instead of the real `SMAppService.mainApp.status`. `Paint.random()` never reaches a snapshot path. `strokeKeys` is empty in a fresh snapshot model. Without these the hashes differ run to run, which passes the distinctness check vacuously and could hide a real collapse.

### Unaffected

The four `keyboard3d` renders, the live-window preview plus paint-bridge check (`AULA_UI_TEST=editor` still opens the real `EditorWindowController`, whose Lighting section still hosts a real `KeyboardPhotoView` with `onPaint` routed and a board far wider than 1pt), and the three python gates `roundtrip` / `hueaudit` / `hitboxaudit`.

---

## 10. IMPLEMENTATION ORDER

Ten steps. Run `scripts/verify.sh` after every one. Steps 1–4 are individually shippable; the UI rebuild lands as one commit at step 8 because retiring `ControlSurface` and `SectionTitle` touches all four sections at once.

**1. Tokens (no behaviour change).** Add `src/InkTheme.swift` with `Ink` and `Color(hex:)`. Nothing references it yet. `verify.sh` must pass unchanged — this proves the new file compiles under `-warnings-as-errors` and reaches both build paths.

**2. `EditorTab` + clamping (no visual change).** Add the enum. Clamp at `AulaCompanion.swift:44`, `EditorWindow.swift:14`, `AppViews.swift:589-592`. Leave the segmented picker and the tab-5 case in place for now — clamping to `0...3` while `case 4` still exists is harmless because nothing reaches 4 except `AULA_TAB=4`, which now renders Lighting. `verify.sh` still passes at 9 (tab-4 now hashes as Lighting… **it will collide with tab-0**), so do steps 2 and 3 in the same commit.

**3. Identify removal + snapshot re-plumbing (one commit with step 2).** Delete `EffectIdentificationView` (`882-1058`), the picker tag, the switch case, the `CommandMenu` entry and ⌘5. Add `AULA_SOURCE` and `AULA_MODE` to the snapshot block. Apply the `verify.sh` diff (`for tab in 0 1 2 3`, the perkey render, the menu-off render). Add `scripts/groundaudit.py`. Reword `AulaDevice.swift:349` and the README. **Sweep for orphans** — `-warnings-as-errors` turns every stranded `@State` or private helper into a build failure, not a warning. Expect the first two builds to fail here and nowhere else. **Tests are untouched** because labels are still read.

**4. Force dark appearance.** In `AulaCompanionApp.init()`, before anything else and guarded by `environment["AULA_SNAPSHOT"] != "1"`:
```swift
NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
```
In `EditorWindowController`, on the created window: `created.appearance = NSAppearance(named: .darkAqua)`. This is the single lever that carries popovers, sheets, alerts, `NSMenu`, `NSSavePanel`/`NSOpenPanel` and the titlebar — none of which `.preferredColorScheme` reliably reaches. Verify by eye on a Mac set to Light Mode: open the panel, the editor, the colour popover, the rename sheet, the delete alert and Export…, and confirm every one is dark.

**5. The preview.** Delete `.aspectRatio(kPreviewDisplayAspect, .fit)` and `.background(RoundedRectangle(cornerRadius: 10).fill(Color.black))` from `KeyboardView` (`AppViews.swift:144-154`) along with the comment at `:146-150`. Add `InkStage`. Panel: `.frame(width: 410, height: 152)`. Editor: `.frame(maxWidth: .infinity).aspectRatio(kPreviewDisplayAspect, .fit).frame(maxHeight: 320).layoutPriority(1)`. **Check with Digital Color Meter that the panel reads exactly #000000 on the real menu bar** — `MenuBarExtra(.window)` draws its own vibrancy, and if the opaque `Ink.ground` fill does not fully cover it the matte will show a faint seam. If it composites, back the root with an opaque layer rather than lightening the black.

**6. Primitives.** `InkRule`, `InkCard`, `InkPage`, `InkRow`, `InkButton`, `InkNotice`, `ConnectionDot`, `InkSectionBar`, `PresetSwatchImage`, `PresetMenu`. Restyle `EffectGrid` (columns only, no `compact`), `SteppedSlider` and `PresetRow`. Retire `ControlSurface`, `SectionTitle`, `ConnectionBadge`, `StatusFooter`.

**7. `AppModel.strokeKeys`.** The three edits in §5, and pass `highlight: model.strokeKeys` from the per-key stage.

**8. Rebuild both surfaces (one commit).** `MenuPanelView` per §3; `EditorView` + `InkSidebar` + the four sections per §4. This is the largest step and there is no incremental landing path — the four sections all lose `ControlSurface` and `SectionTitle` together.

**9. `ColorPopover` restyle.** The bounded table in §5. Structure untouched. Update `ColorEditorSnapshot`'s background in the same commit.

**10. Verify and measure.**
- `scripts/verify.sh` — 9 distinct renders, `groundaudit.py` green, all four `keyboard3d` renders distinct, live window + paint bridge, the three python gates.
- Run `verify.sh` **twice** and diff the nine hashes: they must be identical run to run. If not, the determinism guards in §9 item 6 are incomplete.
- Resize the editor to exactly 700 × 600 and page through all four sections in both lighting sources. Nothing may clip; every row in the Paint card must fit the 351pt control column; the stage must be 194pt tall and full width.
- Turn on System Settings › Accessibility › Display › **Increase contrast** and confirm every card border and control boundary promotes.
- VoiceOver pass: the panel top to bottom, then the editor sidebar, then the Paint card.

---

## 11. FLAWS EXPLICITLY DISMISSED (not fixed)

Every fatal flaw raised by the four critiques is addressed above except these five, which are dismissed on purpose:

1. **"The light palette exists only to keep a gate green" (Anodised).** Correct, and the fiction is removed rather than defended: there is **no light palette**. The app is dark-only, and the sixth render is replaced by `AULA_SOURCE=perkey`, which asserts something the design genuinely has. `groundaudit.py` tests ask #1 directly.

2. **Global ⌘Z / `CommandGroup(replacing: .undoRedo)` (Anodised, Stage).** Not implemented. `replacing:` deletes the standard Undo/Redo menu items outright with no fall-through, so text undo in the rename sheet and the hex field would be permanently worse — and the proposed `lightingSource == .perKey` gate is precisely the state in which the "Preset name" TextField is on screen. Undo/Redo stay as buttons in the Paint card's History row, exactly where they are today.

3. **A live, keyboard-derived accent (Stage).** Rejected. It was specified through `@Environment` inside a `ButtonStyle`, where SwiftUI never populates it; and even correctly wired, a value-clamped HSV floor is not a luminance floor and yields 1.6:1 black-on-blue primary labels. A fixed `#FF5A1F` with a measured `#0A0A0C` label at **6.34:1** is deterministic, needs no per-render branching, and is still the keyboard's own light.

4. **A numeric effect pad in the panel (Console).** Rejected. `mode.id` is the protocol byte 0–19; the LCD numbers are the 1–20 values `recordedEffectNumber(for:)` resolves, and the mapping is not the identity. Printing protocol bytes while claiming to mirror the LCD replaces twenty readable names with twenty numbers matching nothing the user can see. The panel keeps named cells at 3 columns, 34pt rows, 11pt labels — 122pt per cell, which fits the longest name on two lines.

5. **`DotStepper` replacing `SteppedSlider` (Canvas).** Rejected. Six 7pt dots with the value hidden discards arrow-key adjustment, the VoiceOver adjustable trait and any usable hit target, on the app's single most-used control, in exchange for restraint.
