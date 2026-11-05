import Foundation

/// Exercises real state transitions against an injected transport, never HID,
/// NSWorkspace activation or the user's preferences and preset files.
@MainActor
enum StateRegressionTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Job] = []
        func record(_ job: Job) { lock.lock(); recorded.append(job); lock.unlock() }
        var jobs: [Job] { lock.lock(); defer { lock.unlock() }; return recorded }
    }

    private static func model(recording recorder: Recorder) -> AppModel {
        let device = AulaDevice(simulated: true, simulatedExecutor: { job in
            recorder.record(job)
            return .success("Isolated state test accepted job")
        })
        return AppModel(device: device, presets: PresetStore(storageURL: nil),
                        clock: TimeSync(persistPreferences: false, enabled: false),
                        appProfiles: AppProfileStore(observesWorkspace: false),
                        persistsWorkspace: false)
    }

    @discardableResult
    private static func wait(until condition: () -> Bool, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return condition()
    }

    private static func pump(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.005)))
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        testAppliedBrightnessAndProfiles(expect)
        testCalibrationRestoreOrdering(expect)
        testConfirmationInvalidation(expect)
        testDraftProtectionAcrossInvalidation(expect)
        testFailureCannotReviveConfirmation(expect)
        testModeLabelCollisionsAndProfileRestore(expect)
        testPresetRoundTripAndSchemaProtection(expect)
    }

    private static func testAppliedBrightnessAndProfiles(_ expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let model = model(recording: recorder)
        let frame = [kLedIndices[0]: RGB8(r: 255, g: 0, b: 0)]
        model.lightingSource = .perKey
        model.keys = frame
        model.light.brightness = 2
        model.applyKeys()
        expect(wait { model.lastAppliedKeys == frame && model.lastAppliedKeysBrightness == 2 },
               "per-key confirmation records the brightness actually sent")
        expect(!model.keysHaveUnappliedChanges, "an unchanged confirmed per-key output is clean")
        model.updateBrightness(4, preview: true, forPerKey: true)
        expect(model.keysHaveUnappliedChanges && model.hasUncommittedLightingWork,
               "brightness-only per-key edits are dirty and protected as unapplied work")

        var brighter = LightState(); brighter.brightness = 5
        expect(model.presets.add(Preset(name: "Brighter", isPerKey: true, state: brighter, keys: frame)),
               "per-key profile fixture saves into an isolated store")
        guard let preset = model.presets.userPresets.first else { return }
        model.appProfiles.attach(model: model)
        model.appProfiles.bind(bundleID: "test.state.app", appName: "State test", to: preset)
        model.appProfiles.enabled = true
        let confirmations = model.confirmations
        model.appProfiles.applyProfileForTesting(bundleID: "test.state.app", appName: "State test")
        expect(wait { model.lastAppliedKeysBrightness == 5 },
               "a profile with identical keys but different brightness is applied")
        expect(model.confirmations == confirmations + 1,
               "the different-brightness profile is not falsely skipped as already applied")
        let jobCount = recorder.jobs.count
        model.appProfiles.applyProfileForTesting(bundleID: "test.state.app", appName: "State test")
        pump(for: 0.025)
        expect(recorder.jobs.count == jobCount && model.appProfiles.lastEvent.contains("already on the keyboard"),
               "an exactly matching per-key profile still skips redundant uploads")
    }

    private static func testCalibrationRestoreOrdering(_ expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let model = model(recording: recorder)
        let red = RGB8(r: 255, g: 0, b: 0)
        let frame = [kLedIndices[0]: red]
        model.lightingSource = .perKey
        model.keys = frame
        model.previewRawColor(RGB8(r: 0, g: 0, b: 255))
        model.applyKeys()
        expect(wait { model.lastAppliedKeys == frame }, "calibration close restores the per-key frame")
        pump(for: 0.2)
        let jobs = recorder.jobs
        expect(jobs.count == 1, "closing per-key calibration cancels its delayed raw-colour probe")
        if let last = jobs.last, case .perKey(let colors, _, let persist) = last {
            expect(colors == frame && persist, "the restored per-key output is the final durable job")
        } else {
            expect(false, "a calibration probe must not override the restored per-key frame")
        }

        model.light.color = red
        model.previewRawColor(RGB8(r: 0, g: 255, b: 0))
        model.commitMode()
        expect(wait { model.lastAppliedLight?.color == red }, "effect calibration close restores its effect")
        pump(for: 0.2)
        expect(recorder.jobs.count == 2, "effect restore also cancels the delayed calibration probe")
    }

    private static func testConfirmationInvalidation(_ expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let model = model(recording: recorder)
        model.applyConfig()
        expect(wait { model.lastAppliedConfig != nil }, "settings fixture is confirmed")
        model.commitMode()
        expect(wait { model.lastAppliedLight != nil }, "effect fixture is confirmed")
        model.previewCalibration(RGB8(r: 0, g: 0, b: 255))
        expect(wait { model.lastAppliedLight == nil },
               "a successful temporary calibration colour invalidates the previous lighting claim")
        expect(model.lastAppliedConfig != nil,
               "a colour probe does not invalidate unrelated keyboard settings")

        model.keys = [kLedIndices[0]: RGB8(r: 1, g: 2, b: 3)]
        model.applyKeys()
        expect(wait { model.lastAppliedKeys != nil }, "per-key fixture is confirmed before reconnect")
        NotificationCenter.default.post(name: .aulaDeviceConnected, object: model.device)
        expect(model.lastAppliedLight == nil && model.lastAppliedKeys == nil
               && model.lastAppliedKeysBrightness == nil && model.lastAppliedConfig == nil,
               "reconnecting invalidates lighting and settings that hardware may have changed")
        expect(model.keys.count == 1 && model.light.mode == 1,
               "reconnecting preserves the user's staged workspace")
    }

    private static func testModeLabelCollisionsAndProfileRestore(_ expect: (Bool, String) -> Void) {
        let collision = Data("{\"15\":\"Canonical\",\"015\":\"Alias\",\"+15\":\"Signed\",\"bad\":\"Invalid\"}".utf8)
        expect(AppModel.decodeModeLabels(collision) == [15: "Canonical"],
               "noncanonical mode-label keys cannot collide or trap after integer conversion")
        expect(AppModel.decodeModeLabels(Data("not json".utf8)) == nil,
               "unreadable mode labels are rejected without a crash")
        let store = AppProfileStore(observesWorkspace: false)
        let preset = PresetStore.builtIns[0]
        let first = AppProfile(bundleID: "test.duplicate", presetID: preset.id,
                               appName: "First", presetName: preset.name)
        let duplicate = AppProfile(bundleID: first.bundleID, presetID: UUID(),
                                   appName: "Duplicate", presetName: "Other")
        let invalid = AppProfile(bundleID: "", presetID: preset.id,
                                 appName: "Empty", presetName: preset.name)
        store.restore(profiles: [first, duplicate, invalid], enabled: false)
        expect(store.profiles == [first], "restoring profiles filters duplicate and empty persisted IDs")
    }

    private static func testDraftProtectionAcrossInvalidation(_ expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let model = model(recording: recorder)
        expect(!model.hasUncommittedLightingWork, "unchanged startup workspace does not hold automatic profiles")
        model.light.color = RGB8(r: 255, g: 0, b: 0)
        expect(model.hasUncommittedLightingWork, "new effect edits are protected before the first apply")
        model.lightingSource = .perKey
        expect(!model.hasUncommittedLightingWork, "a draft in the other source does not block an unchanged source")
        model.keys = [kLedIndices[0]: RGB8(r: 1, g: 2, b: 3)]
        expect(model.hasUncommittedLightingWork, "new per-key edits are protected before the first apply")
        model.applyKeys()
        expect(wait { model.lastAppliedKeys != nil }, "a durable per-key apply establishes the draft baseline")
        expect(!model.hasUncommittedLightingWork, "successful durable per-key apply clears only its draft")
        model.updateBrightness(4, preview: true, forPerKey: true)
        NotificationCenter.default.post(name: .aulaDeviceConnected, object: model.device)
        expect(model.lastAppliedKeys == nil && model.hasUncommittedLightingWork,
               "reconnect clears hardware confirmation without erasing brightness-draft protection")
        let beforeProbe = recorder.jobs.count
        model.previewCalibration(RGB8(r: 0, g: 0, b: 255))
        expect(wait { recorder.jobs.count == beforeProbe + 1 }, "isolated calibration probe executes")
        pump(for: 0.025)
        expect(model.device.phase == .ready, "isolated calibration probe completes")
        expect(model.hasUncommittedLightingWork, "calibration cannot make the per-key draft look committed")
        model.applyKeys()
        expect(wait { model.lastAppliedKeysBrightness == 4 }, "the brightness draft can be durably applied")
        expect(!model.hasUncommittedLightingWork, "durable apply clears the brightness draft after reconnect")
        model.lightingSource = .effect
        expect(model.hasUncommittedLightingWork, "switching back preserves the uncommitted effect draft")
        model.commitMode()
        expect(wait { model.lastAppliedLight != nil }, "the effect draft can be durably applied")
        expect(!model.hasUncommittedLightingWork, "durable effect apply clears its draft")
        model.lightingSource = .perKey
        expect(!model.hasUncommittedLightingWork, "effect application does not corrupt the per-key draft baseline")
        model.lightingSource = .effect
        model.light.brightness = 1
        model.commitMode()
        expect(wait { model.lastAppliedLight?.brightness == 1 }, "shared-brightness fixture applies to its effect")
        model.lightingSource = .perKey
        expect(model.hasUncommittedLightingWork,
               "shared brightness remains an unapplied per-key change until that source is committed")
    }

    private static func testFailureCannotReviveConfirmation(_ expect: (Bool, String) -> Void) {
        let red = RGB8(r: 255, g: 0, b: 0)
        let green = RGB8(r: 0, g: 255, b: 0)
        let device = AulaDevice(simulated: true, simulatedExecutor: { job in
            if case .mode(let state, _) = job, state.color == green {
                return .failure(.transport("Isolated partial lighting failure"))
            }
            return .success("Isolated state test accepted job")
        })
        let model = AppModel(device: device, presets: PresetStore(storageURL: nil),
                             clock: TimeSync(persistPreferences: false, enabled: false),
                             appProfiles: AppProfileStore(observesWorkspace: false),
                             persistsWorkspace: false)
        model.applyConfig()
        expect(wait { model.lastAppliedConfig != nil }, "settings fixture applies before a transport failure")
        model.light.color = red
        model.commitMode()
        expect(wait { model.lastAppliedLight?.color == red }, "lighting fixture applies before a transport failure")
        model.light.color = green
        model.commitMode()
        expect(wait { model.device.phase == .failed }, "the injected lighting failure is surfaced")
        expect(model.lastAppliedLight == nil && model.lastAppliedConfig == nil,
               "a partial transport failure invalidates old hardware confirmations")
        expect(model.hasUncommittedLightingWork, "the failed lighting draft remains protected")
        device.apply(.time(Date(timeIntervalSince1970: 1_700_000_000)))
        expect(wait { device.phase == .ready }, "a later clock job may recover the ready connection phase")
        expect(model.lastAppliedLight == nil && model.lightHasUnappliedChanges,
               "clock success cannot revive the stale Applied-to-keyboard lighting claim")
    }

    private static func testPresetRoundTripAndSchemaProtection(_ expect: (Bool, String) -> Void) {
        let source = PresetStore(storageURL: nil)
        var amber = LightState(); amber.color = RGB8(r: 255, g: 110, b: 0)
        expect(source.add(Preset(name: "Warm Amber", state: amber)),
               "a custom preset may deliberately match a built-in name and colour")
        guard let exported = source.exportJSON() else {
            expect(false, "custom preset fixture exports"); return
        }
        let destination = PresetStore(storageURL: nil)
        switch destination.importJSON(exported) {
        case .success(let count):
            expect(count == 1 && destination.userPresets.first?.name == "Warm Amber",
                   "versioned custom exports retain legitimate presets matching old built-in signatures")
        case .failure:
            expect(false, "the app's own valid custom export must round-trip")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AulaCompanion-state-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var object = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            object["schemaVersion"] = 999
            object["futureField"] = ["retain": true]
            let future = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let file = directory.appendingPathComponent("future.json")
            try future.write(to: file)
            let protected = PresetStore(storageURL: file)
            expect(protected.isReadOnly && protected.lastError?.contains("read-only") == true,
                   "an unsupported future preset schema surfaces a read-only warning")
            expect(try Data(contentsOf: file) == future, "loading future presets preserves every original byte")
            guard let preset = protected.userPresets.first else {
                expect(false, "known fields in future presets remain readable"); return
            }
            expect(!protected.add(Preset(name: "Must not save")), "future-schema stores reject adding presets")
            expect(!protected.delete(preset), "future-schema stores reject deleting presets")
            expect(!protected.rename(preset, to: "Must not rename"), "future-schema stores reject renaming presets")
            expect(!protected.update(preset, with: Preset(name: "Must not replace")),
                   "future-schema stores reject replacing presets")
            if case .failure(.unsupportedSchema(999)) = protected.importJSON(exported) {
                expect(true, "future-schema stores reject imports without modifying the original")
            } else {
                expect(false, "import must respect the future-schema read-only guard")
            }
            expect(try Data(contentsOf: file) == future && protected.userPresets.count == 1
                   && protected.userPresets.first?.name == "Warm Amber",
                   "attempted mutations leave future presets unchanged on disk and in memory")
            expect(protected.exportJSON() == future, "future-schema exports preserve unknown fields losslessly")
            if case .failure(.unsupportedSchema(999)) = destination.importJSON(future) {
                expect(destination.userPresets.count == 1, "unsupported future imports preserve existing presets")
            } else {
                expect(false, "unsupported future imports must report their schema version")
            }

            let incompatible = Data("{\"schemaVersion\":999,\"presets\":[{\"futureShape\":true}],\"unknown\":42}".utf8)
            let incompatibleFile = directory.appendingPathComponent("future-shape.json")
            try incompatible.write(to: incompatibleFile)
            let unknownShape = PresetStore(storageURL: incompatibleFile)
            let addedToUnknownShape = unknownShape.add(Preset(name: "Blocked"))
            let afterUnknownShape = try Data(contentsOf: incompatibleFile)
            expect(unknownShape.isReadOnly && !addedToUnknownShape && afterUnknownShape == incompatible,
                   "future schema protection also covers preset shapes the current decoder cannot understand")
        } catch {
            expect(false, "preset schema regression fixture failed: \(error)")
        }
    }
}
