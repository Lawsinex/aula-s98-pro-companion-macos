import Foundation
import AppKit
import Combine

/// The two ways the keys can be lit: a firmware animation, or your own per-key frame.
enum LightingSource: String, Codable, CaseIterable, Identifiable {
    case effect, perKey
    var id: String { rawValue }
    var title: String { self == .effect ? "Effect" : "Per-key" }
    var summary: String {
        self == .effect
            ? "A built-in animation runs on the keyboard itself."
            : "Your own colour for every key, uploaded as one frame."
    }
}

private struct StoredWorkspace: Codable {
    var schemaVersion = 2
    var light: LightState
    var keys: [Int: RGB8]
    var brush: RGB8
    var gradientStart: RGB8
    var gradientEnd: RGB8
    var config: KeyboardConfig
    var recentColors: [RGB8]
    var savedColorsCurated: Bool?
    var calibration: ColorCalibration?
    var calibrationPreviewEnabled: Bool?
    var lightingSource: String?
    var modeLabels: [Int: String]?
    var showInDock: Bool?
    var openEditorAtLaunch: Bool?
    /// Both OPTIONAL, like every field added since v1. A non-optional makes the
    /// whole blob fail to decode on the first launch after an update and silently
    /// resets the entire workspace — a far bigger loss than the feature is a gain.
    var appProfiles: [AppProfile]?
    var appProfilesEnabled: Bool?
}

