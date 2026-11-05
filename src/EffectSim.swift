// Living effect thumbnails: what each of the twenty effects actually DOES.
//
// The names are AULA's own rough translations — "Kill two birds with one stone",
// "Range upon range of mountains" — and they predict nothing. A moving picture does.
//
// These are the simulations the old WebGL light table ran, recovered from
// 75e1e3e^:viewer/keyboard3d.src.html and ported case-for-case. The switch index is
// LightMode.id, so nothing has to be mapped. They are INTERPRETATIONS of the
// manual's names, not captures of the firmware: the board renders these itself and
// this protocol has no command that would tell us what it is drawing.
//
// Native Canvas, not a second web view, for three reasons that are not aesthetic:
// viewer/app3d.html is already 2.5MB of base64 textures and a second page would
// roughly double the bundle; `ImageRenderer` cannot rasterise a WKWebView, so a web
// thumbnail would be invisible to all nine render gates and could rot unnoticed;
// and at ~110x33pt none of the photograph's detail survives anyway — a legible
// abstraction of 96 key rects beats an unreadable photo.

import SwiftUI
import AppKit

// MARK: - Working colour

/// The simulations' colour type. Doubles the whole way through: the JS these are
/// ported from works in 0...1, and quantising to bytes per key per frame would band
/// the very gradients these effects are made of.
struct FXColor {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init(_ color: RGB8) {
        self.init(Double(color.r) / 255, Double(color.g) / 255, Double(color.b) / 255)
    }

    static let black = FXColor(0, 0, 0)

    /// Below this a key is drawn as an unlit cap rather than as a colour, so an
    /// effect that lights three keys still shows the shape of the keyboard — and so
    /// "Off" reads as a dark keyboard instead of as a view that failed to render.
    var isDark: Bool { r + g + b < 0.06 }
}

// MARK: - The simulations

enum EffectSim {

    // MARK: Geometry

    /// One key, pre-resolved. Everything the simulations ask for is computed once at
    /// first use: 96 keys x 20 cells x 20fps would otherwise re-derive the same
    /// divisions 38,400 times a second.
    struct Key {
        /// Centre of the key, 0...1 across the board. The simulations' `k.nx`/`k.ny`.
        let nx: Double, ny: Double
        /// Stable per-key randomness. The JS used `Math.random()`, which would give
        /// every snapshot render a different image and make the byte-identical gate
        /// pass vacuously; this is a hash of the LED id, so it is fixed forever.
        let seed: Double
        /// The keycap in unit space, scaled by the canvas at draw time.
        let unit: CGRect
    }

    static let aspect: Double = Double(kLayoutSize.width) / Double(kLayoutSize.height)

    static let keys: [Key] = {
        let w = Double(kLayoutSize.width), h = Double(kLayoutSize.height)
        return kKeyCaps.map { cap in
            Key(nx: (cap.x + cap.w / 2) / w,
                ny: (cap.y + cap.h / 2) / h,
                seed: seed(for: cap.id),
                unit: CGRect(x: cap.x / w, y: cap.y / h, width: cap.w / w, height: cap.h / h))
        }
    }()

    /// SplitMix64 over the LED id. Deterministic, well spread, and — unlike
    /// `Double(id) / 123` — not correlated with the key's position, so Starlight
    /// twinkles instead of sweeping.
    private static func seed(for id: Int) -> Double {
        var x = UInt64(bitPattern: Int64(id)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 53 bits, [0, 1)
    }

    // MARK: Clock

    /// 20fps. A 33pt-tall thumbnail carries no information a 60fps sample would add,
    /// and this is the single knob that scales the whole grid's cost: 20 cells x 96
    /// keys x 20fps = 38,400 fills/second instead of 115,200.
    static let frameInterval: Double = 1.0 / 20.0

    /// The frozen frame, per effect. Snapshot renders and Reduce Motion both use it,
    /// so the gate hashes are byte-identical run to run.
    ///
    /// Per effect, not one shared instant: the two-spot and shuttle effects put their
    /// spots wherever they happen to be at a common t, and at 1.85s several of them
    /// were parked against an edge — twenty stills of which four were nearly blank.
    /// The offset is arbitrary but fixed, and each value was checked by eye against
    /// the render it produces.
    static func stillTime(for mode: Int) -> Double {
        1.85 + Double(mode) * 0.61
    }

    /// Process-relative and quantised. Relative because `sin()` of 7.8e8 has lost
    /// most of its mantissa; quantised so all twenty cells sample the SAME t even
    /// though their timelines fire microseconds apart — otherwise adjacent cells of
    /// the same effect visibly disagree.
    private static let epoch = Date.timeIntervalSinceReferenceDate

    static func clock(_ date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate - epoch
        return (elapsed / frameInterval).rounded(.down) * frameInterval
    }

    // MARK: Inputs

    /// `speed / 3` in the original, where 3 is the keyboard's middle speed. Floored at
    /// 1: at speed 0 every animated thumbnail would freeze into a still, and twenty
    /// stills are the exact failure this feature exists to fix.
    static func speedFactor(_ speed: Int) -> Double {
        Double(max(1, min(5, speed))) / 3
    }

    /// Brightness is felt but not obeyed. The original's `0.18 + (b/5)*0.82` bottoms
    /// out at 18%, which at thumbnail size is indistinguishable from black for all
    /// twenty cells at once; this keeps the response and floors it at legible.
    static func gain(_ brightness: Int) -> Double {
        0.55 + 0.45 * Double(max(0, min(5, brightness))) / 5
    }

    // MARK: Helpers (ported verbatim)

    @inline(__always)
    static func pulse(_ x: Double) -> Double { 0.5 + 0.5 * sin(x) }

    @inline(__always)
    static func scale(_ c: FXColor, _ k: Double) -> FXColor { FXColor(c.r * k, c.g * k, c.b * k) }

    static func hsv(_ hue: Double, _ s: Double, _ v: Double) -> FXColor {
        var h = hue.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let x = h * 6
        let i = Int(x.rounded(.down))
        let f = x - Double(i)
        let p = v * (1 - s), q = v * (1 - f * s), w = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0:  return FXColor(v, w, p)
        case 1:  return FXColor(q, v, p)
        case 2:  return FXColor(p, v, w)
        case 3:  return FXColor(p, q, v)
        case 4:  return FXColor(w, p, v)
        default: return FXColor(v, p, q)
        }
    }

