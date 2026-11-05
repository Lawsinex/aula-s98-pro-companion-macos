import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The binding

/// One binding: "when this app comes to the front, put this preset on the keyboard".
///
/// Resolution is by `presetID` and ONLY by `presetID`. `appName` and `presetName`
/// are the labels captured at bind time and are never matched against anything, so
/// renaming a preset changes nothing here, and a deleted preset can never be
/// resurrected by a new preset that happens to reuse its name.
struct AppProfile: Codable, Hashable, Identifiable {
    /// The bundle id of the optional catch-all row. No real app can claim it.
    static let everythingElse = "*"

    var bundleID: String
    var presetID: UUID
    /// Display only. Kept so an app that has since been uninstalled still lists as
    /// itself rather than as a raw reverse-DNS string.
    var appName: String
    /// Display only, and only for the row that has lost its preset.
    var presetName: String

    var id: String { bundleID }
    var isCatchAll: Bool { bundleID == Self.everythingElse }
}

// MARK: - The store

/// Owns the app-activation observer, the debounce, and the bindings.
///
/// Deliberately NOT `@MainActor`, for the same reason `TimeSync` is not: it is an
/// observer host whose notifications arrive on the main queue, and the two places
/// that touch the model hop with `MainActor.assumeIsolated` — the pattern already
/// used by `AppModel`'s willTerminate observer.
final class AppProfileStore: ObservableObject, @unchecked Sendable {
    static let shared = AppProfileStore()

    /// The master switch. Default OFF: a feature that silently takes the lighting
    /// away from you is hostile, so it does nothing until it is asked to.
    /// Turning it off REMOVES the observer rather than early-returning inside it,
    /// so an app that does not want this pays nothing for it.
    @Published var enabled: Bool = false {
        didSet {
            guard enabled != oldValue else { return }
            enabled ? installObserver() : removeObserver()
            pendingWork?.cancel(); pendingWork = nil
            frontBundleID = nil
            lastEvent = enabled ? "Waiting for the next app switch" : "Off"
            alog("profiles: per-app lighting \(enabled ? "on" : "off")")
            onChange?()
        }
    }

    @Published private(set) var profiles: [AppProfile] = []
    /// What the last activation did, in words. Only ever written on the main queue.
    @Published private(set) var lastEvent: String = "Off"

    /// Called after any change the workspace blob should record. `AppModel` sets it.
    var onChange: (() -> Void)?

    /// False for snapshot and test models. No `NSWorkspace` observer is EVER
    /// installed when this is false, whatever `enabled` is set to — the same
    /// isolation `TimeSync(persistPreferences:)` gives the clock.
    private let observesWorkspace: Bool
    /// Cmd-Tab spam produces one activation per app you pass through. A device
    /// transaction is five packets and roughly 350 ms, so the settle window sits
    /// just above it: only the app you actually land on survives.
    private let settleDelay: TimeInterval

    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var pendingWork: DispatchWorkItem?
    /// The last app we accepted an activation for. Never updated for Aula S98 Pro Companion
    /// itself, so Terminal → Aula S98 Pro Companion → Terminal is a no-op on the way back.
    private var frontBundleID: String?

    init(observesWorkspace: Bool = true, settleDelay: TimeInterval = 0.45) {
        self.observesWorkspace = observesWorkspace
        self.settleDelay = settleDelay
    }

