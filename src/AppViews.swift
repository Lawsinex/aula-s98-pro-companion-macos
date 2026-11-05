import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Snapshot-friendly scrolling

/// `ImageRenderer` gives a `ScrollView` no viewport, so its content collapses and an
/// offscreen render comes out empty. That silently turned the CI render smokes into a
/// test of the window chrome only. In snapshot mode we lay the same content out in a
/// plain stack so the render shows what a user actually sees; at runtime this is an
/// ordinary ScrollView.
private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
private struct SnapshotViewportKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
    /// Editor captures have a fixed viewport; menu captures retain intrinsic height.
    var snapshotViewport: Bool {
        get { self[SnapshotViewportKey.self] }
        set { self[SnapshotViewportKey.self] = newValue }
    }
}

struct VScroll<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshotMode
    @Environment(\.snapshotViewport) private var snapshotViewport
    /// Bounds the scroller at runtime. Ignored offscreen, where the content is laid
    /// out in full rather than clipped to a viewport that does not exist.
    var height: CGFloat?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if snapshotMode && snapshotViewport {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 0) { content() }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }.clipped()
        } else if snapshotMode {
            VStack(alignment: .leading, spacing: 0) { content() }
        } else if let height {
            ScrollView { content() }.frame(height: height)
        } else {
            ScrollView { content() }
        }
    }
}

// MARK: - Keyboard preview and editor

private struct KeyCapView: View {
    let cap: KeyCap
    let color: RGB8
    let scale: Double
    let highlighted: Bool
    let onActivate: (() -> Void)?

    var body: some View {
        Group {
            if let onActivate {
                Button(action: onActivate) { keycap }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(cap.name) key")
                    .accessibilityValue(color == .black ? "unlit" : color.accessibleLabel)
                    .accessibilityHint("Activate to paint this key")
            } else {
                keycap.accessibilityHidden(true)
            }
        }
        .frame(width: cap.w * scale, height: cap.h * scale)
        .offset(x: cap.x * scale, y: cap.y * scale)
    }

    private var lit: Bool { color != .black }