    // MARK: The twenty

    /// `mode` is `LightMode.id`; `s` is `speedFactor(_:)`.
    static func colour(mode: Int, key k: Key, t: Double, base: FXColor, s: Double) -> FXColor {
        switch mode {
        case 0:  return .black                                                  // Off
        case 1:  return base                                                    // Static On
        case 2:  return scale(base, pulse(t * 2 * s - k.nx * 7) > 0.72 ? 1 : 0.06)   // Single light up
        case 3:  return scale(base, pulse(t * 2 * s - k.nx * 7) > 0.72 ? 0.06 : 1)   // Single extinction
        case 4:  return scale(base, pow(pulse(t * 2.6 * s + k.seed * 44), 7))        // Starlight
        case 5:  return scale(base, 0.25 + 0.75 * pow(pulse(t * 5 * s + k.seed * 30), 3))  // Fluttering
        case 6:                                                                 // Flowers are blooming
            let front = (t * 0.32 * s + k.seed * 0.5).truncatingRemainder(dividingBy: 1)
            return scale(base, max(0, 1 - abs(front - k.ny) * 4))
        case 7:  return scale(base, 0.08 + 0.92 * pulse(t * 1.5 * s))           // Dynamic Breathing
        // Spectral cycle. kModes (AulaDevice.swift:308) declares id 8 usesColor,
        // so the cell shows a coloured dot, the tooltip promises "uses the colour
        // you choose", and the stage directly above previews it in that colour —
        // the light table drew a rainbow here and nothing ever cross-checked it.
        // Vertical, to stay distinct from 7 (uniform breathe) and 11/17 (horizontal).
        case 8:  return scale(base, 0.12 + 0.88 * pow(pulse(t * 1.8 * s - k.ny * 3), 2))
        case 9:  return hsv(k.ny * 0.5 - t * 0.5 * s, 0.9, max(0.15, 1 - k.ny)) // Colorful Fountain
        case 10: return hsv(k.nx * 0.85 - t * 0.28 * s, 0.92, 1)                // Rainbow Wave
        case 11: return scale(base, 0.2 + 0.8 * pulse((k.nx * 5) - t * 3 * s))  // Following Currents
        case 12:                                                                // Peak Revolving
            let angle = atan2(k.ny - 0.5, k.nx - 0.5)
            return scale(base, 0.15 + 0.85 * pulse(angle * 2 - t * 2.4 * s))
        case 13: return scale(base, pulse(t * 3.2 * s + k.seed * 20) > 0.55 ? 1 : 0.10)  // Be touch-and-go
        case 14:                                                                // Kill two birds
            let a = (t * 0.30 * s).truncatingRemainder(dividingBy: 1)
            let b = (t * 0.30 * s + 0.5).truncatingRemainder(dividingBy: 1)
            let d = min(abs(k.nx - a), abs(k.nx - b))
            return scale(base, max(0.06, 1 - d * 9))
        case 15:                                                                // Ripple diffusion
            let dx = k.nx - 0.5, dy = k.ny - 0.5
            let r = (dx * dx + dy * dy).squareRoot()
            return scale(base, 0.12 + 0.88 * pow(pulse(r * 22 - t * 3.4 * s), 3))
        case 16: return scale(base, 0.2 + 0.8 * pulse(k.nx * 4 + k.ny * 2 - t * 2.2 * s))       // A continuous flow
        case 17: return scale(base, 0.12 + 0.88 * pow(pulse(k.nx * 9 - t * 1.6 * s), 2))        // Range upon range
        case 18:                                                                // Light wind, drizzle
            let fall = (t * 0.5 * s + k.seed).truncatingRemainder(dividingBy: 1.3)
            return scale(base, max(0.05, 1 - abs(fall - k.ny) * 5))
        case 19:                                                                // Shuttle back and forth
            let p = abs((t * 0.42 * s).truncatingRemainder(dividingBy: 2) - 1)
            return scale(base, max(0.06, 1 - abs(k.nx - p) * 7))
        default: return base
        }
    }
}

