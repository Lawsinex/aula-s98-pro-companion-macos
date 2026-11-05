import Foundation

@main
@MainActor
struct AulaLogicTests {
    private static var failures = 0

    static func main() {
        testRGB()
        testColorWheelMath()
        testColorCalibration()
        testKeyboardEffectNames()
        testUserLightingModeSurvives()
        testPacketCodec()
        testPaintAndLayout()
        testPresetMigrationAndImport()
        testSnapshotIsolation()
        testLiveLight()
        testAppProfiles()
        ColourCommitRegressionTests.run { expect($0, $1) }
        WheelArtworkRegressionTests.run { expect($0, $1) }
        BackendRegressionTests.run { expect($0, $1) }
        StateRegressionTests.run { expect($0, $1) }
        UIAccessibilityRegressionTests.run { expect($0, $1) }
        LegacyDataMigrationTests.run { expect($0, $1) }

        if failures == 0 {
            print("AulaLogicTests: all checks passed")
        } else {
            fputs("AulaLogicTests: \(failures) check(s) failed\n", stderr)
            exit(1)
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }

/// The three rules in InkLight.swift, asserted rather than commented.
    private static func testLiveLight() {
        // Rule 3, tied to scripts/groundaudit.py's CORNER_TOLERANCE. If either
        // number is ever changed alone, this fails instead of the gate failing
        // mysteriously on one render in ten.
        expect(Int(InkGrain.maxByte) <= 6,
               "grain amplitude stays inside groundaudit's corner tolerance of 6/255")
        expect(InkGrain.tile != nil, "the grain tile is generated")

        // Rule 2. Pure blue is at HSV value 1 already, so a value floor cannot move
        // it; only the luminance floor can.
        let blue = RGB8(r: 0, g: 0, b: 255)
        expect(blue.relativeLuminance < LiveTint.luminanceFloor,
               "pure blue really is below the floor — the test is testing something")
        let lifted = LiveTint.raised(blue, to: LiveTint.luminanceFloor)
        expect(lifted.relativeLuminance >= LiveTint.luminanceFloor,
               "raised blue clears the luminance floor")
        expect(lifted.b > lifted.r && lifted.b > lifted.g,
               "raised blue is still recognisably blue")
        expect(LiveTint.raised(lifted, to: LiveTint.luminanceFloor) == lifted,
               "raising is idempotent, so a tint cannot creep toward white")

        // Determinism: the same frame must give the same answer every time, and the
        // reduction must not depend on Dictionary iteration order.
        let solid = Paint.solid(RGB8(r: 0, g: 255, b: 0))
        expect(LiveTint(frame: solid, brightness: 5) == LiveTint(frame: solid, brightness: 5),
               "the frame reduction is stable across calls")
        expect(LiveTint(frame: solid, brightness: 5).isLit,
               "a solid green frame lends its hue")

        // Degradation. Neither of these may produce an invisible ring.
        expect(!LiveTint(frame: [:], brightness: 5).isLit,
               "an unlit board degrades to the accent rather than to a colour")
        expect(!LiveTint(frame: Paint.rainbowHorizontal(), brightness: 5).isLit,
               "a rainbow has no dominant hue and must not invent one")
        expect(!LiveTint(single: RGB8(r: 6, g: 6, b: 7), brightness: 5).isLit,
               "a near-black colour lends nothing")
        expect(LiveTint.dormant.lift == 0,
               "a dark board throws no bloom")
    }

    private static func testRGB() {
        expect(RGB8(hex: "#00ff7F") == RGB8(r: 0, g: 255, b: 127), "hex parses with #")
        expect(RGB8(hex: "A1B2C3")?.hex == "#A1B2C3", "hex round-trips")
        expect(RGB8(hex: "12345") == nil, "short hex is rejected")
        expect(RGB8(hex: "GG0000") == nil, "non-hex input is rejected")
    }

    private static func testColorWheelMath() {
        let side = 200.0
        let right = ColorWheelMath.components(at: CGPoint(x: 200, y: 100),
                                              side: side, currentHue: 0.4)
        let top = ColorWheelMath.components(at: CGPoint(x: 100, y: 0),
                                            side: side, currentHue: 0.4)
        let left = ColorWheelMath.components(at: CGPoint(x: 0, y: 100),
                                             side: side, currentHue: 0.4)
        let bottom = ColorWheelMath.components(at: CGPoint(x: 100, y: 200),
                                               side: side, currentHue: 0.4)
        expect(abs(right.hue - 0) < 0.0001 && abs(right.saturation - 1) < 0.0001,
               "colour wheel right edge is red")
        expect(abs(top.hue - 0.25) < 0.0001, "colour wheel top has quarter-turn hue")
        expect(abs(left.hue - 0.5) < 0.0001, "colour wheel left has half-turn hue")
        expect(abs(bottom.hue - 0.75) < 0.0001, "colour wheel bottom has three-quarter hue")
        let center = ColorWheelMath.components(at: CGPoint(x: 100, y: 100),
                                               side: side, currentHue: 0.42)
        expect(abs(center.hue - 0.42) < 0.0001 && center.saturation == 0,
               "colour wheel center preserves hue and removes saturation")
        expect(HSVColorMath.rgb(h: 0, s: 1, v: 1) == RGB8(r: 255, g: 0, b: 0),
               "wheel HSV red is exact sRGB")
        expect(HSVColorMath.rgb(h: 1.0 / 3, s: 1, v: 1) == RGB8(r: 0, g: 255, b: 0),
               "wheel HSV green is exact sRGB")
        expect(HSVColorMath.rgb(h: 2.0 / 3, s: 1, v: 1) == RGB8(r: 0, g: 0, b: 255),
               "wheel HSV blue is exact sRGB")
    }

    /// The single invariant that makes a durable per-key save actually display: the
    /// 0x80 user-lighting mode must survive normalisation and reach byte 0 of the
    /// light record. If normalized ever clamps it to 1, the frame uploads and the
    /// keyboard shows an ordinary effect instead.
    private static func testUserLightingModeSurvives() {
        var state = LightState()
        state.mode = Proto.userLightMode
        expect(state.normalized.mode == Proto.userLightMode,
               "0x80 user-lighting mode is not clamped away by normalisation")
        expect(LightState().withMode(Proto.userLightMode).normalized.mode == Proto.userLightMode,
               "withMode(0x80) survives normalisation")
        let record = AulaProtocolCodec.lightRecord(mode: Proto.userLightMode,
                                                   state: state.normalized)
        expect(record.count == Proto.packet, "the light record is one full packet")
        expect(record[0] == UInt8(Proto.userLightMode),
               "0x80 reaches byte 0 of the light record")
        var ordinary = LightState(); ordinary.mode = 99
        expect(ordinary.normalized.mode == 1,
               "an out-of-range mode still falls back to Static On")
    }

    private static func testKeyboardEffectNames() {
        expect(keyboardEffectName(for: 15) == "Ripple diffusion",
               "a mode AULA never named reports the manual's real effect name")
        expect(keyboardEffectNumber(for: 15) == 5,
               "the recorded LCD effect number is preserved alongside the name")
        expect(kManualEffectNames.count == 20,
               "the manual lists twenty effects")

        // The ordering is only sound if the recorded numbers and the named modes
        // partition all twenty effects exactly once.
        let unnamedEffects = Set(kKeyboardEffects.values)
        let namedEffects = Set(kNamedModeEffects.values)
        expect(unnamedEffects.isDisjoint(with: namedEffects),
               "no effect number is claimed by both a named and an unnamed mode")
        expect(unnamedEffects.union(namedEffects) == Set(1...20),
               "the two sets together account for every one of the twenty effects")
        expect(kNamedModeEffects.count == kNamedModes.count,
               "every mode AULA names has a recorded effect number")
        expect(keyboardEffectName(for: 1) == nil,
               "modes AULA names carry no recorded effect number")
        let unnamed = kModes.map(\.id).filter { !kNamedModes.contains($0) }
        expect(unnamed.allSatisfy { kKeyboardEffects[$0] != nil },
               "every mode AULA leaves unnamed has a recorded keyboard effect")
        let recorded = Set(kKeyboardEffects.values)
        expect(recorded.count == unnamed.count,
               "no two modes claim the same keyboard effect number")
        expect(recorded.allSatisfy { (1...20).contains($0) },
               "recorded effect numbers stay within the keyboard's 20 effects")
        expect(unnamed.allSatisfy { mode in
                   kModes.first { $0.id == mode }?.name == keyboardEffectName(for: mode)
               },
               "every unnamed mode is listed under the manual's name its LCD number resolves to")
        expect(!kModes.contains { $0.name.hasPrefix("Mode ") },
               "no mode is left with a placeholder name")

        // The CLI carries its own copy of the table. Read it out of the C source
        // so the two can never disagree about what a mode is called or does.
        let cSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("src/aula-s98.c")
        if let text = try? String(contentsOf: cSource, encoding: .utf8),
           let pattern = try? NSRegularExpression(
               pattern: #"\{(\d+),\s*"([^"]+)",\s*(\d),\s*(\d)\}"#) {
            let range = NSRange(text.startIndex..., in: text)
            let cModes = pattern.matches(in: text, range: range).compactMap { match -> LightMode? in
                func group(_ i: Int) -> String { String(text[Range(match.range(at: i), in: text)!]) }
                guard let id = Int(group(1)) else { return nil }
                return LightMode(id: id, name: group(2),
                                 animated: group(3) == "1", usesColor: group(4) == "1")
            }
            expect(cModes == kModes,
                   "the CLI's mode table in aula-s98.c matches kModes name for name and flag for flag")
        } else {
            expect(false, "could not read src/aula-s98.c to compare the CLI's mode table")
        }
    }

    private static func testColorCalibration() {
        let source = RGB8(r: 1, g: 2, b: 3)
        expect(ColorCalibration.identity.transform(source) == source,
               "identity calibration is byte-exact")

        var plus120 = ColorCalibration.identity; plus120.hueShiftDegrees = 120
        var minus120 = ColorCalibration.identity; minus120.hueShiftDegrees = -120
        expect(plus120.transform(RGB8(r: 255, g: 0, b: 0)) == RGB8(r: 0, g: 255, b: 0),
               "+120 degree hue rotation maps red to green")
        expect(minus120.transform(RGB8(r: 255, g: 0, b: 0)) == RGB8(r: 0, g: 0, b: 255),
               "-120 degree hue rotation maps red to blue")
        expect(plus120.transform(RGB8(r: 90, g: 90, b: 90)) == RGB8(r: 90, g: 90, b: 90),
               "hue correction leaves grayscale unchanged")

        var boosted = ColorCalibration.identity
        boosted.valueScale = 3
        expect(boosted.transform(RGB8(r: 200, g: 100, b: 50)) == RGB8(r: 255, g: 128, b: 64),
               "an over-range brightness scale clamps at full value without shifting hue")
        expect(boosted.transform(.black) == .black, "calibration keeps black invariant")

        var malformed = ColorCalibration.identity
        malformed.hueShiftDegrees = .nan; malformed.valueScale = .infinity
        expect(malformed.normalized.hueShiftDegrees == 0 && malformed.normalized.valueScale == 1,
               "non-finite calibration falls back to identity instead of propagating")
        expect(malformed.transform(.black) == .black,
               "a malformed calibration still cannot light black")

        // A sample says "I asked for red and saw dim green", i.e. the hardware shifted
        // hue +120 degrees and halved brightness. The correction must INVERT that.
        var visual = ColorCalibration.identity
        visual.addSample(target: RGB8(r: 255, g: 0, b: 0), observed: RGB8(r: 0, g: 128, b: 0))
        expect(visual.samples.count == 1, "an observation is recorded as a data point")
        expect(visual.hueShiftDegrees > 100 && visual.hueShiftDegrees < 140,
               "a measured +120 degree hue shift is stored as it was observed")
        expect(visual.valueScale > 0.4 && visual.valueScale < 0.6,
               "a measured halving of brightness is stored as it was observed")
        expect(visual.predictedAppearance(of: RGB8(r: 255, g: 0, b: 0)) == RGB8(r: 0, g: 128, b: 0),
               "the display predicts exactly the colour that was observed")

        // Hue deltas either side of the red wrap-around must average circularly
        // rather than cancelling to zero.
        var wrapped = ColorCalibration.identity
        wrapped.addSample(target: RGB8(r: 255, g: 0, b: 0), observed: RGB8(r: 255, g: 60, b: 0))
        wrapped.addSample(target: RGB8(r: 255, g: 0, b: 0), observed: RGB8(r: 255, g: 0, b: 60))
        expect(abs(wrapped.hueShiftDegrees) < 20,
               "opposing hue errors average out instead of wrapping to 180 degrees")

        // The cap must reject rather than accept-then-discard: a correction derived
        // from a sample that was not kept would shift colours on the next unrelated edit.
        var capped = ColorCalibration.identity
        for index in 0..<ColorCalibration.maximumSamples {
            let shade = UInt8(index % 200)
            expect(capped.addSample(target: RGB8(r: shade, g: 10, b: 10),
                                    observed: RGB8(r: shade, g: 20, b: 20)),
                   "samples below the cap are accepted")
        }
        expect(capped.samples.count == ColorCalibration.maximumSamples,
               "the cap is reached exactly")
        let beforeOverflow = capped
        expect(!capped.addSample(target: RGB8(r: 255, g: 255, b: 255), observed: .black),
               "a sample past the cap is refused rather than silently dropped")
        expect(capped == beforeOverflow,
               "a refused sample leaves the correction untouched")

        var removable = visual
        removable.removeSample(id: removable.samples[0].id)
        expect(removable.samples.isEmpty && removable.hueShiftDegrees == 0
               && removable.saturationScale == 1 && removable.valueScale == 1,
               "deleting the last data point returns the wheel to uncorrected")

        // The preview must show what the keys will LOOK like, not the bytes sent.
        var preview = ColorCalibration.identity
        expect(preview.predictedAppearance(of: RGB8(r: 10, g: 20, b: 30)) == RGB8(r: 10, g: 20, b: 30),
               "with no data points the preview is the requested colour untouched")
        preview.addSample(target: RGB8(r: 0, g: 200, b: 255), observed: RGB8(r: 0, g: 150, b: 255))
        let shown = preview.predictedAppearance(of: RGB8(r: 0, g: 200, b: 255))
        func close(_ a: UInt8, _ b: UInt8) -> Bool { abs(Int(a) - Int(b)) <= 14 }
        expect(close(shown.r, 0) && close(shown.g, 150) && close(shown.b, 255),
               "the preview reproduces what was actually observed on the keys")

        let legacyJSON = Data("""
        {"channelOrder":"RGB","hueShiftDegrees":10,"redBalance":1,
         "greenBalance":1,"blueBalance":1}
        """.utf8)
        if let migrated = try? JSONDecoder().decode(ColorCalibration.self, from: legacyJSON) {
            expect(migrated.saturationScale == 1 && migrated.valueScale == 1
                   && migrated.hueShiftDegrees == 10,
                   "older calibration data still decodes, ignoring the retired channel fields")
        } else {
            expect(false, "older calibration data should decode")
        }
    }

    private static func testPacketCodec() {
        let begin = AulaProtocolCodec.command(Proto.opBegin)
        expect(begin.count == 64 && begin[0] == 0x04 && begin[1] == 0x18,
               "BEGIN packet has the expected envelope")

        var state = LightState()
        state.mode = 7; state.color = RGB8(r: 1, g: 2, b: 3)
        state.brightness = 99; state.speed = -2; state.colorful = true; state.reverse = true
        let light = AulaProtocolCodec.lightRecord(mode: state.mode, state: state)
        expect(light.count == 64, "lighting record is exactly one feature report")
        expect(Array(light[0...3]) == [7, 1, 2, 3], "lighting mode and RGB bytes are exact")
        expect(light[8] == 1 && light[9] == 5 && light[10] == 0 && light[11] == 1,
               "lighting flags and numeric values are normalized")
        expect(light[14] == 0xAA && light[15] == 0x55, "lighting terminator is present")

        let frame = AulaProtocolCodec.perKeyFrame([1: RGB8(r: 9, g: 8, b: 7),
                                                    123: RGB8(r: 6, g: 5, b: 4),
                                                    999: RGB8(r: 1, g: 1, b: 1)])
        expect(frame.count == 576, "per-key frame has nine 64-byte chunks")
        expect(Array(frame[4...7]) == [1, 9, 8, 7], "first LED record is correctly addressed")
        expect(Array(frame[492...495]) == [123, 6, 5, 4], "last LED record is correctly addressed")
        expect(frame[574] == 0xAA && frame[575] == 0x55, "per-key terminator is present")

        var config = KeyboardConfig()
        config.disableWin = true; config.disableAltTab = true
        config.sleepMinutes = 200; config.keyResponseMs = -1
        let configPacket = AulaProtocolCodec.configRecord(config)
        expect(configPacket[2] == 1 && configPacket[3] == 0 && configPacket[4] == 1,
               "config flags are encoded")
        expect(configPacket[5] == 60 && configPacket[6] == 0,
               "config numeric values are normalized")
        expect(configPacket[62] == 0xAA && configPacket[63] == 0x55,
               "config terminator is present")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                        year: 2026, month: 8, day: 27,
                                        hour: 12, minute: 34, second: 56)
        let time = AulaProtocolCodec.timeRecord(components.date!, calendar: calendar)!
        expect(Array(time[2...8]) == [0x5A, 26, 8, 27, 12, 34, 56],
               "clock date and time bytes are exact")
        expect(time[10] == 4, "clock weekday uses Sunday=0")
    }

