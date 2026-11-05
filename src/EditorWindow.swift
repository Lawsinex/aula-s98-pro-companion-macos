import SwiftUI
import AppKit

/// Hosts the full SwiftUI editor without declaring an auto-opening Window scene.
/// This keeps normal launches menu-bar-only on every supported macOS version.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    static let shared = EditorWindowController()

    private var window: NSWindow?

    /// True while the editor is on screen. A per-app switch defers rather than
    /// overwriting only in this state, so the hold is always something the user
    /// can end by closing the window.
    var isEditorVisible: Bool { window?.isVisible == true }

    func show(model: AppModel, tab: Int? = nil) {
        alog("ui: opening full editor\(tab.map { " tab \($0)" } ?? "")")
        if let tab { model.selectedTab = EditorTab.clamped(tab).rawValue }

        let editorWindow: NSWindow
        if let window {
            editorWindow = window
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1320, height: 940),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            created.title = "AULA S98 Pro"
            created.appearance = NSAppearance(named: .darkAqua)
            created.backgroundColor = .black
            // The ground has to reach the top edge. A standard titlebar puts a grey
            // bar above a pitch-black window, which is the one place the design
            // cannot afford a seam.
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.styleMask.insert(.fullSizeContentView)
            created.contentMinSize = NSSize(width: 980, height: 680)
            created.contentViewController = NSHostingController(rootView: EditorView(model: model))
            created.isReleasedWhenClosed = false
            created.isRestorable = false
            let environment = ProcessInfo.processInfo.environment
            if environment["AULA_UI_TEST"] == nil && environment["AULA_SNAPSHOT"] != "1" {
                created.setFrameAutosaveName("AulaCompanion.main-editor")
            }
            if let spec = environment["AULA_WINDOW_SIZE"] {
                let parts = spec.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, parts[0] >= 980, parts[1] >= 680,
                   parts[0] <= 4096, parts[1] <= 4096 {
                    created.setContentSize(NSSize(width: parts[0], height: parts[1]))
                }
            }
            created.center()
            created.delegate = self
            window = created
            editorWindow = created
        }

        NSApp.activate(ignoringOtherApps: true)
        editorWindow.makeKeyAndOrderFront(nil)
    }
}

/// Environment-gated host used by UI automation to inspect the exact menu content
/// without changing real preferences or sending HID commands.
@MainActor
final class UIInspectionWindowController {
    static let shared = UIInspectionWindowController()
    private var window: NSWindow?

    func showPanel(model: AppModel) {
        alog("ui test: opening quick-controls fixture")
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        created.title = "Aula S98 Pro Companion Quick Controls"
        created.contentViewController = NSHostingController(rootView: MenuPanelView(model: model))
        created.isReleasedWhenClosed = false
        created.isRestorable = false
        created.center()
        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
