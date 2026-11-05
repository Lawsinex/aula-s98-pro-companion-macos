import SwiftUI
import AppKit
import ServiceManagement

extension Color {
    init(_ color: RGB8) {
        self.init(.sRGB, red: Double(color.r) / 255,
                  green: Double(color.g) / 255,
                  blue: Double(color.b) / 255)
    }
}

extension RGB8 {
    var relativeLuminance: Double {
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    var accessibleLabel: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        return "red \(r), green \(g), blue \(b)"
    }
}

#if !AULA_LOGIC_TESTS

/// The way back in when the menu bar is full.
///
/// A menu-bar-only app does nothing at all when you click it in Finder, Spotlight
/// or the Dock — macOS considers it already running and there is no window to
/// raise. That leaves no route to the editor on a small screen with a crowded
/// menu bar, which is exactly when you need one.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by AulaCompanionApp.init, and left nil in snapshot and self-test runs so a
    /// headless render can never be interrupted by a window opening.
    static weak var model: AppModel?

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        guard let model = Self.model else { return false }
        EditorWindowController.shared.show(model: model)
        return true
    }
}

@main
@MainActor
struct AulaCompanionApp: App {
    @StateObject private var model: AppModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        alog("--- Aula S98 Pro Companion launched ---")
        let environment = ProcessInfo.processInfo.environment
        // The app is dark-only: the preview is a photograph shot on black, and the
        // whole design is built to let it dissolve into the ground. Pinning the
        // NSApplication appearance is the single lever that carries popovers,
        // sheets, alerts, NSMenu, the save/open panels and the titlebar with us —
        // none of which .preferredColorScheme reliably reaches. Offscreen renders
        // inject their own colorScheme, so this stays out of their way.
        if environment["AULA_SNAPSHOT"] != "1" {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        let isolated = environment["AULA_SNAPSHOT"] == "1" ||
            environment["AULA_LOGIN"] != nil || environment["AULA_UI_TEST"] != nil
        if !isolated { LegacyDataMigration.runOnce() }
        let activeModel = isolated ? AppModel.snapshot() : AppModel.shared
        _model = StateObject(wrappedValue: activeModel)
        // Inspection inputs are confined to the isolated model: visual QA cannot
        // overwrite the user's saved workspace or send fixture colours over USB.
        if isolated {
            if let raw = environment["AULA_MODE"], let mode = Int(raw),
               kModes.contains(where: { $0.id == mode }) { activeModel.light.mode = mode }
            if let raw = environment["AULA_COLOUR"], let colour = RGB8(hex: raw) {
                activeModel.light.color = colour
            }
            if environment["AULA_SOURCE"] == "perkey" {
                activeModel.lightingSource = .perKey
                if environment["AULA_KB_RAINBOW"] == "1" { activeModel.keys = Paint.rainbowHorizontal() }
            }
            if let raw = environment["AULA_TAB"], let tab = Int(raw) {
                activeModel.selectedTab = EditorTab.clamped(tab).rawValue
            }
            if environment["AULA_PALETTE"] == "fixture" {
                activeModel.recentColors = ["FFC799", "FF3B30", "FFCC00", "34C759", "007AFF", "AF52DE"]
                    .compactMap { RGB8(hex: $0) }
            }
        }

        if environment["AULA_SNAPSHOT"] == "1" {
            let tab = EditorTab.clamped(Int(environment["AULA_TAB"] ?? "0") ?? 0).rawValue
            let output = environment["AULA_SNAPSHOT_OUT"] ?? "/tmp/aula-ui.png"
            let panel = environment["AULA_SNAPSHOT_PANEL"] ?? ""
            // Two render dimensions the smokes could never reach before: the per-key
            // paint inspector (LightingView always defaulted to .effect offscreen) and
            // the panel with the lights off (a different cell, an unlit stage, and the
            // colour and brightness controls in their disabled states).
            if environment["AULA_SOURCE"] == "perkey" { activeModel.lightingSource = .perKey }
            // A fixed set of bindings, built from the built-in presets' literal
            // UUIDs — including one deliberately dangling id, so the render covers
            // the ghost-binding path. Never the live running-app list, which would
            // differ on every machine and every run.
            if environment["AULA_PROFILES"] == "fixture" { activeModel.appProfiles.loadFixture() }
            if let raw = environment["AULA_MODE"], let mode = Int(raw),
               kModes.contains(where: { $0.id == mode }) {
                activeModel.light.mode = mode
            }
            let renderer: ImageRenderer<AnyView>
            if panel == "keyboard3d" {
                // The preview is a WKWebView, which ImageRenderer cannot rasterise —
                // so the photo board gets its own review path through takeSnapshot.
                // The panel name is kept: verify.sh and the gates address it.
                let out = environment["AULA_SNAPSHOT_OUT"] ?? "/tmp/aula-kb3d.png"
                let name = environment["AULA_KB_EFFECT"] ?? "Static On"
                let hex = environment["AULA_KB_COLOUR"] ?? "FF5A1F"
                let colour = RGB8(hex: hex) ?? RGB8(r: 255, g: 90, b: 31)
                var frame: [Int: RGB8] = [:]
                // An explicit per-key frame, as JSON {"<ledId>":[r,g,b], ...}.
                // The round-trip gate needs to drive all 96 keys independently,
                // which no single-colour hook can express.
                if let path = environment["AULA_KB_FRAME"],
                   let data = FileManager.default.contents(atPath: path),
                   let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [Int]] {
                    for (key, rgb) in raw where rgb.count == 3 {
                        guard let id = Int(key), kLedIndices.contains(id) else { continue }
                        frame[id] = RGB8(r: UInt8(clamping: rgb[0]),
                                         g: UInt8(clamping: rgb[1]),
                                         b: UInt8(clamping: rgb[2]))
                    }
                } else if environment["AULA_KB_RAINBOW"] == "1" {
                    frame = Paint.rainbowHorizontal()
                } else if environment["AULA_KB_ZONES"] == "1" {
                    // The split the reference photograph was shot in: ember on
                    // the main field, ice on the numpad.
                    let ice = RGB8(r: 0, g: 150, b: 255)
                    for cap in kKeyCaps { frame[cap.id] = cap.x >= 560 ? ice : colour }
                } else if environment["AULA_KB_OFF"] != "1" {
                    for id in kLedIndices { frame[id] = colour }
                }
                // The round-trip gates render at the reference photographs' own
                // dimensions so nothing has to be resampled before comparison.
                var canvas = CGSize(width: 1672, height: 941)
                if let spec = environment["AULA_SNAPSHOT_SIZE"] {
                    let parts = spec.lowercased().split(separator: "x")
                    if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
                       w >= 64, h >= 64, w <= 8192, h <= 8192 {
                        canvas = CGSize(width: w, height: h)
                    }
                }
                let image = KeyboardWebSnapshot.render(
                    colors: frame, label: name, size: canvas)
                if let data = image?.tiffRepresentation
                    .flatMap({ NSBitmapImageRep(data: $0) })
                    .flatMap({ $0.representation(using: .png, properties: [:]) }) {
                    try? data.write(to: URL(fileURLWithPath: out))
                    alog("keyboard3d snapshot -> \(out)")
                } else {
                    alog("ERR keyboard3d snapshot failed")
                    exit(1)
                }
                exit(0)
            }
            if panel == "menu" {
                renderer = ImageRenderer(content: AnyView(
                    MenuPanelView(model: activeModel)
                        .environment(\.snapshotMode, true)
                        .environment(\.colorScheme, .dark)
                        .background(Ink.ground)))
            } else if panel == "calibration" || panel == "colour" {
                renderer = ImageRenderer(content: AnyView(
                    ColorEditorSnapshot(startCalibrating: panel == "calibration")
                        .environment(\.colorScheme, .dark)))
            } else {
                // The window supplies the ground at runtime; an ImageRenderer does not,
                // so it is painted explicitly here. groundaudit.py asserts it landed.
                renderer = ImageRenderer(content: AnyView(
                    EditorView(model: activeModel, initialTab: tab)
                        .environment(\.snapshotMode, true)
                        .environment(\.snapshotViewport, true)
                        // A fixed editor viewport. Taller snapshot-only stacks are
                        // top-aligned, not centred with the titlebar outside the
                        // frame; the live version scrolls this same content.
                        .frame(width: 1280, height: 940, alignment: .topLeading)
                        .clipped()
                        .environment(\.colorScheme, .dark)
                        .background(Ink.ground)))
            }
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try png.write(to: URL(fileURLWithPath: output), options: .atomic)
                    alog("snapshot tab \(tab) -> \(output)")
                } catch {
                    alog("ERR snapshot write failed: \(error.localizedDescription)")
                    exit(1)
                }
            } else {
                alog("ERR snapshot rendering failed")
                exit(1)
            }
            exit(0)
        }

        if let command = environment["AULA_LOGIN"] {
            runLoginCommand(command)
        }

        if environment["AULA_TIMETEST"] == "1" {
            usleep(500_000)
            let ok = waitForJob(.time(Date()), on: activeModel.device, timeout: 4)
            alog("timetest completed=\(ok)")
            exit(ok ? 0 : 1)
        }

        if environment["AULA_SELFTEST"] == "1" {
            usleep(500_000)
            var state = LightState()
            state.mode = 1; state.color = RGB8(r: 0, g: 255, b: 0)
            let modeOK = waitForJob(.mode(state, persist: true),
                                    on: activeModel.device, timeout: 5)
            let keysOK = modeOK && waitForJob(
                .perKey(Paint.rainbowHorizontal(), brightness: 5, persist: true),
                on: activeModel.device, timeout: 7)
            let clockOK = keysOK && waitForJob(.time(Date()),
                                               on: activeModel.device, timeout: 4)
            let ok = modeOK && keysOK && clockOK
            alog("selftest mode=\(modeOK) perKey=\(keysOK) clock=\(clockOK)")
            exit(ok ? 0 : 1)
        }

        activeModel.start()

        if !isolated {
            AppDelegate.model = activeModel
            // Honour the saved choice before any window appears, so the Dock icon
            // and the editor arrive together rather than a frame apart.
            activeModel.applyActivationPolicy()
            if activeModel.openEditorAtLaunch {
                DispatchQueue.main.async {
                    EditorWindowController.shared.show(model: activeModel)
                }
            }
        }

        if environment["AULA_UI_TEST"] != nil, let out = environment["AULA_WINDOW_SHOT_OUT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exit(KeyboardWebSnapshot.captureWindow(to: out) ? 0 : 1)
            }
        }
        if environment["AULA_UI_TEST"] == "panel" {
            DispatchQueue.main.async {
                UIInspectionWindowController.shared.showPanel(model: activeModel)
            }
        } else if environment["AULA_UI_TEST"] == "editor" {
            DispatchQueue.main.async {
                EditorWindowController.shared.show(model: activeModel)
            }
            // Review hook: prove the preview really renders inside the live
            // SwiftUI window. The offscreen path cannot show that, because it
            // never goes through NSViewRepresentable hosting.
            if let out = environment["AULA_LIVE_PREVIEW_OUT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    let ok = KeyboardWebSnapshot.renderLive(to: out)
                    alog(ok ? "live preview snapshot -> \(out)"
                            : "ERR live preview did not render")
                    // The paint bridge is the other half: a click in the page
                    // has to come back across as an LED id.
                    let bridged = KeyboardWebSnapshot.checkPaintBridge()
                    alog(bridged ? "paint bridge ok" : "ERR paint bridge is dead")
                    exit(ok && bridged ? 0 : 1)
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(model: model)
        } label: {
            Label("AULA S98 Pro",
                  systemImage: model.device.connected ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandMenu("Aula S98 Pro Companion") {
                Button("Lighting") { EditorWindowController.shared.show(model: model, tab: 0) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Clock") { EditorWindowController.shared.show(model: model, tab: 1) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Presets") { EditorWindowController.shared.show(model: model, tab: 2) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Settings") { EditorWindowController.shared.show(model: model, tab: 3) }
                    .keyboardShortcut("4", modifiers: .command)
                // Command-5 is Apps even though the sidebar lists it fourth: the
                // shortcuts follow the raw values, which are a stable wire format.
                Button("Apps") { EditorWindowController.shared.show(model: model, tab: 4) }
                    .keyboardShortcut("5", modifiers: .command)
                Divider()
                Button("Open Editor") { EditorWindowController.shared.show(model: model) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
    }

    private func runLoginCommand(_ command: String) -> Never {
        if command == "status" {
            let status = SMAppService.mainApp.status
            let names = ["not registered", "enabled", "requires approval", "not found"]
            let name = status.rawValue < names.count ? names[Int(status.rawValue)] : "unknown"
            alog("login item status=\(status.rawValue) (\(name))")
            exit(status == .enabled ? 0 : 1)
        }
        do {
            if command == "1" { try SMAppService.mainApp.register() }
            else if command == "0" { try SMAppService.mainApp.unregister() }
            else { alog("ERR AULA_LOGIN must be 0, 1, or status"); exit(2) }
            alog("login item \(command == "1" ? "registered" : "unregistered")")
            exit(0)
        } catch {
            alog("ERR login item: \(error.localizedDescription)")
            exit(1)
        }
    }

    private func waitForJob(_ job: Job, on device: AulaDevice, timeout: TimeInterval) -> Bool {
        var outcome: Result<String, DeviceOperationError>?
        device.apply(job) { outcome = $0 }
        let deadline = Date().addingTimeInterval(timeout)
        while outcome == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if case .success? = outcome { return true }
        if case .failure(let error)? = outcome { alog("ERR selftest: \(error.localizedDescription)") }
        else { alog("ERR selftest timed out") }
        return false
    }
}
#endif