    deinit {
        pendingWork?.cancel()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    // MARK: Lifecycle

    /// Mirrors `TimeSync.attach(_:)`. Called from `AppModel.start()`, which the
    /// snapshot and CLI paths never reach in a state that matters.
    func attach(model: AppModel) {
        guard self.model !== model else { return }
        self.model = model
        if enabled { installObserver() }
    }

    /// Seeds from the persisted workspace. Called before `onChange` is wired, so
    /// restoring never writes the blob straight back.
    func restore(profiles stored: [AppProfile], enabled storedEnabled: Bool) {
        var seen = Set<String>()
        profiles = stored.filter { !$0.bundleID.isEmpty && seen.insert($0.bundleID).inserted }
        sortProfiles()
        enabled = storedEnabled
        lastEvent = storedEnabled ? "Waiting for the next app switch" : "Off"
    }

    private func installObserver() {
        guard observesWorkspace, model != nil, observers.isEmpty else { return }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                self?.handleActivation(app)
            }
        ]
        alog("profiles: watching app activation")
    }

    private func removeObserver() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }

    // MARK: Bindings

    func bind(bundleID: String, appName: String, to preset: Preset) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let entry = AppProfile(bundleID: id, presetID: preset.id,
                               appName: appName.isEmpty ? id : String(appName.prefix(80)),
                               presetName: preset.name)
        if let index = profiles.firstIndex(where: { $0.bundleID == id }) {
            profiles[index] = entry
        } else {
            profiles.append(entry)
        }
        sortProfiles()
        onChange?()
    }

    func unbind(_ bundleID: String) {
        guard profiles.contains(where: { $0.bundleID == bundleID }) else { return }
        profiles.removeAll { $0.bundleID == bundleID }
        onChange?()
    }

    /// The exact binding if there is one, else the catch-all if there is one.
    /// An exact binding that exists but is BROKEN is returned as itself and is not
    /// quietly answered by the catch-all: you asked for that preset, and it is gone.
    /// True when any binding points at a preset that no longer exists. The sidebar
    /// shows a pip for it, so a broken binding is findable without opening the
    /// section to hunt for it.
    func hasUnresolvedBinding(in presets: [Preset]) -> Bool {
        let ids = Set(presets.map(\.id))
        return profiles.contains { !ids.contains($0.presetID) }
    }

    func binding(for bundleID: String) -> AppProfile? {
        profiles.first { $0.bundleID == bundleID } ?? profiles.first(where: \.isCatchAll)
    }

    /// Nil when nothing is bound, or when the bound preset no longer exists.
    /// Never force-unwraps, never invents a preset.
    func resolvedPreset(for bundleID: String, in presets: [Preset]) -> Preset? {
        guard let binding = binding(for: bundleID) else { return nil }
        return presets.first { $0.id == binding.presetID }
    }

    private func sortProfiles() {
        // `caseInsensitiveCompare`, not `localizedStandardCompare`: the render gate
        // needs an ordering that cannot move with the machine's locale.
        profiles.sort {
            if $0.isCatchAll != $1.isCatchAll { return !$0.isCatchAll }
            let byName = $0.appName.caseInsensitiveCompare($1.appName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return $0.bundleID < $1.bundleID
        }
    }

    // MARK: Activation

    private func handleActivation(_ app: NSRunningApplication?) {
        guard enabled, let bundleID = app?.bundleIdentifier, !bundleID.isEmpty else { return }
        // Aula S98 Pro Companion itself NEVER triggers a switch. Opening the editor or the menu
        // panel must not change your lighting — and because `frontBundleID` is
        // left alone here, coming back out of the editor is a no-op too.
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        // The same app re-activated (click away to Finder's desktop and back, a
        // save panel closing) is not a switch.
        guard bundleID != frontBundleID else { return }
        frontBundleID = bundleID

        let name = app?.localizedName ?? bundleID
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyProfile(for: bundleID, appName: name) }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    @MainActor
    private func applyProfile(for bundleID: String, appName: String) {
        pendingWork = nil
        guard enabled, let model else { return }

        guard let binding = binding(for: bundleID) else {
            // No match: leave the lighting exactly as it is. Reverting here would
            // make every switch to Finder, Spotlight or a file dialog's owner an
            // unwanted USB transaction, and unbound apps are the common case.
            lastEvent = "\(appName) — no binding; lighting left alone"
            return
        }

        guard let preset = model.presets.presets.first(where: { $0.id == binding.presetID }) else {
            lastEvent = "\(appName) — “\(binding.presetName)” is no longer saved"
            alog("profiles: \(bundleID) is bound to a preset that no longer exists; ignored")
            return
        }

        // Never throw away edits made since startup or the last durable apply
        // while the user is looking at them. Closing the editor lifts the hold.
        if model.hasUncommittedLightingWork, EditorWindowController.shared.isEditorVisible {
            lastEvent = "\(appName) — held: unapplied changes are open in the editor"
            return
        }

        if alreadyOnKeyboard(preset, model: model) {
            lastEvent = "\(appName) — \(preset.name) (already on the keyboard)"
            return
        }

        // Undo is recorded like any other whole-frame replacement: pushUndo is the
        // sole caller of redoStack.removeAll() and updateUndoState(), so skipping
        // it corrupts the stack rather than sparing it. The guards above already
        // stop the flood this was meant to prevent.
        // frames through the per-key undo stack and erase your own history.
        model.apply(preset)
        lastEvent = "\(appName) — \(preset.name)"
        alog("profiles: \(bundleID) -> \(preset.name)")
    }

#if AULA_LOGIC_TESTS
    /// Exercises the actual application path without installing an NSWorkspace observer.
    @MainActor
    func applyProfileForTesting(bundleID: String, appName: String) {
        applyProfile(for: bundleID, appName: appName)
    }
#endif

    /// Compared against what the DEVICE last confirmed, not against staged state,
    /// so any manual change since invalidates the skip on its own — no bookkeeping
    /// hook in a dozen mutating methods.
    @MainActor
    private func alreadyOnKeyboard(_ preset: Preset, model: AppModel) -> Bool {
        if preset.isPerKey {
            guard let applied = model.lastAppliedKeys else { return false }
            return applied == preset.keys
                && model.lastAppliedKeysBrightness == preset.state.normalized.brightness
        }
        return model.lastAppliedLight == preset.state.normalized
    }

    // MARK: Snapshot fixture

    /// A fixed set of bindings for the render gate: three live ones, one whose
    /// preset has been deleted (so the gate covers the ghost-safety path), and the
    /// catch-all. Built from the built-in presets, whose UUIDs are literals, so
    /// the render is byte-identical run to run.
    func loadFixture() {
        let builtIns = PresetStore.builtIns
        guard builtIns.count >= 4 else { return }
        profiles = [
            AppProfile(bundleID: "com.apple.Terminal", presetID: builtIns[2].id,
                       appName: "Terminal", presetName: builtIns[2].name),
            AppProfile(bundleID: "com.figma.Desktop", presetID: builtIns[1].id,
                       appName: "Figma", presetName: builtIns[1].name),
            AppProfile(bundleID: "com.valvesoftware.steam", presetID: builtIns[3].id,
                       appName: "Steam", presetName: builtIns[3].name),
            AppProfile(bundleID: "com.example.retired",
                       presetID: UUID(uuidString: "DEAD0001-0000-4000-8000-000000000001")!,
                       appName: "Old Editor", presetName: "Midnight"),
            AppProfile(bundleID: AppProfile.everythingElse, presetID: builtIns[0].id,
                       appName: "Everything else", presetName: builtIns[0].name),
        ]
        sortProfiles()
        enabled = true
        lastEvent = "Terminal — \(builtIns[2].name)"
    }
}

