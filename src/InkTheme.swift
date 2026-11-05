// The app's whole visual vocabulary: palette, spacing rhythm, type scale, geometry.
//
// Dark-only on purpose. `NSApplication.shared.appearance` is pinned to `.darkAqua`
// at launch, so every AppKit-drawn control, popover, sheet, alert, menu and titlebar
// comes with us; nothing here has a light mirror to keep in sync, and nothing
// derives from `Color.primary`, `.secondary` or `.accentColor`.
//
// The ground is literally #000000 because the keyboard preview is a photograph on a
// transparent page: give it any other ground and the matte and its desk reflection
// terminate on a visible edge instead of dissolving into the app.
//
// Structure is carried by BORDERS, not by fill steps. Against #000000 no fill can
// reach the 3:1 a boundary needs without going grey enough to fight the photograph —
// so `surface` and `well` are quiet planes, and borders identify working controls.

import SwiftUI

extension Color {
    /// 0xRRGGBB, so the token table reads as the numbers it was designed as.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Ink {

    // MARK: Surfaces

    static let ground = Color(hex: 0x000000)    // window, panel, and the stage
    static let surface = Color(hex: 0x141414)
    static let well = Color(hex: 0x1C1C1C)
    static let hairline = Color(hex: 0x292929)
    static let stroke = Color(hex: 0x484848)
    static let selection = Color(hex: 0x302820)
    static let titlebar = Color(hex: 0x151515)

    /// System Settings › Accessibility › Display › Increase contrast promotes both.
    static let hairlineHi = Color(hex: 0x616169)
    static let strokeHi = Color(hex: 0x8A8A94)

    // MARK: Ink
    //
    // Exactly two text colours plus a disabled step. There is no "tertiary": every
    // draft that defined one immediately spent it on load-bearing text at 3.3:1.

    static let text = Color(hex: 0xF2F3F5)          // 18.91:1 on ground
    static let textSecond = Color(hex: 0xA8A8A8)
    static let textDisabled = Color(hex: 0x858585)

    // MARK: Accent
    //
    // Warm peach from the selected Library Rail reference, independent of the
    // keyboard colour and of the user's system accent.

    static let accent = Color(hex: 0xFFC799)
    static let onAccent = Color(hex: 0x0A0A0C)

    // MARK: Signals

    static let ok = Color(hex: 0x30D158)    // 10.39:1
    static let warn = Color(hex: 0xFFB020)  // 11.48:1
    static let bad = Color(hex: 0xFF453A)   //  6.16:1

    // MARK: Spacing — 4 / 8 / 12 / 16 / 20 / 28, nothing else.

    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s28: CGFloat = 28

    static let panelGutter: CGFloat = 16   // menu panel, every band
    static let pagePad: CGFloat = 28
    static let pageWidth: CGFloat = 720    // editor, every section, no exceptions
    static let cardPad: CGFloat = 20
    static let labelColumn: CGFloat = 96

    // MARK: Radii — the stage has none, which is the point.

    static let rControl: CGFloat = 8
    static let rCard: CGFloat = 10
    static let rSwatch: CGFloat = 5

    // MARK: Heights

    static let hairlineWidth: CGFloat = 1
    static let rowControl: CGFloat = 30   // a slider or checkbox row
    static let rowNav: CGFloat = 46
    static let rowCell: CGFloat = 34      // effect grid cell
    static let button: CGFloat = 32

    // MARK: Type
    //
    // 11pt is the floor: AppKit's own smallest standard label, and a point above the
    // 10pt and 9pt this app used for status text, badges and captions.

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight)
    }
    static func mono(_ size: CGFloat = 11) -> Font {
        .system(size: size, design: .monospaced)
    }
    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 14, weight: weight)
    }
    static func row(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight)
    }
    static let panelTitle = Font.system(size: 15, weight: .semibold)
    static let sidebarTitle = Font.system(size: 16, weight: .semibold)
    static let sectionTitle = Font.system(size: 22, weight: .semibold)
    static let clockTime = Font.system(size: 30, weight: .medium, design: .monospaced)

    // The micro label, on working surfaces only — rendered by `InkMicro`, which
    // uppercases and tracks it. Still 11pt: the floor above is not negotiable, and
    // this is a role rather than a smaller size.
    //
    // There is deliberately no `numeric()` token beside it. `mono()` is already
    // .system(size:design:.monospaced), so a "tabular" variant would be the same
    // font, and .monospacedDigit() on a monospaced face is a second no-op.
    static let micro = Font.system(size: 11, weight: .semibold)
    static let microTracking: CGFloat = 0.8

    // MARK: Fixed geometry

    static let panelWidth: CGFloat = 410
    static let panelHeight: CGFloat = 660
    /// 410 ÷ (1672/620) = 152.03. Pinned, never derived at layout time, so a budget
    /// overrun elsewhere can never squeeze the board back into a letterbox.
    static let panelStageHeight: CGFloat = 152
    static let sidebarWidth: CGFloat = 84
    static let libraryWidth: CGFloat = 280
    static let stageMaxHeight: CGFloat = 400
}

/// The editor's five sections. Total by construction: there is no `default:` arm
/// anywhere that could silently alias a stray index onto Settings.
enum EditorTab: Int, CaseIterable, Identifiable {
    case lighting = 0, clock = 1, presets = 2, settings = 3, apps = 4

    var id: Int { rawValue }

    /// The order the sidebar lists them in, deliberately NOT the raw order. Raw
    /// values are a wire format — AULA_TAB, the CommandMenu shortcuts and
    /// EditorWindowController.show all address sections by number — so a new
    /// section is appended at 4 and placed by this list, rather than renumbering
    /// Settings out from under the render gate.
    static let sidebarOrder: [EditorTab] = [.lighting, .clock, .presets, .apps, .settings]

    var title: String {
        switch self {
        case .lighting: return "Lighting"
        case .clock: return "Clock"
        case .presets: return "Presets"
        case .settings: return "Settings"
        case .apps: return "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .lighting: return "paintbrush.pointed"
        case .clock: return "clock"
        case .presets: return "square.stack.3d.up"
        case .settings: return "gearshape"
        case .apps: return "macwindow.on.rectangle"
        }
    }

    /// The one place an out-of-range index is resolved. Applied at all three
    /// unvalidated entry points: AULA_TAB, EditorWindowController.show, EditorView.init.
    static func clamped(_ raw: Int) -> EditorTab { EditorTab(rawValue: raw) ?? .lighting }
}