    private var capShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(2.5, 3.5 * scale))
    }

    private var textColor: Color {
        guard lit else { return .white.opacity(0.72) }
        return color.relativeLuminance > 0.38 ? .black.opacity(0.78) : .white.opacity(0.94)
    }

    /// A keycap is lit from within and catches light along its top edge, so a flat
    /// fill reads as a coloured rectangle rather than a key.
    private var capFill: LinearGradient {
        let base = Color(color)
        let stops: [Color] = lit
            ? [base, base.opacity(0.8)]
            : [Color.white.opacity(0.10), Color.white.opacity(0.045)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    private var capEdge: LinearGradient {
        let stops: [Color] = lit
            ? [.white.opacity(0.55), .white.opacity(0.10)]
            : [.white.opacity(0.22), .white.opacity(0.06)]
        return LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    private var legend: some View {
        Text(cap.name)
            .font(.system(size: max(6.5, 7.7 * scale), weight: .medium))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var keycap: some View {
        let base = Color(color)
        let glow = lit ? base.opacity(0.75) : Color.clear
        let bloom = lit ? base.opacity(0.35) : Color.clear
        return capShape
            .fill(capFill)
            .overlay(capShape.strokeBorder(capEdge, lineWidth: 0.75))
            .overlay(capShape.stroke(Color.white, lineWidth: highlighted ? 1.6 : 0))
            .overlay(legend)
            // Two shadows: a tight one for the cap edge, and a wide soft one for the
            // bloom the LED actually throws onto the plate around it.
            .shadow(color: glow, radius: min(2.5, 2 * scale))
            .shadow(color: bloom, radius: min(7, 6 * scale))
    }
}

/// The keyboard preview.
///
/// A photograph of the real board, re-tinted per key from the same frame that goes
/// over USB. `ImageRenderer` cannot rasterise a WKWebView, so offscreen renders fall
/// back to the flat drawing — without that the render smokes would capture an empty
/// frame and pass, which is the exact failure they exist to catch.
struct KeyboardView: View {
    @Environment(\.snapshotMode) private var snapshotMode
    var colors: [Int: RGB8]
    var highlight: Set<Int> = []
    var effectName: String = ""
    var onPaint: ((Int) -> Void)?
    var onPaintEnded: (() -> Void)?

    var body: some View {
        Group {
            if snapshotMode {
                KeyboardFlatView(colors: colors, highlight: highlight,
                                 onPaint: onPaint, onPaintEnded: onPaintEnded)
            } else {
                // No aspect ratio and no plate here: frame ownership belongs to
                // the caller, so the board can be sized by WIDTH. Sizing it by
                // height is what letterboxed it into the middle of the panel —
                // 104pt of height resolved to 280pt of width inside a 378pt
                // column, and the 16pt padding was never the real defect.
                //
                // The plate is gone because the ground is now literally #000000:
                // the frames were shot on black, the page is transparent, so with
                // nothing behind it the matte and the desk reflection run out
                // into the app with no terminating edge at all.
                KeyboardPhotoView(colors: colors, highlight: highlight,
                                  effectName: effectName,
                                  onPaint: onPaint, onPaintEnded: onPaintEnded)
            }
        }
        .accessibilityElement(children: onPaint == nil ? .ignore : .contain)
        .accessibilityLabel(onPaint == nil ? "AULA S98 Pro lighting preview"
                                           : "Per-key lighting editor")
        .accessibilityRepresentation {
            if let onPaint {
                KeyboardPaintAccessibilityView(colors: colors, onPaint: onPaint,
                                               onPaintEnded: onPaintEnded)
            } else {
                Text("AULA S98 Pro lighting preview")
            }
        }
    }
}

/// The photograph is a canvas, so its pixels cannot become keyboard or VoiceOver
/// controls by themselves. Keep the native key actions separate from the page's
/// pointer hit map: an accessibility action never intercepts a photographic click.
enum KeyboardPaintAccessibility {
    static let keys = kKeyCaps

    static func label(for cap: KeyCap) -> String {
        let name: String
        switch cap.name {
        case "↑": name = "Up arrow"
        case "↓": name = "Down arrow"
        case "←": name = "Left arrow"
        case "→": name = "Right arrow"
        case "//": name = "Divide"
        default: name = cap.name
        }
        if cap.x >= 566 { return "Numpad \(name) key" }
        if ["Shift", "Ctrl", "Alt"].contains(name) {
            return "\(cap.x < 300 ? "Left" : "Right") \(name) key"
        }
        return "\(name) key"
    }

    static func activate(id: Int, onPaint: (Int) -> Void,
                         onPaintEnded: (() -> Void)?) {
        guard kLedIndices.contains(id) else { return }
        onPaint(id)
        onPaintEnded?()
    }
}

private struct KeyboardPaintAccessibilityView: View {
    let colors: [Int: RGB8]
    let onPaint: (Int) -> Void
    let onPaintEnded: (() -> Void)?

    var body: some View {
        VStack {
            ForEach(KeyboardPaintAccessibility.keys) { cap in
                Button(KeyboardPaintAccessibility.label(for: cap)) {
                    KeyboardPaintAccessibility.activate(id: cap.id, onPaint: onPaint,
                                                        onPaintEnded: onPaintEnded)
                }
                .accessibilityValue((colors[cap.id] ?? .black).accessibleLabel)
                .accessibilityHint("Paint with the current brush, or erase when Erase is enabled")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Individual keyboard keys")
    }
}

struct KeyboardFlatView: View {
    var colors: [Int: RGB8]
    var highlight: Set<Int> = []
    var onPaint: ((Int) -> Void)?
    var onPaintEnded: (() -> Void)?

    @State private var lastPainted: Int?

    private func hit(_ point: CGPoint) -> Int? {
        kKeyCaps.first {
            point.x >= $0.x && point.x <= $0.x + $0.w &&
            point.y >= $0.y && point.y <= $0.y + $0.h
        }?.id
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.01, geometry.size.width / kLayoutSize.width)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13 * max(0.6, scale))
                    .fill(
                        LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13 * max(0.6, scale))
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6 * max(0.5, scale), y: 2)
                ForEach(kKeyCaps) { key in
                    KeyCapView(cap: key,
                               color: colors[key.id] ?? .black,
                               scale: scale,
                               highlighted: highlight.contains(key.id),
                               onActivate: onPaint.map { action in
                                   { action(key.id); onPaintEnded?() }
                               })
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard let onPaint,
                          let id = hit(CGPoint(x: drag.location.x / scale,
                                               y: drag.location.y / scale)),
                          id != lastPainted else { return }
                    lastPainted = id
                    onPaint(id)
                }
                .onEnded { _ in
                    guard onPaint != nil else { return }
                    lastPainted = nil
                    onPaintEnded?()
                })
        }
        .aspectRatio(kLayoutSize.width / kLayoutSize.height, contentMode: .fit)
        .accessibilityElement(children: onPaint == nil ? .ignore : .contain)
        .accessibilityLabel(onPaint == nil ? "AULA S98 Pro lighting preview" : "Per-key lighting editor")
    }
}

// MARK: - Effect grid