// MARK: - Running applications

struct RunningApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    /// Only ever called from a sheet's `.onAppear`. Nothing in a rendered view
    /// body touches `runningApplications`, because its contents are whatever the
    /// machine happens to be running.
    static func current() -> [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, !id.isEmpty,
                      id != Bundle.main.bundleIdentifier,
                      seen.insert(id).inserted else { return nil }
                return RunningApp(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Icons

/// App icons are the single most environment-dependent thing this feature could
/// draw, so the render path never reads one. In snapshot mode every icon is a
/// placeholder derived from an EXPLICIT FNV-1a hash of the bundle id — not
/// `hashValue`, which is seeded per process and would change the render on every
/// single run.
@MainActor
enum AppIconSource {
    private static var cache: [String: NSImage] = [:]
    private static let side: CGFloat = 18

    static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return hash
    }

    static func icon(bundleID: String, name: String, deterministic: Bool) -> NSImage {
        let key = bundleID
        if let hit = cache[key] { return hit }
        let image = deterministic
            ? placeholder(bundleID: bundleID, name: name)
            : resolved(bundleID: bundleID, name: name)
        cache[key] = image
        return image
    }

    private static func resolved(bundleID: String, name: String) -> NSImage {
        guard bundleID != AppProfile.everythingElse,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return placeholder(bundleID: bundleID, name: name) }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        // Redrawn rather than resized: `icon(forFile:)` can hand back a shared
        // instance, and mutating its size would resize it for everyone.
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }

    private static func placeholder(bundleID: String, name: String) -> NSImage {
        let hash = stableHash(bundleID)
        let top = Double(hash % 360) / 360
        let bottom = Double((hash / 360) % 360) / 360
        let letter = String(name.uppercased().prefix(1))
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 4, yRadius: 4)
            let gradient = NSGradient(
                starting: NSColor(hue: CGFloat(top), saturation: 0.55,
                                  brightness: 0.62, alpha: 1),
                ending: NSColor(hue: CGFloat(bottom), saturation: 0.55,
                                brightness: 0.30, alpha: 1))
            gradient?.draw(in: path, angle: -90)
            NSColor(white: 1, alpha: 0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
            if !letter.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor(white: 1, alpha: 0.92),
                ]
                let text = letter as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: rect.midX - size.width / 2,
                                      y: rect.midY - size.height / 2),
                          withAttributes: attributes)
            }
            return true
        }
    }
}