// MARK: - The thumbnail

/// One effect, drawn small and moving.
///
/// Fidelity is deliberately low: flat rectangles, no corner radius, no legend, no
/// per-key glow, one fill per lit key and ONE fill for every unlit key together. At
/// 110pt wide a keycap is 4pt across and 1.3pt from its neighbour — the gaps in the
/// layout do all the work that KeyCapView's gradients, strokes and two shadows do at
/// full size, at a twentieth of the cost.
struct EffectThumbnail: View {
    /// Freezing rules. `snapshotMode` is the hard one: nine render hashes have to be
    /// identical run to run or the distinctness gate passes without testing anything.
    @Environment(\.snapshotMode) private var snapshotMode
    /// Twenty simultaneous animations is precisely what Reduce Motion is for. The
    /// frozen frame is still informative, which is why it was chosen carefully.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let mode: Int
    let base: RGB8
    let speed: Int
    let brightness: Int
    /// False while the app is not frontmost. See `effectMotionGate(_:)`.
    var animating: Bool = true

    private var frozen: Bool { snapshotMode || reduceMotion || !animating }

    var body: some View {
        Group {
            if frozen {
                EffectThumbnailCanvas(mode: mode, base: base, speed: speed,
                                      brightness: brightness,
                                      t: EffectSim.stillTime(for: mode))
            } else {
                TimelineView(.animation(minimumInterval: EffectSim.frameInterval)) { context in
                    EffectThumbnailCanvas(mode: mode, base: base, speed: speed,
                                          brightness: brightness,
                                          t: EffectSim.clock(context.date))
                }
            }
        }
        .aspectRatio(EffectSim.aspect, contentMode: .fit)
        // The name is on the cell as text and on the button as its label; the picture
        // adds nothing a screen reader can use and would only lengthen the sweep.
        .accessibilityHidden(true)
    }
}

private struct EffectThumbnailCanvas: View {
    let mode: Int
    let base: RGB8
    let speed: Int
    let brightness: Int
    let t: Double

    /// Matches KeyCapView's unlit cap (white at 0.10 → 0.045) collapsed to one step.
    private static let unlitCap = Color.white.opacity(0.06)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.ground))

            let tint = FXColor(base)
            let s = EffectSim.speedFactor(speed)
            let gain = EffectSim.gain(brightness)

            // Unlit keys are accumulated into one path and filled once. Half the
            // effects light a handful of keys at a time, and "Off" lights none —
            // for those this is 1 fill instead of 96.
            var unlit = Path()
            for key in EffectSim.keys {
                let rect = CGRect(x: key.unit.minX * size.width,
                                  y: key.unit.minY * size.height,
                                  width: key.unit.width * size.width,
                                  height: key.unit.height * size.height)
                let c = EffectSim.colour(mode: mode, key: key, t: t, base: tint, s: s)
                if c.isDark {
                    unlit.addRect(rect)
                } else {
                    context.fill(Path(rect), with: .color(.sRGB,
                                                          red: min(1, c.r * gain),
                                                          green: min(1, c.g * gain),
                                                          blue: min(1, c.b * gain),
                                                          opacity: 1))
                }
            }
            if !unlit.isEmpty { context.fill(unlit, with: .color(Self.unlitCap)) }
        }
    }
}

// MARK: - Pausing

/// Stops every thumbnail while the app is not frontmost.
///
/// This is the cheap 90%: the menu panel's views are torn down when the panel
/// closes, so "both surfaces animating at once" only happens while both are on
/// screen AND the app is in front. Per-cell visibility pausing was considered and
/// rejected — it needs twenty GeometryReaders reporting into a shared coordinate
/// space on every scroll, which costs more than the four rows it would save.
private struct EffectMotionGate: ViewModifier {
    @Binding var animating: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)) { _ in animating = true }
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.didResignActiveNotification)) { _ in animating = false }
    }
}

extension View {
    func effectMotionGate(_ animating: Binding<Bool>) -> some View {
        modifier(EffectMotionGate(animating: animating))
    }
}
