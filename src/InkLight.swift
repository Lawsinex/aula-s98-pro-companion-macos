// The room's light.
//
// The app is a darkroom and the keyboard is the only light source in it. This file
// is the only place that turns "what is on the board" into something the chrome can
// wear, and it is one file because three rules govern all of it — each learned by
// breaking it:
//
//  1. A LIVE COLOUR IS NEVER A FILL BEHIND TEXT. `LiveTint` deliberately exposes no
//     `fill` member. Anything with a label on it keeps `Ink.accent`, whose label
//     contrast (6.34:1) is a measured constant rather than a per-frame gamble.
//     Black-on-blue measures 1.6:1, and no amount of clamping in HSV prevents it.
//
//  2. A LUMINANCE FLOOR IS NOT A VALUE FLOOR. Pure blue is already at HSV value 1
//     and still only 0.0722 relative luminance — 2.44:1 on #000000. Clamping `v`
//     does nothing for it. The floor below is applied to relative luminance, which
//     is the quantity contrast is actually defined on, and the lever that moves it
//     is desaturation toward white.
//
//  3. NOTHING HERE MAY LIFT A WINDOW CORNER ABOVE 6/255. scripts/groundaudit.py
//     fails any render whose corner pixels exceed CORNER_TOLERANCE = 6. The ambient
//     gradient's first and last stops are literally `Ink.ground`, so the top and
//     bottom rows are untouched at any amplitude; the grain is the only layer that
//     can reach a corner, and it is bounded to 4/255 by construction.
//
// Everything here is DETERMINISTIC. No Double.random, no arc4random, no Dictionary
// iteration, no clock. The snapshot renders must hash identically run to run.

import SwiftUI
import CoreGraphics

// MARK: - The live colour

/// One colour derived from the frame currently on the keyboard.
///
/// There is no `fill`. That absence is the design: rings, dots, hairlines and glow
/// are the only things allowed to be live, because none of them has writing on it.
struct LiveTint: Equatable {

    /// The board's hue raised to a safe luminance. `nil` when the board lends no
    /// usable hue — off, near-black, or many hues at once — in which case every
    /// consumer degrades to `Ink.accent`, which is exactly the app's behaviour
    /// before the room had a colour. It degrades to SAFE, never to invisible.
    private let ring: RGB8?

    /// The unraised colour, used only for glow. A bloom is light, not a boundary,
    /// so it is not held to the contrast floor — raising it would wash it out.
    private let glow: RGB8?

    /// 0…1 from the keyboard's own brightness step. The ambient scales by it, so
    /// turning the board down turns the room down.
    let lift: Double

    /// The board is dark, or has nothing to lend. Rings fall back to `Ink.accent`,
    /// the bloom goes to nothing at all, and the room is genuinely dark.
    static let dormant = LiveTint(ring: nil, glow: nil, lift: 0)

    /// 3:1 — the floor a non-text UI boundary needs — is L ≥ 0.10 on #000000,
    /// since contrast there is (L + 0.05) / 0.05. 0.13 is 3.6:1, and the margin
    /// buys back what a 1.5pt ring loses against the thicker strokes the 3:1 rule
    /// was measured on.
    static let luminanceFloor = 0.13
    /// Below this HSV saturation there is no hue to wear, only a grey.
    static let chromaFloor = 0.20
    /// Below this HSV value the colour is near-black; deriving a hue from it is
    /// inventing one.
    static let valueFloor = 0.10
    /// Circular resultant length of the frame's hues. Below it the frame is many
    /// hues at once (the firmware rainbows), and their circular mean is a colour
    /// that is nowhere on the keyboard.
    static let concentrationFloor = 0.35

    private init(ring: RGB8?, glow: RGB8?, lift: Double) {
        self.ring = ring
        self.glow = glow
        self.lift = lift
    }

    // MARK: What the UI may use it for

    /// Selection rings, focus rings, live control tracks. Never a fill behind a
    /// label — there is deliberately no `fill` member on this type.
    var stroke: Color { ring.map { Color($0) } ?? Ink.accent }

    /// The connection dot when the keyboard is ready. Degrades to `Ink.ok`, which
    /// is what the dot was before. "Connected" is stated by the label beside it,
    /// so no meaning is carried by hue alone.
    var connected: Color { ring.map { Color($0) } ?? Ink.ok }