// MARK: - The Apps section

struct AppProfilesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: AppProfileStore
    @Environment(\.snapshotMode) private var snapshotMode
    @State private var adding = false

    private func preset(for profile: AppProfile) -> Preset? {
        // Resolved live, by id. This is why a rename needs no bookkeeping: the row
        // shows whatever the preset is called right now.
        model.presets.presets.first { $0.id == profile.presetID }
    }

    var body: some View {
        VStack(spacing: 0) {
            InkSectionBar("Apps")
            InkRule()
            VScroll {
                InkPage {
                    InkCard(title: "Per-app lighting",
                            detail: "Switch to one of these apps and Aula S98 Pro Companion puts its preset on the keyboard.") {
                        VStack(alignment: .leading, spacing: Ink.s12) {
                            Toggle("Change the lighting when I change apps",
                                   isOn: $store.enabled)
                                .toggleStyle(.checkbox)
                                .font(Ink.body())

                            InkRow("Last event") {
                                Text(store.lastEvent)
                                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 0)
                            }

                            Text("Aula S98 Pro Companion never reacts to itself, so opening this editor "
                                 + "leaves your lighting alone. An app with no binding also "
                                 + "leaves it alone — add an “Everything else” row if you "
                                 + "would rather it reset.")
                                .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if store.enabled && store.profiles.isEmpty {
                        InkNotice("Per-app lighting is on, but no app is bound yet.",
                                  systemImage: "app.dashed")
                    }

                    InkCard(title: "Bindings") {
                        VStack(alignment: .leading, spacing: Ink.s8) {
                            if store.profiles.isEmpty {
                                Text("No apps are bound yet.")
                                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                                    .padding(.vertical, Ink.s8)
                            } else {
                                ForEach(store.profiles) { profile in
                                    let bound = preset(for: profile)
                                    AppProfileRow(
                                        profile: profile,
                                        preset: bound,
                                        swatch: bound.map { model.displayColor($0.swatch) },
                                        deterministicIcons: snapshotMode,
                                        presets: model.presets.presets,
                                        rebind: { store.bind(bundleID: profile.bundleID,
                                                             appName: profile.appName,
                                                             to: $0) },
                                        remove: { store.unbind(profile.bundleID) })
                                }
                            }

                            InkRule().padding(.vertical, Ink.s4)

                            HStack(spacing: Ink.s8) {
                                InkButton("Bind an app…", icon: "plus", tone: .accent) {
                                    adding = true
                                }
                                Spacer(minLength: 0)
                                Text("\(store.profiles.count) binding"
                                     + (store.profiles.count == 1 ? "" : "s"))
                                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                            }
                        }
                    }
                }
            }
        }
        // A sheet is never rasterised by ImageRenderer, which is exactly why the
        // environment-dependent parts of this feature live inside one.
        .sheet(isPresented: $adding) {
            AppBindingSheet(presets: model.presets.presets) { bundleID, name, preset in
                store.bind(bundleID: bundleID, appName: name, to: preset)
                adding = false
            } onCancel: {
                adding = false
            }
        }
    }
}