    private static func testPaintAndLayout() {
        expect(kKeyCaps.count == Set(kLedIndices).count, "keyboard LED ids are unique")
        expect(kKeyCaps.allSatisfy { (1...Proto.maxLED).contains($0.id) },
               "keyboard LED ids fit the wire protocol")
        expect(Paint.solid(RGB8(r: 2, g: 3, b: 4)).count == kKeyCaps.count,
               "solid fill covers every rendered key")
        let rainbow = Paint.rainbowHorizontal()
        expect(rainbow.count == kKeyCaps.count && Set(rainbow.values).count > 20,
               "rainbow fill covers the layout with varied colours")
        let gradient = Paint.gradient(.black, RGB8(r: 255, g: 255, b: 255))
        let left = gradient[kKeyCaps.min(by: { $0.x < $1.x })!.id]!
        let right = gradient[kKeyCaps.max(by: { $0.x < $1.x })!.id]!
        expect(left.r < right.r, "gradient progresses from left to right")
    }

    private static func testPresetMigrationAndImport() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AulaCompanion-tests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("presets.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            var legacyBuiltIn = LightState()
            legacyBuiltIn.mode = 4; legacyBuiltIn.color = RGB8(r: 0, g: 220, b: 255)
            var userState = LightState()
            userState.mode = 12; userState.color = RGB8(r: 20, g: 30, b: 40)
            let legacy = [
                Preset(name: "Cyan Breathe", state: legacyBuiltIn),
                Preset(name: "My desk", state: userState),
            ]
            let encoder = JSONEncoder()
            try encoder.encode(legacy).write(to: file)

            let store = PresetStore(storageURL: file)
            expect(store.userPresets.count == 1 && store.userPresets.first?.name == "My desk",
                   "legacy built-ins are removed without losing user presets")
            expect(PresetStore.builtIns.first(where: { $0.name == "Cyan Breathe" })?.state.mode == 7,
                   "corrected built-in effect mapping is authoritative")

            let exported = store.exportJSON()!
            let second = PresetStore(storageURL: nil)
            if case .success(let count) = second.importJSON(exported) {
                expect(count == 1 && second.userPresets.first?.name == "My desk",
                       "versioned export imports cleanly")
            } else {
                expect(false, "versioned export should import")
            }
            if case .failure = second.importJSON(Data("not json".utf8)) {
                expect(true, "invalid imports return a visible error")
            } else {
                expect(false, "invalid imports must fail")
            }

            let unwritable = PresetStore(storageURL: directory)
            let added = unwritable.add(Preset(name: "Must roll back", state: userState))
            expect(!added && unwritable.userPresets.isEmpty,
                   "failed preset writes roll back the in-memory mutation")
        } catch {
            expect(false, "preset migration fixture failed: \(error)")
        }
    }

    private static func testAppProfiles() {
        // observesWorkspace: false — a unit test must never install a real
        // NSWorkspace observer, exactly as it never touches the real clock prefs.
        let store = AppProfileStore(observesWorkspace: false)
        let presets = PresetStore(storageURL: nil)
        let mine = Preset(name: "Cold", state: LightState())
        expect(presets.add(mine), "a preset can be saved into an isolated store")
        guard let saved = presets.userPresets.first else {
            expect(false, "the saved preset is readable back"); return
        }

        store.bind(bundleID: "com.apple.Terminal", appName: "Terminal", to: saved)
        expect(store.profiles.count == 1, "binding an app adds one row")
        store.bind(bundleID: "com.apple.Terminal", appName: "Terminal",
                   to: PresetStore.builtIns[0])
        expect(store.profiles.count == 1, "re-binding the same app replaces, never duplicates")

        store.bind(bundleID: "com.apple.dt.Xcode", appName: "Xcode", to: saved)
        expect(presets.rename(saved, to: "Colder"), "the bound preset can be renamed")
        expect(store.resolvedPreset(for: "com.apple.dt.Xcode", in: presets.presets)?.name == "Colder",
               "a binding follows a rename, because it resolves by id and not by name")

        expect(presets.delete(saved), "the bound preset can be deleted")
        expect(store.resolvedPreset(for: "com.apple.dt.Xcode", in: presets.presets) == nil,
               "a deleted preset resolves to nothing rather than to a ghost")
        expect(store.profiles.contains { $0.bundleID == "com.apple.dt.Xcode" },
               "the row survives the deletion so the user can see and re-point it")

        // A preset that reuses the deleted one's NAME must not inherit its binding.
        expect(presets.add(Preset(name: "Colder", state: LightState())),
               "a new preset can reuse the deleted name")
        expect(store.resolvedPreset(for: "com.apple.dt.Xcode", in: presets.presets) == nil,
               "reusing a deleted preset's name does not resurrect its binding")

        store.bind(bundleID: AppProfile.everythingElse, appName: "Everything else",
                   to: PresetStore.builtIns[1])
        expect(store.resolvedPreset(for: "com.unbound.app", in: presets.presets)?.id
               == PresetStore.builtIns[1].id,
               "an app with no binding of its own falls back to the catch-all")
        expect(store.resolvedPreset(for: "com.apple.dt.Xcode", in: presets.presets) == nil,
               "a broken exact binding is NOT quietly answered by the catch-all")
        expect(store.profiles.last?.isCatchAll == true,
               "the catch-all always sorts last")

        // Per-process hash seeding would make every render of the binding list
        // differ from the last one.
        expect(AppIconSource.stableHash("com.apple.Terminal")
               == AppIconSource.stableHash("com.apple.Terminal"),
               "placeholder icon colours come from an explicit stable hash")
        expect(AppIconSource.stableHash("com.apple.Terminal") == 3_578_028_786,
               "the stable hash is FNV-1a over UTF-8 and does not drift")
    }

    private static func testSnapshotIsolation() {
        let before = UserDefaults.standard.object(forKey: "timeSyncEnabled") as? Bool
        let model = AppModel.snapshot()
        expect(model.device.phase == .disconnected && !model.clock.enabled,
               "snapshot model uses isolated device and clock services")
        expect(model.modeLabels.isEmpty,
               "snapshot model does not read the real recorded-label store")
        // Labels recorded by the retired Identify tab are still honoured.
        expect(AppModel.label(for: 15, recorded: [15: "Effect 5"]) == "Ripple diffusion",
               "a recorded effect number displays as the manual's effect name")
        expect(AppModel.label(for: 13, recorded: [13: "My favourite"]) == "My favourite",
               "a free-form label is shown as written")
        expect(AppModel.label(for: 1, recorded: [1: "Wrong"]) == "Static On",
               "vendor-named protocol modes are never relabelled")
        expect(AppModel.label(for: 15, recorded: [:]) == "Ripple diffusion",
               "with nothing recorded, a mode shows its baked-in name")
        let after = UserDefaults.standard.object(forKey: "timeSyncEnabled") as? Bool
        expect(before == after, "snapshot creation does not change the real clock-sync preference")
    }
}