    /// 3% of the live colour, for the surfaces nearest the board. Over `Ink.surface`
    /// this moves #121216 by about 7/255: the card does not become a fill step, its
    /// edge picks up the room.
    var wash: Color { (ring.map { Color($0) } ?? .clear).opacity(0.03 * lift) }

    /// The spill. `.clear` when dormant, so an unlit board throws nothing.
    var bloom: Color { glow.map { Color($0) } ?? .clear }

    /// True when the board is lending a hue rather than falling back to the accent.
    var isLit: Bool { ring != nil }

    // MARK: Derivation

    /// 0.35 at brightness 0, 1.0 at brightness 5. Never 0 while the board is lit:
    /// the room keeps a floor so structure does not vanish when you dim the keys.
    static func lift(for brightness: Int) -> Double {
        0.35 + 0.13 * Double(max(0, min(5, brightness)))
    }

    /// The whole board is one colour — every mode that uses the colour you picked.
    init(single colour: RGB8, brightness: Int) {
        self.init(hue: colour, brightness: brightness)
    }

    /// Many hues at once. There is no dominant hue to wear, so boundaries stay
    /// `Ink.accent` and only the glow goes — correctly — warm white.
    static func polychrome(brightness: Int) -> LiveTint {
        LiveTint(ring: nil,
                 glow: RGB8(r: 255, g: 244, b: 232),
                 lift: lift(for: brightness))
    }

    /// A per-key frame reduced to its dominant hue.
    ///
    /// Weighted circular mean, then a CONCENTRATION test. Averaging a rainbow's
    /// hues on the circle produces a near-zero resultant pointing at an arbitrary
    /// angle, so the resultant's LENGTH is checked before its direction is used.
    init(frame: [Int: RGB8], brightness: Int) {
        var x = 0.0, y = 0.0, saturation = 0.0, weight = 0.0
        // kLedIndices, not frame.keys. Swift seeds Dictionary iteration order per
        // process, and a sum of Doubles is order-dependent — iterating the
        // dictionary would give the same build a different tint, and therefore a
        // different snapshot hash, on every launch.
        for id in kLedIndices {
            guard let colour = frame[id], colour != .black else { continue }
            let hsv = HSVColorMath.hsv(colour)
            // Grey and dim keys do not get a vote on what colour the room is.
            let w = hsv.s * hsv.v
            guard w > 0.02 else { continue }
            let angle = hsv.h * 2 * .pi
            x += cos(angle) * w
            y += sin(angle) * w
            saturation += hsv.s * w
            weight += w
        }
        guard weight > 0 else { self = .dormant; return }
        let concentration = (x * x + y * y).squareRoot() / weight
        guard concentration >= LiveTint.concentrationFloor else {
            self = .polychrome(brightness: brightness)
            return
        }
        var hue = atan2(y, x) / (2 * .pi)
        hue -= hue.rounded(.down)
        let mean = min(0.95, max(0.55, saturation / weight))
        self.init(hue: HSVColorMath.rgb(h: hue, s: mean, v: 1), brightness: brightness)
    }

    private init(hue colour: RGB8, brightness: Int) {
        let hsv = HSVColorMath.hsv(colour)
        // Off, or so nearly black that any hue read off it was invented rather
        // than observed. Degrade, do not guess.
        guard hsv.v >= LiveTint.valueFloor, hsv.s >= LiveTint.chromaFloor else {
            self = .dormant
            return
        }
        // Never a washed-out pastel, never a full-gamut neon: the ring should read
        // as the board's colour, not as a highlighter.
        let full = HSVColorMath.rgb(h: hsv.h, s: min(0.95, max(0.55, hsv.s)), v: 1)
        self.init(ring: LiveTint.raised(full, to: LiveTint.luminanceFloor),
                  glow: colour,
                  lift: LiveTint.lift(for: brightness))
    }

    /// The luminance floor.
    ///
    /// Raising HSV `value` cannot rescue pure blue — it is already at v = 1 and
    /// still only 0.0722. The only lever that moves relative luminance for a
    /// saturated hue is a blend toward white, and the quantity to bisect on is the
    /// luminance itself. #0000FF lands at roughly #4545FF: unmistakably blue, and
    /// 3.6:1 on black instead of 2.44:1.
    static func raised(_ colour: RGB8, to floor: Double) -> RGB8 {
        guard colour.relativeLuminance < floor else { return colour }
        var low = 0.0, high = 1.0
        // A FIXED iteration count, not a tolerance loop: the result has to be
        // bit-identical on every run or the snapshot hashes drift.
        for _ in 0..<14 {
            let mid = (low + high) / 2
            if mixedWithWhite(colour, mid).relativeLuminance < floor { low = mid }
            else { high = mid }
        }
        return mixedWithWhite(colour, high)
    }

