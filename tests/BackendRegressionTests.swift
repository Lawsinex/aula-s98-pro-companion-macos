import Foundation
import Darwin

/// Exercises real job coalescing with a bounded fake executor, never HID or prefs.
@MainActor
enum BackendRegressionTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Job] = []
        private var completed = 0
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        func execute(_ job: Job) -> Result<String, DeviceOperationError> {
            lock.lock()
            recorded.append(job)
            let first = recorded.count == 1
            lock.unlock()
            if first {
                entered.signal()
                guard release.wait(timeout: .now() + 2) == .success else {
                    return .failure(.transport("Regression test gate timed out"))
                }
            }
            lock.lock(); completed += 1; lock.unlock()
            return .success("Isolated regression fixture")
        }

        var jobs: [Job] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }
        var completionCount: Int {
            lock.lock(); defer { lock.unlock() }
            return completed
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        testNeutralCalibration(expect: expect)
        testCalibrationDoesNotInheritSave(expect: expect)
        testQueuedCalibrationIsDiscardedByRealOutput(expect: expect)
        testOrdinaryPreviewPreservesCommitIntent(expect: expect)
        testClockToggleAndManualSync(expect: expect)
        testSimulationResourceIsolation(expect: expect)
        testSafeLogging(expect: expect)
    }

    private static func pump(until predicate: () -> Bool, timeout: TimeInterval = 1) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return predicate()
    }

    private static func testNeutralCalibration(expect: (Bool, String) -> Void) {
        var calibration = ColorCalibration.identity
        let red = RGB8(r: 255, g: 0, b: 0)
        let gray = RGB8(r: 127, g: 127, b: 127)
        calibration.addSample(target: red, observed: gray)
        expect(calibration.saturationScale == 0,
               "neutral calibration evidence removes saturation even though hue is undefined")
        expect(calibration.predictedAppearance(of: red) == gray,
               "a saturated-to-neutral observation reproduces the observed neutral colour")
        expect(calibration.hueShiftDegrees == 0,
               "a neutral observation does not invent a hue offset")
    }

    private static func testCalibrationDoesNotInheritSave(expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
        var completed = 0
        device.apply(.config(KeyboardConfig())) { _ in completed += 1 }
        expect(recorder.entered.wait(timeout: .now() + 1) == .success,
               "the isolated executor holds the first transaction")
        var state = LightState(); state.color = RGB8(r: 255, g: 0, b: 0)
        device.apply(.mode(state, persist: true)) { _ in completed += 1 }
        state.color = RGB8(r: 0, g: 0, b: 255)
        device.apply(.calibration(state)) { _ in completed += 1 }
        recorder.release.signal()
        expect(pump(until: { completed == 3 }), "commit and calibration callbacks complete")
        let jobs = recorder.jobs
        expect(jobs.count == 3, "a temporary probe does not drop the queued durable output")
        if jobs.count == 3 {
            if case .mode(let sent, let persist) = jobs[1] {
                expect(persist && sent.color == RGB8(r: 255, g: 0, b: 0),
                       "the requested red lighting commit retains its SAVE intent")
            } else { expect(false, "the durable lighting job runs before its calibration probe") }
            if case .calibration(let sent) = jobs[2] {
                expect(!jobs[2].isPersisting && !jobs[2].persisting.isPersisting &&
                       sent.color == RGB8(r: 0, g: 0, b: 255),
                       "a calibration probe can never be upgraded to SAVE")
            } else { expect(false, "the temporary colour remains an explicit calibration job") }
        }
    }

    private static func testQueuedCalibrationIsDiscardedByRealOutput(expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
        var completed = 0
        var superseded = false
        device.apply(.config(KeyboardConfig())) { _ in completed += 1 }
        expect(recorder.entered.wait(timeout: .now() + 1) == .success,
               "the restore test holds its first transaction")
        device.apply(.calibration(LightState())) { result in
            superseded = result == .failure(.superseded)
            completed += 1
        }
        device.apply(.perKey([1: RGB8(r: 1, g: 2, b: 3)], brightness: 4, persist: true)) { _ in
            completed += 1
        }
        recorder.release.signal()
        expect(pump(until: { completed == 3 }), "queued probe supersession and output callbacks complete")
        expect(superseded, "restoring per-key output reports the queued probe as superseded")
        expect(recorder.jobs.count == 2 && !recorder.jobs.contains(where: {
            if case .calibration = $0 { return true }; return false
        }), "a stale calibration probe never runs after a newer output selection")
    }

    private static func testOrdinaryPreviewPreservesCommitIntent(expect: (Bool, String) -> Void) {
        let recorder = Recorder()
        let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
        var completed = 0
        device.apply(.config(KeyboardConfig())) { _ in completed += 1 }
        expect(recorder.entered.wait(timeout: .now() + 1) == .success,
               "the ordinary coalescing test holds its first transaction")
        device.apply(.mode(LightState(), persist: true)) { _ in completed += 1 }
        var latest = LightState(); latest.color = RGB8(r: 9, g: 8, b: 7)
        device.apply(.mode(latest, persist: false)) { _ in completed += 1 }
        recorder.release.signal()
        expect(pump(until: { completed == 3 }), "ordinary preview coalescing callbacks complete")
        let jobs = recorder.jobs
        if jobs.count == 2, case .mode(let sent, let persist) = jobs[1] {
            expect(sent == latest && persist, "ordinary drag previews preserve an already queued SAVE")
        } else { expect(false, "ordinary previews still coalesce to one latest output job") }
    }

    private static func testClockToggleAndManualSync(expect: (Bool, String) -> Void) {
        do {
            let recorder = Recorder()
            let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
            let clock = TimeSync(persistPreferences: false, enabled: false)
            clock.attach(device)
            clock.enabled = true
            expect(recorder.entered.wait(timeout: .now() + 1) == .success,
                   "automatic clock request enters the bounded executor")
            clock.enabled = false
            recorder.release.signal()
            expect(pump(until: { recorder.completionCount == 1 }), "the old automatic clock request completes")
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            expect(clock.lastSync == "Automatic sync is off" && clock.lastSyncDate == nil,
                   "a late automatic completion cannot overwrite the disabled clock status")
            clock.syncNow()
            expect(pump(until: { clock.lastSyncDate != nil }), "manual clock sync works while automation is disabled")
            expect(!clock.enabled && recorder.jobs.count == 2 && clock.lastSync.hasPrefix("Last synced"),
                   "manual sync reports success without re-enabling automatic sync")
            if case .time(let target) = recorder.jobs.last, let sentAt = clock.lastSyncDate {
                expect(abs(target.timeIntervalSince(sentAt) - 1) < 0.000_001,
                       "clock sync compensates one second without shifting sync history")
            } else {
                expect(false, "manual sync records its clock target and actual request time")
            }
        }
        do {
            let recorder = Recorder()
            let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
            let clock = TimeSync(persistPreferences: false, enabled: false)
            clock.attach(device)
            clock.enabled = true
            expect(recorder.entered.wait(timeout: .now() + 1) == .success,
                   "the rapidly toggled automatic request enters the executor")
            clock.enabled = false
            clock.enabled = true
            expect(recorder.jobs.count == 1, "rapid off/on does not start overlapping logical clock requests")
            recorder.release.signal()
            expect(pump(until: { clock.lastSyncDate != nil }), "a re-enabled clock refreshes after its obsolete request")
            expect(recorder.jobs.count == 2 && clock.enabled,
                   "rapid off/on produces one obsolete request and exactly one current refresh")
            clock.enabled = false
        }
        do {
            let recorder = Recorder()
            let device = AulaDevice(simulated: true, simulatedExecutor: recorder.execute)
            let clock = TimeSync(persistPreferences: false, enabled: false)
            clock.attach(device)
            clock.enabled = true
            expect(recorder.entered.wait(timeout: .now() + 1) == .success,
                   "the manual-after-disable fixture enters its automatic request")
            clock.enabled = false
            clock.syncNow()
            recorder.release.signal()
            expect(pump(until: { clock.lastSyncDate != nil }),
                   "a manual request made while an obsolete automatic request drains is preserved")
            expect(recorder.jobs.count == 2 && !clock.enabled,
                   "queued manual sync neither overlaps the old request nor enables automation")
        }
    }

    private static func testSimulationResourceIsolation(expect: (Bool, String) -> Void) {
        func descriptorCount() -> Int {
            (0..<4096).reduce(0) { count, descriptor in
                count + (fcntl(Int32(descriptor), F_GETFD) >= 0 ? 1 : 0)
            }
        }
        let before = descriptorCount()
        for _ in 0..<32 { autoreleasepool { _ = AulaDevice(simulated: true) } }
        expect(descriptorCount() == before, "discarded simulated devices open no process-lock descriptors")
    }

    private static func testSafeLogging(expect: (Bool, String) -> Void) {
        let pipe = Pipe()
        do { try pipe.fileHandleForWriting.close() }
        catch { expect(false, "the closed-log fixture can be prepared"); return }
        expect(!writeAulaLog(Data("discarded log fixture".utf8), to: pipe.fileHandleForWriting),
               "a failed log write is returned safely instead of throwing a Foundation exception")
        try? pipe.fileHandleForReading.close()
    }
}