private struct AppProfileRow: View {
    let profile: AppProfile
    let preset: Preset?
    let swatch: RGB8?
    let deterministicIcons: Bool
    let presets: [Preset]
    let rebind: (Preset) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Ink.s12) {
            Image(nsImage: AppIconSource.icon(bundleID: profile.bundleID,
                                              name: profile.appName,
                                              deterministic: deterministicIcons))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.appName)
                    .font(Ink.body(.medium)).foregroundStyle(Ink.text).lineLimit(1)
                Text(profile.isCatchAll ? "Any app with no binding of its own"
                                        : profile.bundleID)
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: Ink.s8)

            if let preset {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: Ink.rSwatch, style: .continuous)
                        .fill(Color(swatch ?? preset.swatch))
                        .frame(width: 22, height: 16)
                        .overlay(RoundedRectangle(cornerRadius: Ink.rSwatch,
                                                  style: .continuous)
                            .strokeBorder(Ink.stroke, lineWidth: 1))
                    Text(preset.name)
                        .font(Ink.caption()).foregroundStyle(Ink.text).lineLimit(1)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundStyle(Ink.bad)
                    Text("“\(profile.presetName)” was deleted")
                        .font(Ink.caption()).foregroundStyle(Ink.bad).lineLimit(1)
                }
            }

            Menu {
                Section("Use preset") {
                    ForEach(presets) { candidate in
                        Button(candidate.name) { rebind(candidate) }
                    }
                }
                Button("Remove binding", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .accessibilityLabel("Actions for \(profile.appName)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Ink.s8)
        .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
            .fill(Ink.well))
        .overlay(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
            .strokeBorder(preset == nil ? Ink.bad : Ink.hairline, lineWidth: Ink.hairlineWidth))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(preset == nil
            ? "\(profile.appName), bound preset was deleted"
            : "\(profile.appName), \(preset?.name ?? "")")
    }
}

private struct AppBindingSheet: View {
    let presets: [Preset]
    let onAdd: (String, String, Preset) -> Void
    let onCancel: () -> Void

    @State private var candidates: [RunningApp] = []
    @State private var selectedBundle = AppProfile.everythingElse
    @State private var selectedPreset: UUID?

    private var chosenName: String {
        if selectedBundle == AppProfile.everythingElse { return "Everything else" }
        return candidates.first { $0.bundleID == selectedBundle }?.name ?? selectedBundle
    }

    private var chosenPreset: Preset? {
        selectedPreset.flatMap { id in presets.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.s16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bind an app").font(Ink.sectionTitle).foregroundStyle(Ink.text)
                Text("Apps that are running now are listed here. Anything else can be "
                     + "picked from Applications.")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }

            InkRow("App") {
                Picker("App", selection: $selectedBundle) {
                    Text("Everything else").tag(AppProfile.everythingElse)
                    ForEach(candidates) { app in Text(app.name).tag(app.bundleID) }
                }
                .labelsHidden()
                .frame(width: 220)
                InkButton("Choose…", icon: "folder", action: chooseApplication)
                Spacer(minLength: 0)
            }

            InkRow("Preset") {
                Picker("Preset", selection: $selectedPreset) {
                    Text("Choose a preset").tag(UUID?.none)
                    ForEach(presets) { preset in
                        Text(preset.name).tag(UUID?.some(preset.id))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                InkButton("Cancel", action: onCancel)
                InkButton("Bind", tone: .accent) {
                    guard let preset = chosenPreset else { return }
                    onAdd(selectedBundle, chosenName, preset)
                }
                .disabled(chosenPreset == nil)
            }
        }
        .padding(Ink.pagePad)
        .frame(width: 460)
        .background(Ink.ground)
        .onAppear { candidates = RunningApp.current() }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application, .applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let identifier = Bundle(url: url)?.bundleIdentifier,
              !identifier.isEmpty else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        if !candidates.contains(where: { $0.bundleID == identifier }) {
            candidates.append(RunningApp(bundleID: identifier, name: name))
            candidates.sort { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
        }
        selectedBundle = identifier
    }
}