    private static func mixedWithWhite(_ colour: RGB8, _ t: Double) -> RGB8 {
        func channel(_ value: UInt8) -> UInt8 {
            let raw = Double(value) + (255 - Double(value)) * t
            return UInt8(max(0, min(255, raw.rounded())))
        }
        return RGB8(r: channel(colour.r), g: channel(colour.g), b: channel(colour.b))
    }
}

// MARK: - Carried by the environment

private struct LiveTintKey: EnvironmentKey {
    static let defaultValue = LiveTint.dormant
}

extension EnvironmentValues {
    /// Injected once at each surface's root. Defaulting to `.dormant` means every
    /// component that has not opted in keeps its `Ink.accent` behaviour exactly,
    /// so this can be adopted one control at a time.
    var liveTint: LiveTint {
        get { self[LiveTintKey.self] }
        set { self[LiveTintKey.self] = newValue }
    }
}

extension AppModel {
    /// What is on the board right now, as one colour the app can wear.
    ///
    /// Deliberately NOT `LiveTint(frame: effectPreview)` for the effect source:
    /// `effectPreview` builds a 96-entry dictionary on every access, and for a
    /// single-colour mode the answer is one colour that is already to hand. The
    /// frame reduction runs only where there really is a frame.
    var liveTint: LiveTint {
        if lightingSource == .perKey {
            return LiveTint(frame: displayColors(keys), brightness: light.brightness)
        }
        if light.mode == 0 { return .dormant }
        guard currentMode.usesColor else {
            return .polychrome(brightness: light.brightness)
        }
        return LiveTint(single: displayColor(light.color), brightness: light.brightness)
    }
}

// MARK: - Motion

/// Light ramps ASYMMETRICALLY: bright fast, dark slow. That asymmetry is the whole
/// grammar, and these five durations are all of it — nothing else in the app
/// animates.
struct InkMotion {
    let enabled: Bool

    /// Off for reduce-motion, and off offscreen so `ImageRenderer` captures the
    /// settled state and the snapshot hashes stay identical run to run.
    init(reduceMotion: Bool, snapshot: Bool) {
        enabled = !reduceMotion && !snapshot
    }

    /// Something becomes lit.
    var bloom: Animation? { enabled ? .easeOut(duration: 0.18) : nil }
    /// Something stops being lit. Longer, because that is what light does.
    var decay: Animation? { enabled ? .easeIn(duration: 0.32) : nil }
    /// The room's level following the keyboard's brightness step.
    var lift: Animation? { enabled ? .easeOut(duration: 0.24) : nil }
    /// The confirmation flash, and its long fall.
    var pulseUp: Animation { .easeOut(duration: 0.14) }
    var pulseDown: Animation { .easeIn(duration: 0.42) }
}

// MARK: - The ambient