/// Effects as named buttons rather than a menu.
///
/// Twenty rough translations in a pop-up menu are miserable to scan: you cannot see
/// them at once, and picking one means reading a list from the top every time. As a
/// grid the whole set is visible, the current one is obvious, and choosing is a single
/// click. The dot says whether an effect will use the colour you picked or generates
/// its own, which is also why the colour control greys out for some of them.
struct EffectGrid: View {
    @ObservedObject var model: AppModel
    var columns: Int
    /// Motion is off while the app is not frontmost. Written by `effectMotionGate`.
    @State private var animating = true
    @Environment(\.liveTint) private var live
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.snapshotMode) private var snapshotMode

    private var motion: InkMotion {
        InkMotion(reduceMotion: reduceMotion, snapshot: snapshotMode)
    }

    /// Editor only. The panel's scroller has ~360pt of viewport under 317pt of
    /// fixed chrome, and thumbnails grow the grid to ~493pt — the controls below
    /// would fall off the fold. The panel's grid is for switching; the editor's is
    /// for browsing, and the panel already animates the current effect at full
    /// width on the stage directly above it.
    private var showsThumbnails: Bool { columns >= 4 }

    /// Two lines of 11pt at 157pt per cell: "Range upon range of mountains" needs
    /// them. The full name is also in the tooltip, the accessibility label, and the
    /// "Effect: <name>" row directly above the grid.
    private var labelLines: Int { showsThumbnails ? 2 : 1 }
    private var labelHeight: CGFloat { showsThumbnails ? 27 : 14 }

    /// The panel keeps a fixed count; the editor adapts to the window.
    ///
    /// `.adaptive` and not a GeometryReader on purpose: a GeometryReader inside the
    /// editor's `.fixedSize(vertical:)` snapshot path has zero ideal height and
    /// collapses the whole render. Adaptive sizing is resolved by the grid itself,
    /// so it works identically on screen and off, and stays deterministic.
    private var gridColumns: [GridItem] {
        showsThumbnails
            ? [GridItem(.adaptive(minimum: 176, maximum: 260), spacing: 6)]
            : Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 6) {
            ForEach(kModes) { mode in
                button(for: mode)
            }
        }
        .effectMotionGate($animating)
    }

    private func button(for mode: LightMode) -> some View {
        let selected = mode.id == model.light.mode
        let name = model.modeName(mode)
        return Button {
            model.selectMode(mode.id)
        } label: {
            cellBody(for: mode, name: name, selected: selected)
            .frame(maxWidth: .infinity,
                   minHeight: Ink.rowCell,
                   alignment: showsThumbnails ? .topLeading : .leading)
            .background(
                RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                    // The FILL stays Ink.accent. It carries Ink.onAccent text at a
                    // measured 6.34:1; a live colour behind a label is exactly the
                    // failure this design forbids — black on blue is 1.6:1.
                    .fill(selected ? Ink.selection : Ink.well)
                    // Unselected cells are near the board, so they pick up 3% of it.
                    .overlay(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                        .fill(selected ? Color.clear : live.wash))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                    .strokeBorder(selected ? Ink.accent.opacity(0.45) : Ink.hairline, lineWidth: 1)
            )
            // The selection RING sits outside the fill with nothing written on it,
            // so it is free to be whatever the keyboard is showing.
            .overlay(
                RoundedRectangle(cornerRadius: Ink.rControl + 1.5, style: .continuous)
                    .strokeBorder(Ink.accent.opacity(0.3), lineWidth: 1)
                    .opacity(selected ? 1 : 0)
                    .padding(-1.5)
                    .allowsHitTesting(false)
            )
            // Bright fast, dark slow. Each cell owns its own `selected`, so the
            // arriving cell resolves to `bloom` and the leaving one to `decay` —
            // the asymmetry falls out of which cell is asked, which is the only
            // way SwiftUI expresses a per-direction curve.
            .animation(selected ? motion.bloom : motion.decay, value: selected)
            .foregroundStyle(Ink.text)
            .contentShape(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(mode.usesColor ? "\(name) — uses the colour you choose"
                             : "\(name) — generates its own colours")
        .accessibilityLabel(name)
        .accessibilityHint(mode.usesColor ? "Uses the chosen colour"
                                          : "Generates its own colours")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }


    /// Two shapes, deliberately not one parameterised shape: the panel's cell is
    /// byte-for-byte what it was before thumbnails existed, which is what lets the
    /// render gate prove the panel was untouched by them.
    @ViewBuilder
    private func cellBody(for mode: LightMode, name: String, selected: Bool) -> some View {
        if showsThumbnails {
            VStack(alignment: .leading, spacing: 5) {
                // The colour the sim tints with is the colour the user will
                // actually get: their pick, through the calibration correction,
                // exactly as the stage and the swatch already do. The three modes
                // that make their own colours ignore it — that is what the dot is for.
                EffectThumbnail(mode: mode.id,
                                base: model.displayColor(model.light.color),
                                speed: model.light.speed,
                                brightness: model.light.brightness,
                                animating: animating)
                    .clipShape(RoundedRectangle(cornerRadius: Ink.rSwatch, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Ink.rSwatch, style: .continuous)
                        .strokeBorder(selected ? Color.clear
                                               : Ink.stroke.opacity(0.7), lineWidth: 1))

                // A picture must not cost the name. Twenty unlabelled animations
                // are their own usability failure, and a tooltip is not a label.
                HStack(alignment: .top, spacing: 5) {
                    indicator(for: mode, selected: selected)
                        .padding(.top, 2)
                    Text(name)
                        .font(Ink.caption(selected ? .semibold : .regular))
                        .lineLimit(labelLines)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                // A floor, not a cap: reserved so a one-line cell keeps a two-line
                // cell's height, but larger system text grows instead of clipping.
                .frame(minHeight: labelHeight, alignment: .topLeading)
            }
            .padding(6)
        } else {
            HStack(spacing: 5) {
                indicator(for: mode, selected: selected)
                Text(name)
                    .font(Ink.caption(selected ? .semibold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func indicator(for mode: LightMode, selected: Bool) -> some View {
        let side: CGFloat = 8
        // On the selected cell the ring is onAccent, so a colour dot that happens
        // to match the accent cannot vanish on exactly the cell you are looking at.
        let ring = selected ? Ink.onAccent : Ink.stroke
        if mode.id == 0 {
            Image(systemName: "power")
                .font(.system(size: side, weight: .bold))
                .foregroundStyle(selected ? Ink.onAccent : Ink.textSecond)
                .frame(width: side, height: side)
        } else if mode.usesColor {
            Circle()
                .fill(Color(model.displayColor(model.light.color)))
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(ring, lineWidth: 1))
        } else {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center))
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(ring, lineWidth: 1))
        }
    }
}

/// Replaces `ConnectionBadge` AND `StatusFooter`'s second, contradictory icon set —
/// two vocabularies for one fact, 600pt apart. Appears exactly once per surface.
private struct ConnectionDot: View {
    @ObservedObject var device: AulaDevice
    @Environment(\.liveTint) private var live

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
        // "Connected" is written right beside the dot, so hue carries no meaning
        // on its own here and the dot is free to BE the light on the board. It
        // degrades to Ink.ok — exactly what it was before the room had a colour.
        case .ready: return live.connected
        // The two states that mean something is wrong keep their fixed semantic
        // colours. A warning that changes colour with the lighting is not a warning.
        case .failed: return Ink.warn
        default: return Ink.textDisabled
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

/// A preset described the same way on both surfaces: the panel's flat, anonymous
/// Button list gains the same calibration-corrected swatch the editor's rows show.
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
                    Button {
                        model.apply(preset)
                    } label: {
                        Label {
                            Text(preset.name)
                        } icon: {
                            Image(nsImage: PresetSwatchImage.make(
                                model.displayColor(preset.swatch)))
                        }
                    }
                }
            }
            if !model.presets.userPresets.isEmpty {
                Section("Your presets") {
                    ForEach(model.presets.userPresets) { preset in
                        Button {
                            model.apply(preset)
                        } label: {
                            Label {
                                Text(preset.name)
                            } icon: {
                                Image(nsImage: PresetSwatchImage.make(
                                    model.displayColor(preset.swatch)))
                            }
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

private struct SteppedSlider: View {
    @Environment(\.liveTint) private var live
    let label: String
    let value: Int
    let enabled: Bool
    let onChange: (Int, Bool) -> Void
    @State private var pendingValue: Int?

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Ink.body())
                .foregroundStyle(enabled ? Ink.textSecond : Ink.textDisabled)
                .frame(width: Ink.labelColumn, alignment: .leading)
            Slider(value: Binding(
                get: { Double(pendingValue ?? value) },
                set: {
                    let next = Int($0.rounded())
                    pendingValue = next
                    onChange(next, true)
                }),
                in: 0...5, step: 1,
                onEditingChanged: { editing in
                    if !editing {
                        onChange(pendingValue ?? value, false)
                        pendingValue = nil
                    }
                })
                .accessibilityLabel(label)
                .accessibilityValue("\(pendingValue ?? value) of 5")
                // A track with nothing written on it — the second place the live
                // colour is safe. The ROOT tint stays Ink.accent on purpose: it
                // reaches segmented pickers and menus, whose selected chip has a
                // label on it.
                .tint(Ink.accent)
            Text("\(pendingValue ?? value)")
                .font(Ink.mono())
                .foregroundStyle(enabled ? Ink.text : Ink.textDisabled)
                .frame(width: 20, alignment: .trailing)
        }
        // Disabled reads as a colour, never .opacity() on the whole row: an opacity
        // multiplier is what put readouts at 2.8:1 for the modes that take no colour.
        .disabled(!enabled)
    }
}

// MARK: - Menu-bar quick panel

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    private var effectName: String { model.modeName(model.currentMode) }

    var body: some View {
        VStack(spacing: 0) {

            // Identity, 50pt. No rule under it: the black runs unbroken from the
            // top of the panel down through the board, so the keyboard floats up
            // into the title instead of sitting in a compartment.
            VStack(alignment: .leading, spacing: 2) {
                Text("AULA S98 Pro").font(Ink.panelTitle).foregroundStyle(Ink.text)
                Text("Native USB control").font(Ink.caption()).foregroundStyle(Ink.textSecond)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Ink.panelGutter)
            .frame(height: 50)

            // The stage. Full bleed: no padding, no plate, no radius. Width drives
            // it and the height is a pinned constant, so a budget overrun elsewhere
            // can never squeeze the board back into a letterbox.
            InkStage(caption: effectName,
                     trailing: model.currentMode.usesColor
                        ? model.calibratedOutputColor.hex : nil) {
                KeyboardView(colors: model.effectPreview, effectName: effectName)
            }
            .frame(width: Ink.panelWidth, height: Ink.panelStageHeight)

            // The panel's one and only scroller. The inner VScroll(height: 150)
            // that used to wrap the effect grid inside this one is gone.
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
                        // already pick an animated effect and then had nowhere to
                        // set its speed or direction.
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

            // Pinned OUTSIDE the scroller: the one element that exists to be
            // noticed can no longer be the first thing pushed below the fold.
            if model.lightHasUnappliedChanges {
                InkNotice("Last change is not confirmed on the keyboard",
                          actionTitle: "Apply again", action: model.commitMode)
                    .padding(.horizontal, Ink.panelGutter)
                    .padding(.bottom, Ink.s8)
            }

            InkRule()

            // Connection state is stated ONCE per surface, and this is the place.
            VStack(spacing: Ink.s8) {
                HStack(spacing: Ink.s8) {
                    ConnectionDot(device: model.device)
                    // Only the sentence that repeats the dot is dropped. Every job
                    // result — "Clock synced · …", "Keyboard settings applied" —
                    // still shows, because for jobs that change nothing visible on
                    // the board that line is the whole confirmation.
                    if !model.device.statusRestatesTheDot {
                        Text(model.device.status)
                            .font(Ink.mono()).foregroundStyle(Ink.textSecond)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: Ink.s8)
                    if model.device.phase == .disconnected || model.device.phase == .failed {
                        InkButton("Retry") { model.device.retryConnection() }
                    }
                }
                .frame(height: 20)

                HStack(spacing: Ink.s8) {
                    // Return confirms; it never navigates. Opening the editor is
                    // Command-E, bound here and in the CommandMenu.
                    InkButton("Open editor", icon: "rectangle.inset.filled", tone: .accent) {
                        EditorWindowController.shared.show(model: model)
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    // The two ways of reaching the app live HERE as well as in
                    // Settings, and this is the copy that matters: they exist for
                    // when the menu bar is too full to reach, and Settings is
                    // behind the editor, which is the thing you were struggling to
                    // open. A setting you can only reach by doing the thing it
                    // helps you do is not reachable.
                    Menu {
                        Toggle("Show in the Dock", isOn: $model.showInDock)
                        Toggle("Open the editor at launch", isOn: $model.openEditorAtLaunch)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.textSecond)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Where Aula S98 Pro Companion appears")
                    .accessibilityLabel("Where Aula S98 Pro Companion appears")

                    Spacer()
                    InkButton("Quit") { NSApp.terminate(nil) }
                }
            }
            .padding(.horizontal, Ink.panelGutter)
            .padding(.vertical, 10)
        }
        // Offscreen the height is intrinsic. VScroll has no viewport under
        // ImageRenderer, so the scroller renders its full content; pinning 660
        // there made SwiftUI centre the overflow and clip the identity bar off the
        // top, which is exactly what the ground audit caught.
        .frame(width: Ink.panelWidth,
               height: snapshotMode ? nil : Ink.panelHeight,
               alignment: .top)
        // Matte surfaces keep the menu panel consistent with the full editor.
        .background(Ink.ground)
        .environment(\.liveTint, model.liveTint)
        .foregroundStyle(Ink.text)
        // Ink.accent ON PURPOSE. The root tint reaches segmented pickers and NSMenu,
        // whose selected chip carries a label; the live colour is applied
        // per-control, only where nothing is written on it.
        .tint(Ink.accent)
    }
}

// MARK: - Full editor

struct EditorView: View {
    @ObservedObject var model: AppModel

    init(model: AppModel, initialTab: Int? = nil) {
        self.model = model
        if let initialTab { model.selectedTab = EditorTab.clamped(initialTab).rawValue }
    }

    private var tab: EditorTab { EditorTab.clamped(model.selectedTab) }

    var body: some View {
        VStack(spacing: 0) {
            Ink.titlebar.frame(height: 34)
            InkRule()
            HStack(spacing: 0) {
                StudioNavigationRail(model: model)
                    .frame(width: Ink.sidebarWidth)
                InkRule(.vertical)
                Group {
                    switch tab {
                    case .lighting: StudioLightingView(model: model)
                    case .clock: ClockView(model: model)
                    case .presets: PresetsView(model: model)
                    case .settings: SettingsView(model: model)
                    case .apps: AppProfilesView(model: model, store: model.appProfiles)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Ink.ground)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.liveTint, model.liveTint)
        .foregroundStyle(Ink.text)
        .tint(Ink.accent)
    }
}

// MARK: Effects

private struct ClockView: View {
    @ObservedObject var model: AppModel
    @Environment(\.snapshotMode) private var snapshotMode

    /// Offscreen the clock is frozen. A live TimelineView made this the one render
    /// whose bytes changed run to run, which quietly downgraded the whole suite:
    /// the distinctness gate can only prove views differ from each other, not that
    /// a view is stable, so one ticking clock hid every other nondeterminism.
    private static let frozen = Date(timeIntervalSince1970: 1_700_000_000)

    var body: some View {
        VStack(spacing: 0) {
            InkSectionBar("Clock")
            InkRule()
            VScroll {
                InkPage {
                InkCard(title: "Keyboard clock",
                        detail: "The S98 Pro draws its own date, time, battery, and lock indicators.") {
                    VStack(alignment: .leading, spacing: 16) {
                        if snapshotMode {
                            clockFace(Self.frozen)
                        } else {
                            TimelineView(.periodic(from: Date(), by: 1)) { context in
                                clockFace(context.date)
                            }
                        }

                        Divider()
                        Toggle("Keep the keyboard clock in sync automatically",
                               isOn: Binding(get: { model.clock.enabled },
                                             set: { model.clock.enabled = $0 }))
                            .toggleStyle(.switch)
                        Text("Syncs at launch, every 30 minutes, and after wake, time-zone, or system-clock changes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)

                        HStack {
                            Button { model.clock.syncNow() } label: {
                                Label("Sync now", systemImage: "clock.arrow.circlepath")
                            }
                            Text(model.clock.lastSync)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                Label("Picture upload is intentionally unavailable because both the vendor app and direct protocol tests can hang this keyboard model.",
                      systemImage: "shield.checkered")
                    .font(Ink.caption())
                    .foregroundStyle(Ink.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: Presets

private extension ClockView {
    @ViewBuilder
    func clockFace(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted(date: .complete, time: .omitted))
                .font(.system(size: 13, weight: .medium))
            Text(date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current Mac time \(date.formatted())")
    }
}

private struct PresetsView: View {
    @ObservedObject var model: AppModel
    @State private var presetName = ""
    @State private var renameCandidate: Preset?
    @State private var renameText = ""
    @State private var deleteCandidate: Preset?
    @State private var notice = ""
    @State private var showNotice = false

    var body: some View {
        VStack(spacing: 0) {
            InkSectionBar("Presets")
            InkRule()
            VScroll {
                InkPage {
                Text("Built-ins stay correct across updates; your presets are stored separately.")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                    .fixedSize(horizontal: false, vertical: true)

                presetSection("Built-in", presets: PresetStore.builtIns)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your presets").font(.system(size: 13, weight: .semibold))
                    if model.presets.userPresets.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up.slash").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No custom presets yet").font(.system(size: 12, weight: .medium))
                                Text("Save the current effect here or a layout from Per-key.")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                    } else {
                        ForEach(model.presets.userPresets) { preset in
                            PresetRow(preset: preset,
                                      displaySwatch: model.displayColor(preset.swatch),
                                      effectName: model.labelForMode(preset.state.mode),
                                      apply: { model.apply(preset) },
                                      replace: { _ = model.replace(preset) },
                                      rename: {
                                          renameText = preset.name
                                          renameCandidate = preset
                                      },
                                      delete: { deleteCandidate = preset })
                        }
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    TextField("New effect preset", text: $presetName)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    Button("Save current effect") {
                        if model.savePreset(named: presetName, perKey: false) { presetName = "" }
                    }
                    Spacer()
                    Button("Export…", action: exportPresets)
                    Button("Import…", action: importPresets)
                }
                .controlSize(.small)

                if let error = model.presets.lastError {
                    InkNotice(error, systemImage: "exclamationmark.triangle", tint: Ink.bad)
                }
                }
            }
        }
        .sheet(item: $renameCandidate) { preset in
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename preset").font(.headline)
                TextField("Preset name", text: $renameText).frame(width: 280)
                HStack {
                    Spacer()
                    Button("Cancel") { renameCandidate = nil }
                    Button("Rename") {
                        _ = model.presets.rename(preset, to: renameText)
                        renameCandidate = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .alert("Delete preset?", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } })) {
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
                Button("Delete", role: .destructive) {
                    if let preset = deleteCandidate { _ = model.presets.delete(preset) }
                    deleteCandidate = nil
                }
            } message: {
                Text("\(deleteCandidate?.name ?? "This preset") will be removed from this Mac.")
            }
        .alert("Presets", isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice) }
    }

    @ViewBuilder
    private func presetSection(_ title: String, presets: [Preset]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            ForEach(presets) { preset in
                PresetRow(preset: preset,
                          displaySwatch: model.displayColor(preset.swatch),
                          effectName: model.labelForMode(preset.state.mode),
                          apply: { model.apply(preset) })
            }
        }
    }

    private func exportPresets() {
        guard let data = model.presets.exportJSON() else {
            notice = "Aula S98 Pro Companion could not encode your presets."; showNotice = true; return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "aula-presets.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            notice = "Exported \(model.presets.customCount) custom preset\(model.presets.customCount == 1 ? "" : "s")."
        } catch {
            notice = "Export failed: \(error.localizedDescription)"
        }
        showNotice = true
    }

    private func importPresets() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            switch model.presets.importJSON(data) {
            case .success(let count): notice = "Imported \(count) preset\(count == 1 ? "" : "s")."
            case .failure(let error): notice = error.localizedDescription
            }
        } catch {
            notice = "Import failed: \(error.localizedDescription)"
        }
        showNotice = true
    }
}

private struct PresetRow: View {
    let preset: Preset
    /// Resolved by the caller so the swatch matches the keyboard, like every other
    /// colour in the app.
    var displaySwatch: RGB8?
    /// Resolved by the caller too, so a preset reads the same name as the effect grid.
    let effectName: String
    let apply: () -> Void
    var replace: (() -> Void)?
    var rename: (() -> Void)?
    var delete: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(displaySwatch ?? preset.swatch))
                .frame(width: 34, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(preset.name).font(.system(size: 12, weight: .medium))
                    if preset.isBuiltIn {
                        Text("Built-in").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(summary).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply", action: apply).controlSize(.small)
            if replace != nil || rename != nil || delete != nil {
                Menu {
                    if let replace { Button("Replace with current", action: replace) }
                    if let rename { Button("Rename…", action: rename) }
                    if let delete { Button("Delete", role: .destructive, action: delete) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .accessibilityLabel("More actions for \(preset.name)")
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
    }

    private var summary: String {
        if preset.isPerKey {
            return "Per-key · \(preset.keys.values.filter { $0 != .black }.count) keys lit"
        }
        return effectName
    }
}

// MARK: Settings

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            InkSectionBar("Settings")
            InkRule()
            VScroll {
                InkPage {
                InkCard(title: "Keyboard behaviour",
                        detail: model.lastAppliedConfig == nil
                            ? "These values have not yet been confirmed from this Mac."
                            : "These are the last settings confirmed by this Mac.") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Sleep after").frame(width: 130, alignment: .leading)
                            Picker("Sleep after", selection: $model.config.sleepMinutes) {
                                Text("Never").tag(0); Text("1 minute").tag(1)
                                Text("5 minutes").tag(5); Text("30 minutes").tag(30)
                            }.labelsHidden().frame(width: 150)
                            Spacer()
                        }
                        HStack {
                            Text("Key response").frame(width: 130, alignment: .leading)
                            Picker("Key response", selection: $model.config.keyResponseMs) {
                                Text("Default").tag(0); Text("Level 1").tag(1)
                                Text("Level 2").tag(2); Text("Level 3").tag(3)
                            }.labelsHidden().frame(width: 150)
                            Spacer()
                        }
                        Toggle("Disable Windows / Command key", isOn: $model.config.disableWin)
                        Toggle("Disable Alt + F4", isOn: $model.config.disableAltF4)
                        Toggle("Disable Alt + Tab", isOn: $model.config.disableAltTab)

                        Divider()
                        HStack {
                            Button("Reset form to defaults", action: model.resetConfigForm)
                            Spacer()
                            if model.configHasUnappliedChanges {
                                Text("Not applied").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Button("Apply to keyboard", action: model.applyConfig)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .font(.system(size: 12))
                .toggleStyle(.checkbox)

                InkCard(title: "LED colour calibration",
                             detail: "Corrects how the app draws colour so the screen matches the keys. What is sent to the keyboard never changes.") {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Label(model.calibration == .identity
                                  ? "Standard RGB profile"
                                  : "Custom visual profile",
                                  systemImage: model.calibration == .identity
                                    ? "checkmark.circle" : "circle.lefthalf.filled")
                            Spacer()
                            if !model.calibration.samples.isEmpty {
                                Label(model.calibrationPreviewEnabled ? "Applied to the display" : "Display uncorrected",
                                      systemImage: model.calibrationPreviewEnabled
                                        ? "eye" : "eye.slash")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }

                        Text("Open any Colour or Brush control and choose Calibrate. Pick a target, show it on the keyboard, then set the second wheel to the colour you actually saw and add it as a data point.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()
                        HStack(spacing: 7) {
                            Text("Live tests").frame(width: 78, alignment: .leading)
                            Button("Red") { model.previewCalibration(RGB8(r: 255, g: 0, b: 0)) }
                            Button("Green") { model.previewCalibration(RGB8(r: 0, g: 255, b: 0)) }
                            Button("Blue") { model.previewCalibration(RGB8(r: 0, g: 0, b: 255)) }
                            Button("White") { model.previewCalibration(RGB8(r: 255, g: 255, b: 255)) }
                            Spacer()
                        }
                        .controlSize(.small)

                        HStack {
                            Button("Reset calibration", action: model.resetCalibration)
                            Spacer()
                            HStack(spacing: 6) {
                                Text("Shown on screen as")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Circle().fill(Color(model.calibratedOutputColor))
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                                Text(model.calibratedOutputColor.hex)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Button("Reapply current effect", action: model.commitMode)
                        }

                        if !model.modeLabels.isEmpty {
                            InkRule().padding(.vertical, Ink.s4)
                            InkRow("Effect names") {
                                Text("\(model.modeLabels.count) custom effect name"
                                     + (model.modeLabels.count == 1 ? "" : "s") + " recorded")
                                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                                Spacer(minLength: Ink.s8)
                                InkButton("Use the manual's names") {
                                    for mode in model.modeLabels.keys {
                                        model.clearModeLabel(for: mode)
                                    }
                                }
                                .help("Discard your recorded names and fall back to the "
                                      + "keyboard manual's twenty effect names")
                            }
                        }

                        Text("Data points correct how this app draws colour so the screen matches the keys; nothing sent to the keyboard changes. Firmware-generated rainbow modes cannot be corrected.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 12))

                InkCard(title: "Application") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Start Aula S98 Pro Companion at login", isOn: Binding(
                            get: { startsAtLogin }, set: updateLoginItem))
                        if !loginMessage.isEmpty {
                            InkNotice(loginMessage, systemImage: "exclamationmark.triangle")
                        }

                        InkRule().padding(.vertical, Ink.s4)

                        // Reaching a menu-bar-only app means reaching the menu bar.
                        // On a small screen with a lot already up there, these are
                        // the two ways in that do not depend on it.
                        Toggle("Show Aula S98 Pro Companion in the Dock", isOn: $model.showInDock)
                        Text("Adds a Dock icon and an entry in the app switcher. "
                             + "The menu-bar item stays either way.")
                            .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle("Open the editor at launch", isOn: $model.openEditorAtLaunch)
                        Text("Opens this window on every launch. Clicking Aula S98 Pro Companion in "
                             + "Finder, Spotlight or the Dock opens it too, whether or "
                             + "not this is on.")
                            .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                            .fixedSize(horizontal: false, vertical: true)

                        InkRule().padding(.vertical, Ink.s4)
                        HStack {
                            Button("Reveal log in Finder", action: revealLog)
                            Spacer()
                            Text("Aula S98 Pro Companion \(appVersion)")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }

                InkCard(title: "About") {
                    Text("Aula S98 Pro Companion is an unofficial open-source app, not affiliated with or endorsed by AULA. It talks directly to the keyboard's vendor HID interface over USB. It uses no virtual machine, vendor suite, account, telemetry, or runtime dependency. Wireless modes expose a different device and cannot be configured by this protocol.")
                        .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }
                }
            }
        }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            // Report what the system decided, not what was asked. Registration can
            // succeed into "requires approval", where the app will NOT start at login
            // until the user approves it in System Settings.
            let status = SMAppService.mainApp.status
            startsAtLogin = status == .enabled
            loginMessage = status == .requiresApproval
                ? "Approve Aula S98 Pro Companion in System Settings › General › Login Items."
                : ""
        } catch {
            startsAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = error.localizedDescription
        }
    }

    private func revealLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Aula S98 Pro Companion.log")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}