/// One source of truth shared by the menu-bar panel and the full editor window.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let device: AulaDevice
    let presets: PresetStore
    let clock: TimeSync
    let appProfiles: AppProfileStore

    @Published var light: LightState { didSet { schedulePersistence() } }
    @Published var keys: [Int: RGB8] { didSet { schedulePersistence() } }
    @Published var brush: RGB8 { didSet { schedulePersistence() } }
    @Published var gradientStart: RGB8 { didSet { schedulePersistence() } }
    @Published var gradientEnd: RGB8 { didSet { schedulePersistence() } }
    @Published var config: KeyboardConfig { didSet { schedulePersistence() } }
    @Published var recentColors: [RGB8] { didSet { schedulePersistence() } }
    @Published var calibration: ColorCalibration { didSet { schedulePersistence() } }
    /// Whether the app renders colours the way the keyboard really shows them.
    /// Switch it off to see true colours while collecting more data points.
    @Published var calibrationPreviewEnabled: Bool { didSet { schedulePersistence() } }
    /// Which lighting source the combined tab is editing. Switching never discards
    /// the other one's work — both live on until they are applied.
    @Published var lightingSource: LightingSource { didSet { schedulePersistence() } }
    @Published private(set) var modeLabels: [Int: String] { didSet { saveModeLabels() } }
    @Published private(set) var lastAppliedLight: LightState? { didSet { schedulePersistence() } }
    @Published private(set) var lastAppliedKeys: [Int: RGB8]? { didSet { schedulePersistence() } }
    @Published private(set) var lastAppliedKeysBrightness: Int?
    @Published private(set) var lastAppliedConfig: KeyboardConfig? { didSet { schedulePersistence() } }
    @Published private(set) var canUndoKeys = false
    @Published private(set) var canRedoKeys = false
    @Published var selectedTab = 0

    private let persistsWorkspace: Bool
    private var started = false
    private var persistWork: DispatchWorkItem?
    private var modePreviewWork: DispatchWorkItem?
    private var paintBaseline: [Int: RGB8]?
    private var undoStack: [[Int: RGB8]] = []
    private var redoStack: [[Int: RGB8]] = []
    // Draft protection is independent of hardware confirmation. A reconnect or
    // calibration probe makes hardware state unknown, not the user's edits clean.
    private var lightingBaseline = LightState()
    private var keysBaseline: [Int: RGB8] = [:]
    private var keysBrightnessBaseline = 5
    private var cancellables: Set<AnyCancellable> = []
    private static let workspaceKey = "workspace.v1"

    /// Identification work is expensive to redo by hand, so it lives in its own small
    /// file rather than inside the workspace blob. A schema change, a failed decode or
    /// a reset of the rest of the workspace can no longer wipe it, and it is written
    /// immediately instead of on the persistence debounce.
    private static let modeLabelsURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aula S98 Pro Companion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mode-labels.json")
    }()

    private static func storedModeLabels() -> [Int: String]? {
        guard let data = try? Data(contentsOf: modeLabelsURL) else { return nil }
        return decodeModeLabels(data)
    }

    /// Persisted keys are canonical decimal mode IDs. Reject aliases such as "015"
    /// rather than letting two JSON keys collapse into one and trap at launch.
    static func decodeModeLabels(_ data: Data) -> [Int: String]? {
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return raw.reduce(into: [:]) { labels, entry in
            guard let mode = Int(entry.key), String(mode) == entry.key else { return }
            labels[mode] = entry.value
        }
    }

    private func saveModeLabels() {
        guard persistsWorkspace else { return }
        let raw = Dictionary(uniqueKeysWithValues: modeLabels.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: Self.modeLabelsURL, options: .atomic)
    }

    init(device: AulaDevice = .shared,
         presets: PresetStore = .shared,
         clock: TimeSync = .shared,
         appProfiles: AppProfileStore = .shared,
         persistsWorkspace: Bool = true) {
        self.device = device
        self.presets = presets
        self.clock = clock
        self.appProfiles = appProfiles
        self.persistsWorkspace = persistsWorkspace

        let stored: StoredWorkspace? = {
            guard persistsWorkspace,
                  let data = UserDefaults.standard.data(forKey: Self.workspaceKey) else { return nil }
            return try? JSONDecoder().decode(StoredWorkspace.self, from: data)
        }()
        light = stored?.light.normalized ?? LightState()
        keys = stored?.keys.filter { Set(kLedIndices).contains($0.key) } ?? [:]
        brush = stored?.brush ?? RGB8(r: 255, g: 59, b: 48)
        gradientStart = stored?.gradientStart ?? RGB8(r: 175, g: 82, b: 222)
        gradientEnd = stored?.gradientEnd ?? RGB8(r: 50, g: 215, b: 255)
        config = stored?.config.normalized ?? KeyboardConfig()
        // The list used to fill itself on every commit, which just produced a row of
        // near-identical shades. It is user-curated now, so the auto-collected one is
        // discarded once and never rebuilt behind their back.
        recentColors = (stored?.savedColorsCurated == true)
            ? (stored?.recentColors ?? []).prefix(12).map { $0 }
            : []
        calibration = stored?.calibration?.normalized ?? .identity
        calibrationPreviewEnabled = stored?.calibrationPreviewEnabled ?? true
        showInDock = stored?.showInDock ?? false
        openEditorAtLaunch = stored?.openEditorAtLaunch ?? false
        lightingSource = LightingSource(rawValue: stored?.lightingSource ?? "") ?? .effect
        // Gated like every other disk read: an isolated model (snapshots, tests) must
        // not pick up the real user's recorded labels.
        let onDisk = persistsWorkspace ? Self.storedModeLabels() : nil
        let migrated = onDisk ?? (persistsWorkspace ? (stored?.modeLabels ?? [:]) : [:])
        let needsMigration = persistsWorkspace && onDisk == nil && !migrated.isEmpty
        modeLabels = migrated.filter {
            (0...19).contains($0.key) && !kNamedModes.contains($0.key) && !$0.value.isEmpty
        }
        // The keyboard can be changed while Aula S98 Pro Companion is closed (or by the CLI), and
        // this protocol has no reliable read-current-state command. Never present a
        // previous session's values as confirmed live hardware state.
        lastAppliedLight = nil
        lastAppliedKeys = nil
        lastAppliedKeysBrightness = nil
        lastAppliedConfig = nil
        lightingBaseline = light
        keysBaseline = keys
        keysBrightnessBaseline = light.brightness

        [device.objectWillChange.eraseToAnyPublisher(),
         presets.objectWillChange.eraseToAnyPublisher(),
         clock.objectWillChange.eraseToAnyPublisher(),
         appProfiles.objectWillChange.eraseToAnyPublisher()].forEach { publisher in
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)
        }

        // A reconnect cannot prove what survived a power cycle or a knob change.
        // Device publishers and connection notifications are delivered on main.
        device.$phase.dropFirst().sink { [weak self] phase in
            // A failed transaction can also have changed part of the hardware
            // state. A later successful clock job must not revive its old claim.
            guard phase == .disconnected || phase == .connecting || phase == .searching || phase == .failed else { return }
            MainActor.assumeIsolated { self?.invalidateConfirmedState() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .aulaDeviceConnected, object: device)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidateConfirmedState() }
            }.store(in: &cancellables)

        // Write the migrated labels out at once. Until this file exists, the store
        // meant to protect identification work does not actually protect anything.
        if needsMigration { saveModeLabels() }

        // Workspace writes are debounced by 250ms, so anything changed just before
        // Quit would otherwise never reach disk.
        if persistsWorkspace {
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.persistWork?.cancel()
                        self?.persistNow()
                    }
                }
        }

        // Seeded BEFORE onChange is wired, so restoring never writes the blob
        // straight back. No observer is installed here either: the store refuses
        // to install one until it has a model, which is start()'s job.
        appProfiles.restore(profiles: stored?.appProfiles ?? [],
                            enabled: stored?.appProfilesEnabled ?? false)
        appProfiles.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.schedulePersistence() }
        }
    }

    static func snapshot() -> AppModel {
        AppModel(device: AulaDevice(simulated: true),
                 presets: PresetStore(storageURL: nil),
                 clock: TimeSync(persistPreferences: false, enabled: false),
                 // observesWorkspace: false is belt and braces — no NSWorkspace
                 // observer can exist in a render whatever `enabled` says.
                 appProfiles: AppProfileStore(observesWorkspace: false),
                 persistsWorkspace: false)
    }

    func start() {
        guard !started else { return }
        started = true
        clock.attach(device)
        appProfiles.attach(model: self)
    }

    var currentMode: LightMode {
        kModes.first { $0.id == light.mode } ?? kModes[1]
    }

    /// Correction applied to what the app DRAWS, never to what it sends. Off while
    /// collecting data points, so you judge the keyboard against true colours.
    var calibrationIsActive: Bool { calibrationPreviewEnabled && !calibration.samples.isEmpty }

    func displayColor(_ color: RGB8) -> RGB8 {
        calibrationIsActive ? calibration.predictedAppearance(of: color) : color
    }

    /// The preview shows how the keys are expected to LOOK, not the bytes we send.
    /// Once calibration data points exist, that is the requested colour passed through
    /// the correction and back through the measured distortion — equal to what you
    /// picked when the correction fits, and visibly short of it when it cannot.
    var effectPreview: [Int: RGB8] {
        if light.mode == 0 { return [:] }
        guard currentMode.usesColor else { return Paint.rainbowHorizontal() }
        return Paint.solid(displayColor(light.color))
    }

    /// True when the keyboard visibly renders the requested colour differently.
    var previewDiffersFromRequest: Bool {
        guard currentMode.usesColor, calibrationIsActive else { return false }
        return displayColor(light.color) != light.color
    }

    var lightHasUnappliedChanges: Bool {
        lastAppliedLight != light
    }
    /// The keys touched by the stroke in progress. KeyCapView has drawn a 1.6pt
    /// selection stroke and KeyboardWebController has shipped kbSetHighlight since
    /// they were written, and no shipping call site had ever passed a non-empty
    /// set — so a click that landed on the wrong key looked identical to one that
    /// landed on the right key.
    /// Whether the app also appears in the Dock and the app switcher. It is a
    /// menu-bar utility by default (LSUIElement), which is unreachable if the menu
    /// bar is full — so the activation policy is switchable at runtime.
    @Published var showInDock: Bool = false {
        didSet {
            guard showInDock != oldValue else { return }
            applyActivationPolicy()
            schedulePersistence()
        }
    }

    /// Open the editor window on launch, for anyone who cannot reach the menu bar.
    @Published var openEditorAtLaunch: Bool = false {
        didSet { if openEditorAtLaunch != oldValue { schedulePersistence() } }
    }

    func applyActivationPolicy() {
        // .regular gives a Dock icon and Cmd-Tab; .accessory is the menu-bar-only
        // default. Switching to .regular has to re-activate, or the app ends up
        // frontmost-but-hidden with no window and no way back.
        let wanted: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Increments once every time a change is CONFIRMED by the keyboard.
    ///
    /// The app answers a success with light — a pulse on the board's own glow —
    /// rather than a line of text saying what you can already see. Failure keeps
    /// its words: a notice you have to read is right for something that went wrong
    /// and wrong for something that went right.
    @Published private(set) var confirmations: UInt64 = 0

    @Published private(set) var strokeKeys: Set<Int> = []
    private var strokeClearWork: DispatchWorkItem?

    var keysHaveUnappliedChanges: Bool {
        lastAppliedKeys != keys || lastAppliedKeysBrightness != light.brightness
    }
    var configHasUnappliedChanges: Bool { lastAppliedConfig != config }

    /// Changes made since the restored workspace or the last successful durable
    /// apply of this source. Unchanged startup values do not hold app profiles,
    /// but new drafts do — even before their first apply and after reconnecting.
    var hasUncommittedLightingWork: Bool {
        switch lightingSource {
        case .perKey: return keysBaseline != keys || keysBrightnessBaseline != light.brightness
        case .effect: return lightingBaseline != light
        }
    }
    /// The colour the keys are expected to show for the current selection.
    var calibratedOutputColor: RGB8 { displayColor(light.color) }

    /// Correct a whole keyboard frame for display. Used by every keyboard drawing so
    /// a painted layout on screen matches the one on the desk.
    func displayColors(_ frame: [Int: RGB8]) -> [Int: RGB8] {
        guard calibrationIsActive else { return frame }
        return frame.mapValues { calibration.predictedAppearance(of: $0) }
    }

    /// Every mode's name, unless an older build recorded a label for it by hand.
    func modeName(_ mode: LightMode) -> String { labelForMode(mode.id) }

    func labelForMode(_ mode: Int) -> String {
        Self.label(for: mode, recorded: modeLabels)
    }

    /// Labels typed into the retired Identify tab are still honoured, in the form
    /// they were meant: an effect number resolves to the manual's name, anything
    /// else is shown exactly as typed. Vendor-named modes are never relabelled.
    static func label(for mode: Int, recorded: [Int: String]) -> String {
        let official = kModes.first(where: { $0.id == mode })?.name ?? "Mode \(mode)"
        guard !kNamedModes.contains(mode), let label = recorded[mode] else { return official }
        if let number = effectNumber(in: label), let name = kManualEffectNames[number] {
            return name
        }
        return label
    }

    /// Reads an LCD effect number out of a label like "Effect 5". Returns nil for
    /// free-form text, which is then shown verbatim rather than being reinterpreted.
    private static func effectNumber(in label: String) -> Int? {
        let digits = label.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), (1...20).contains(value),
              label.lowercased().contains("effect") else { return nil }
        return value
    }

    func clearModeLabel(for mode: Int) {
        modeLabels.removeValue(forKey: mode)
    }

    func selectMode(_ mode: Int) {
        guard (0...19).contains(mode) else { return }
        light.mode = mode
        commitMode()
    }

    func updateColor(_ color: RGB8, preview: Bool) {
        light.color = color
        preview ? previewMode() : commitMode()
    }

    func updateBrightness(_ value: Int, preview: Bool, forPerKey: Bool = false) {
        light.brightness = max(0, min(5, value))
        if preview {
            if forPerKey { return }
            previewMode()
        } else if forPerKey {
            applyKeys()
        } else {
            commitMode()
        }
    }

    func updateSpeed(_ value: Int, preview: Bool) {
        light.speed = max(0, min(5, value))
        preview ? previewMode() : commitMode()
    }

    func setReverse(_ value: Bool) {
        light.reverse = value
        commitMode()
    }

    func setColorful(_ value: Bool) {
        light.colorful = value
        commitMode()
    }

    func turnLightsOff() {
        light.mode = 0
        commitMode()
    }

    func commitMode() {
        modePreviewWork?.cancel(); modePreviewWork = nil
        let state = light.normalized
        device.apply(.mode(state, persist: true)) { [weak self] result in
            if case .success = result {
                self?.lastAppliedLight = state
                self?.lightingBaseline = state
                self?.lastAppliedKeys = nil   // an effect replaces the per-key frame
                self?.lastAppliedKeysBrightness = nil
                self?.confirmations &+= 1
            }
        }
    }

    func previewMode() {
        modePreviewWork?.cancel()
        let state = light.normalized
        let work = DispatchWorkItem { [weak self] in
            self?.device.apply(.mode(state, persist: false))
        }
        modePreviewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func beginPainting() {
        if paintBaseline == nil { paintBaseline = keys }
    }

    func paintKey(_ id: Int, erase: Bool) {
        guard kLedIndices.contains(id) else { return }
        beginPainting()
        strokeClearWork?.cancel()
        strokeKeys.insert(id)
        if erase { keys.removeValue(forKey: id) }
        else { keys[id] = brush }
    }

    func endPainting() {
        // The stroke stays outlined for a beat after the mouse goes up, so the
        // confirmation is still there to read when you look up from the keyboard.
        strokeClearWork?.cancel()
        let clear = DispatchWorkItem { [weak self] in self?.strokeKeys = [] }
        strokeClearWork = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: clear)

        guard let baseline = paintBaseline else { return }
        paintBaseline = nil
        guard baseline != keys else { return }
        pushUndo(baseline)
        applyKeys()
    }

    func replaceKeys(with replacement: [Int: RGB8]) {
        strokeClearWork?.cancel()
        strokeKeys = []
        guard replacement != keys else { return }
        pushUndo(keys)
        keys = replacement.filter { Set(kLedIndices).contains($0.key) && $0.value != .black }
        applyKeys()
    }

    func undoKeys() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(keys)
        keys = previous
        updateUndoState()
        applyKeys()
    }

    func redoKeys() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(keys)
        keys = next
        updateUndoState()
        applyKeys()
    }

    func applyKeys() {
        modePreviewWork?.cancel(); modePreviewWork = nil
        let frame = keys
        let brightness = light.normalized.brightness
        device.apply(.perKey(frame, brightness: brightness, persist: true)) { [weak self] result in
            if case .success = result {
                self?.lastAppliedKeys = frame
                self?.lastAppliedKeysBrightness = brightness
                self?.keysBaseline = frame
                self?.keysBrightnessBaseline = brightness
                self?.lastAppliedLight = nil  // the per-key frame replaces the effect
                self?.confirmations &+= 1
            }
        }
    }

    func apply(_ preset: Preset) {
        light = preset.state.normalized
        if preset.isPerKey {
            pushUndo(keys)
            keys = preset.keys
            lightingSource = .perKey        // show the source the keyboard is now using
            applyKeys()
        } else {
            lightingSource = .effect
            commitMode()
        }
    }

    @discardableResult
    func savePreset(named rawName: String, perKey: Bool) -> Bool {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = perKey ? "Per-key \(presets.customCount + 1)" : "Preset \(presets.customCount + 1)"
        return presets.add(Preset(name: trimmed.isEmpty ? fallback : trimmed,
                                  isPerKey: perKey, state: light,
                                  keys: perKey ? keys : [:]))
    }

    @discardableResult
    func replace(_ preset: Preset) -> Bool {
        presets.update(preset, with: Preset(name: preset.name,
                                            isPerKey: preset.isPerKey,
                                            state: light,
                                            keys: preset.isPerKey ? keys : [:]))
    }

    func applyConfig() {
        let value = config.normalized
        device.apply(.config(value)) { [weak self] result in
            if case .success = result {
                self?.lastAppliedConfig = value
                self?.confirmations &+= 1
            }
        }
    }

    func previewCalibration(_ color: RGB8) {
        modePreviewWork?.cancel(); modePreviewWork = nil
        var test = LightState()
        test.mode = 1
        test.color = color
        test.brightness = 5
        applyCalibrationPreview(test)
    }

    func previewRawColor(_ output: RGB8) {
        modePreviewWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            var test = LightState()
            test.mode = 1
            test.color = output
            test.brightness = 5
            self?.applyCalibrationPreview(test)
        }
        modePreviewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func applyCalibrationPreview(_ state: LightState) {
        device.apply(.calibration(state)) { [weak self] result in
            if case .success = result { self?.invalidateConfirmedLighting() }
        }
    }

    private func invalidateConfirmedLighting() {
        lastAppliedLight = nil
        lastAppliedKeys = nil
        lastAppliedKeysBrightness = nil
    }

    private func invalidateConfirmedState() {
        invalidateConfirmedLighting()
        lastAppliedConfig = nil
    }

    func resetCalibration() {
        calibration = .identity
    }

    func resetConfigForm() {
        config = KeyboardConfig()
    }

    @discardableResult
    func saveColor(_ color: RGB8) -> Bool {
        guard !recentColors.contains(color), recentColors.count < 12 else { return false }
        recentColors.append(color)
        return true
    }

    func removeSavedColor(_ color: RGB8) {
        recentColors.removeAll { $0 == color }
    }

    func clearSavedColors() {
        recentColors = []
    }

    private func pushUndo(_ value: [Int: RGB8]) {
        undoStack.append(value)
        if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
        redoStack.removeAll()
        updateUndoState()
    }

    private func updateUndoState() {
        canUndoKeys = !undoStack.isEmpty
        canRedoKeys = !redoStack.isEmpty
    }

    private func schedulePersistence() {
        guard persistsWorkspace else { return }
        persistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistNow() }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func persistNow() {
        guard persistsWorkspace else { return }
        let value = StoredWorkspace(light: light.normalized, keys: keys, brush: brush,
                                    gradientStart: gradientStart, gradientEnd: gradientEnd,
                                    config: config.normalized, recentColors: recentColors,
                                    savedColorsCurated: true,
                                    calibration: calibration.normalized,
                                    calibrationPreviewEnabled: calibrationPreviewEnabled,
                                    lightingSource: lightingSource.rawValue,
                                    modeLabels: modeLabels,
                                    showInDock: showInDock,
                                    openEditorAtLaunch: openEditorAtLaunch,
                                    appProfiles: appProfiles.profiles,
                                    appProfilesEnabled: appProfiles.enabled)
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: Self.workspaceKey)
    }

    static let defaultSwatches: [RGB8] = [
        RGB8(r: 255, g: 59, b: 48), RGB8(r: 255, g: 149, b: 0),
        RGB8(r: 255, g: 204, b: 0), RGB8(r: 52, g: 199, b: 89),
        RGB8(r: 0, g: 199, b: 190), RGB8(r: 50, g: 173, b: 230),
        RGB8(r: 0, g: 122, b: 255), RGB8(r: 88, g: 86, b: 214),
        RGB8(r: 175, g: 82, b: 222), RGB8(r: 255, g: 45, b: 85),
    ]
}