/// The room, lit from the board's direction: one soft vertical gradient plus one
/// bloom of the board's own colour. Painted ONCE per surface, as a BACKGROUND —
/// never an overlay — so no glow can ever land on top of a label.
///
/// `Ink.surface` at #121216 on #000000 is 1.12:1 and imperceptible, and lightening
/// it would fight the photograph. This gives the depth instead, without touching a
/// single token.
///
/// CORNERS: the first and last stops are literally `Ink.ground`, so row 0 and row
/// h-1 of the render are exactly #000000 whatever the amplitude in between — which
/// is every pixel groundaudit.py samples. The bloom's last stop is fully
/// transparent and its end radius stops well inside the frame, so it contributes
/// nothing at a corner either.
struct InkAmbient: View {
    var tint: LiveTint
    /// Where the light comes from, in POINTS from the top: the bottom edge of the
    /// keyboard stage. Points rather than a fraction because the snapshot renders
    /// the panel at its intrinsic height, not at 660.
    var source: CGFloat
    /// Points of chrome to the left that the light does not reach — the editor's
    /// sidebar. Keeps the bloom centred on the board, not on the window.
    var leading: CGFloat = 0
    /// 0…1, driven by the confirmation pulse.
    var pulse: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)
            let width = max(1, geometry.size.width)
            let at = min(0.90, max(0.06, source / height))
            let centre = min(0.95, max(0.05, (leading + (width - leading) / 2) / width))
            let flash = 1 + 0.55 * pulse
            ZStack {
                Ink.ground
                // Structure, and deliberately NEUTRAL: it must not disappear when
                // the board is off, or the window loses its depth exactly when it
                // has least else to read.
                LinearGradient(stops: [
                    .init(color: Ink.ground, location: 0),
                    .init(color: Color.white.opacity(0.028), location: at),
                    .init(color: Color.white.opacity(0.012), location: min(0.98, at + 0.31)),
                    .init(color: Ink.ground, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                // The flourish: the board's glow spilling into the window. Its
                // centre sits at the stage's bottom edge, so the half above is
                // occluded by the stage's own black — you see the spill AROUND and
                // BELOW the board, which is what a light source under glass does.
                EllipticalGradient(
                    stops: [
                        .init(color: tint.bloom.opacity(0.20 * tint.lift * flash), location: 0),
                        .init(color: tint.bloom.opacity(0.07 * tint.lift * flash), location: 0.42),
                        .init(color: tint.bloom.opacity(0), location: 1),
                    ],
                    center: UnitPoint(x: centre, y: at),
                    startRadiusFraction: 0,
                    // NOT a constant. EllipticalGradient scales its unit radius
                    // anisotropically to the rect, so a fixed reach lands on
                    // corners that sit at ~0.50–0.56 unit distance — and how far it
                    // travels changes with content height, which the effect
                    // thumbnails just changed. Terminating on the nearest corner
                    // puts the fully transparent stop exactly there, so every
                    // corner falls outside the gradient at any page height.
                    endRadiusFraction: min(
                        min(hypot(centre, at), hypot(1 - centre, at)),
                        min(hypot(centre, 1 - at), hypot(1 - centre, 1 - at))))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Grain

/// The difference between "black" and "a dark room", and the dither that keeps the
/// bloom above from banding on an 8-bit display.
enum InkGrain {
    /// BOUNDED, not tuned. groundaudit.py fails a render whose corner pixels exceed
    /// 6/255, and the grain is the only layer that can reach a corner. 4 leaves
    /// 2/255 of headroom and is 1.6% of full scale — inside the 1–2% the look asks
    /// for. AulaLogicTests asserts this against the audit's tolerance so the two
    /// numbers cannot drift apart silently.
    static let maxByte: UInt8 = 4
    static let side = 64

    /// One 64×64 tile from a fixed-seed integer LCG. No Double.random, no
    /// arc4random: the bytes are identical on every launch, which is what keeps the
    /// snapshot hashes identical. 16 KB, built once, tiled by the GPU.
    static let tile: CGImage? = {
        let count = side * side
        var bytes = [UInt8](repeating: 0, count: count * 4)
        var seed: UInt32 = 0x5A1F_0B0D          // #FF5A1F, the ember, as a seed
        for i in 0..<count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let v = UInt8((seed >> 24) % (UInt32(maxByte) + 1))
            // Premultiplied white: RGB == A, so the unpremultiplied colour is pure
            // white at alpha v/255. Composited over #000000 the result is exactly
            // v; over a lit pixel it adds at most v. Plain source-over, no blend
            // mode, so there is no compositing-group subtlety to get wrong.
            bytes[i * 4 + 0] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
            bytes[i * 4 + 3] = v
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: side, height: side,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(
                        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }()
}

/// 1.6% monochrome noise over the whole ground, including the photograph — the
/// board is in the room, not behind a window into another one.
struct InkGrainOverlay: View {
    var body: some View {
        if let tile = InkGrain.tile {
            Image(decorative: tile, scale: 1)
                .resizable(resizingMode: .tile)
                // Crisp 2×2 blocks at renderer.scale = 2 rather than a resampled
                // smear: sharper on Retina, and it removes a resampling step from
                // the hash.
                .interpolation(.none)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Typography, role 3

/// The third and last type role: a micro label on a WORKING surface — the things
/// you operate. Never prose, never a heading.
///
/// Uppercased here rather than in the string so VoiceOver still reads the words
/// instead of spelling out capitals. Still 11pt: the floor holds.
struct InkMicro: View {
    let text: String
    var tint: Color

    init(_ text: String, tint: Color = Ink.textSecond) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Ink.micro)
            .tracking(Ink.microTracking)
            .foregroundStyle(tint)
            .accessibilityLabel(text)
    }
}
