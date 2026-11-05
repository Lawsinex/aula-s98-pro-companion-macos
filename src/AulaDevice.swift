import Foundation
import IOKit
import IOKit.hid
import Darwin

private func openAulaProcessLock() -> Int32 {
    let path = "/tmp/io.github.lawsinex.aula-s98-pro-companion.\(getuid()).lock"
    let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                          S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { return -1 }

    var metadata = stat()
    let isRegularFile = fstat(descriptor, &metadata) == 0 &&
        metadata.st_uid == getuid() &&
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    guard isRegularFile else {
        close(descriptor)
        return -1
    }
    return descriptor
}

// MARK: - Wire protocol
//
// Recovered from the AULA S98Pro Windows driver (DeviceDriver.exe).
//   Transport : 64-byte HID Feature report, report ID 0, on vendor collection 0xFF13.
//   MANDATORY : every write must be followed by a Feature *read*, or the firmware
//               silently ignores the whole transaction.
//   Envelope  : 04 18 BEGIN -> 04 <select> -> payload -> 04 02 END -> 04 F0 SAVE
//
enum Proto {
    static let vid = 0x0C45, pid = 0x800A, usagePage = 0xFF13
    static let packet = 64
    static let delay: UInt32 = 35_000      // cmd_delaytime=35ms, from rgb-keyboard.xml

    static let opBegin: UInt8  = 0x18
    static let opLight: UInt8  = 0x13      // lighting mode record
    static let opPerKey: UInt8 = 0x23      // per-key frame ("user lighting")
    static let opConfig: UInt8 = 0x17      // keyboard settings
    static let opEnd: UInt8    = 0x02
    static let opSave: UInt8   = 0xF0

    static let opTime: UInt8 = 0x28        // set the keyboard's real-time clock

    static let userLightMode = 0x80        // light mode that displays the per-key frame
    static let perKeyChunks  = 9           // 9 x 64 = 576 bytes
    static let maxLED        = 123
}

struct RGB8: Equatable, Hashable, Codable {
    var r: UInt8, g: UInt8, b: UInt8
    static let black = RGB8(r: 0, g: 0, b: 0)
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard raw.count == 6, raw.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(raw, radix: 16) else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF),
                  g: UInt8((value >> 8) & 0xFF),
                  b: UInt8(value & 0xFF))
    }
}

/// One calibration observation: the colour asked for, and the colour the keyboard
/// actually produced as judged by eye. Several of these describe how the hardware
/// distorts colour, which the app then applies to what it draws.
struct CalibrationSample: Identifiable, Equatable, Hashable, Codable {
    var id = UUID()
    var target: RGB8
    var observed: RGB8
}

/// How this keyboard actually renders colour, measured by eye.
///
/// This never changes what is sent over USB — the keyboard is left exactly as it is.
/// It corrects the *app's* display instead, so the on-screen wheel and preview show
/// what the keys really look like rather than an idealised colour the hardware does
/// not produce. `transform` therefore maps "what you asked for" to "how it appears".
/// Nothing in the device layer takes one: what goes over USB is always the colour
/// that was asked for.
struct ColorCalibration: Equatable, Hashable, Codable {
    var hueShiftDegrees = 0.0
    var saturationScale = 1.0
    var valueScale = 1.0
    /// Observations the correction is derived from. Editing these is the only
    /// supported way to change the correction; the scalars above are outputs.
    var samples: [CalibrationSample] = []

    static let identity = ColorCalibration()

    var normalized: ColorCalibration {
        var copy = self
        copy.samples = Array(copy.samples.prefix(Self.maximumSamples))
        copy.hueShiftDegrees = Self.finite(copy.hueShiftDegrees, fallback: 0, range: -180...180)
        copy.saturationScale = Self.finite(copy.saturationScale, fallback: 1, range: 0...4)
        copy.valueScale = Self.finite(copy.valueScale, fallback: 1, range: 0...4)
        return copy
    }

    func transform(_ input: RGB8) -> RGB8 {
        let value = normalized
        return Self.adjustHSV(input, hueDegrees: value.hueShiftDegrees,
                              saturationScale: value.saturationScale,
                              valueScale: value.valueScale)
    }

    /// Recompute the measured distortion from the collected samples.
    ///
    /// Each sample says "I asked for T and the keys showed W", so the samples describe
    /// the map T -> W directly. That is exactly what the display needs, so nothing is
    /// inverted here. Hue deltas are averaged circularly, otherwise observations either
    /// side of the red wrap-around cancel instead of averaging.
    mutating func recomputeFromSamples() {
        var sinSum = 0.0, cosSum = 0.0, satRatioSum = 0.0, valRatioSum = 0.0
        var hueCount = 0, satCount = 0, valCount = 0

        for sample in samples {
            let target = Self.hsv(sample.target)
            let observed = Self.hsv(sample.observed)
            if target.saturation > 0.05 && observed.saturation > 0.05 {
                var delta = observed.hue - target.hue
                if delta > 0.5 { delta -= 1 }
                if delta < -0.5 { delta += 1 }
                let radians = delta * 2 * .pi
                sinSum += sin(radians); cosSum += cos(radians); hueCount += 1
            }
            // A neutral observation has no meaningful hue, but it is still valid
            // evidence that this requested colour lost its saturation.
            if target.saturation > 0.05 {
                satRatioSum += observed.saturation / target.saturation; satCount += 1
            }
            if target.value > 0.05 {
                valRatioSum += observed.value / target.value; valCount += 1
            }
        }

        if hueCount > 0 && !(sinSum == 0 && cosSum == 0) {
            let meanDelta = atan2(sinSum / Double(hueCount), cosSum / Double(hueCount)) / (2 * .pi)
            hueShiftDegrees = meanDelta * 360
        } else {
            hueShiftDegrees = 0
        }
        saturationScale = satCount > 0 ? satRatioSum / Double(satCount) : 1
        valueScale = valCount > 0 ? valRatioSum / Double(valCount) : 1
        self = normalized
    }

    /// How the keyboard is expected to render `input`. Identity until data points exist.
    func predictedAppearance(of input: RGB8) -> RGB8 {
        samples.isEmpty ? input : transform(input)
    }

    static let maximumSamples = 64

    /// Returns false when the sample could not be stored. Truncation happens BEFORE the
    /// correction is recomputed, so the scalars can never be derived from a sample that
    /// was then discarded — which would silently shift every colour on the next edit.
    @discardableResult
    mutating func addSample(target: RGB8, observed: RGB8) -> Bool {
        guard samples.count < Self.maximumSamples else { return false }
        samples.append(CalibrationSample(target: target, observed: observed))
        recomputeFromSamples()
        return true
    }

    mutating func removeSample(id: UUID) {
        samples.removeAll { $0.id == id }
        recomputeFromSamples()
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value)).rounded())
    }

    private static func finite(_ value: Double, fallback: Double,
                               range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return max(range.lowerBound, min(range.upperBound, value))
    }

    private static func hsv(_ color: RGB8) -> (hue: Double, saturation: Double, value: Double) {
        let r = Double(color.r) / 255, g = Double(color.g) / 255, b = Double(color.b) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        guard delta > 0 else { return (0, 0, maximum) }
        let baseHue: Double
        if maximum == r { baseHue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == g { baseHue = (b - r) / delta + 2 }
        else { baseHue = (r - g) / delta + 4 }
        let saturation = maximum == 0 ? 0 : delta / maximum
        var hue = baseHue / 6
        hue = hue - floor(hue)
        return (hue, saturation, maximum)
    }

    private static func adjustHSV(_ color: RGB8, hueDegrees: Double,
                                  saturationScale: Double, valueScale: Double) -> RGB8 {
        let source = hsv(color)
        var hue = source.hue + hueDegrees / 360
        hue = hue - floor(hue)
        let saturation = max(0, min(1, source.saturation * saturationScale))
        let value = max(0, min(1, source.value * valueScale))

        let sector = hue * 6
        let index = Int(floor(sector)) % 6
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        let output: (Double, Double, Double)
        switch index {
        case 0: output = (value, t, p)
        case 1: output = (q, value, p)
        case 2: output = (p, value, t)
        case 3: output = (p, q, value)
        case 4: output = (t, p, value)
        default: output = (value, p, q)
        }
        return RGB8(r: byte(output.0 * 255),
                    g: byte(output.1 * 255),
                    b: byte(output.2 * 255))
    }
}

extension ColorCalibration {
    /// Older builds also stored a channel order and per-channel balances. Nothing
    /// could set them to anything but identity once samples drove the correction,
    /// so those keys are simply ignored when an old workspace is read.
    private enum CodingKeys: String, CodingKey {
        case hueShiftDegrees, saturationScale, valueScale, samples
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        hueShiftDegrees = try values.decodeIfPresent(Double.self, forKey: .hueShiftDegrees) ?? 0
        saturationScale = try values.decodeIfPresent(Double.self, forKey: .saturationScale) ?? 1
        valueScale = try values.decodeIfPresent(Double.self, forKey: .valueScale) ?? 1
        samples = try values.decodeIfPresent([CalibrationSample].self, forKey: .samples) ?? []
        self = normalized
    }

    func encode(to encoder: Encoder) throws {
        let value = normalized
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(value.hueShiftDegrees, forKey: .hueShiftDegrees)
        try values.encode(value.saturationScale, forKey: .saturationScale)
        try values.encode(value.valueScale, forKey: .valueScale)
        try values.encode(value.samples, forKey: .samples)
    }
}

struct LightMode: Identifiable, Hashable {
    let id: Int, name: String, animated: Bool, usesColor: Bool
}

/// The keyboard has 19 lighting effects plus off (AULA's own spec sheet and manual
/// both say 19). The nine modes in `kNamedModes` carry the names the Windows driver
/// pairs with their real mode byte via AddString(name, lParam). The other eleven are
/// the manual's names, resolved through `kKeyboardEffects` — the test suite asserts
/// they still agree with that table and with the CLI's copy in aula-s98.c.
let kModes: [LightMode] = [
    .init(id: 0,  name: "Off",                           animated: false, usesColor: false),
    .init(id: 1,  name: "Static On",                     animated: false, usesColor: true),
    .init(id: 2,  name: "Single light up",               animated: true,  usesColor: true),
    .init(id: 3,  name: "Single extinction",             animated: true,  usesColor: true),
    .init(id: 4,  name: "Starlight",                     animated: true,  usesColor: true),
    .init(id: 5,  name: "Fluttering",                    animated: true,  usesColor: true),
    .init(id: 6,  name: "Flowers are blooming",          animated: true,  usesColor: true),
    .init(id: 7,  name: "Dynamic Breathing",             animated: true,  usesColor: true),
    .init(id: 8,  name: "Spectral cycle",                animated: true,  usesColor: true),
    .init(id: 9,  name: "Colorful Fountain",             animated: true,  usesColor: false),
    .init(id: 10, name: "Rainbow Wave",                  animated: true,  usesColor: false),
    .init(id: 11, name: "Following Currents",            animated: true,  usesColor: true),
    .init(id: 12, name: "Peak Revolving",                animated: true,  usesColor: true),
    .init(id: 13, name: "Be touch-and-go",               animated: true,  usesColor: true),
    .init(id: 14, name: "Kill two birds with one stone", animated: true,  usesColor: true),
    .init(id: 15, name: "Ripple diffusion",              animated: true,  usesColor: true),
    .init(id: 16, name: "A continuous flow",             animated: true,  usesColor: true),
    .init(id: 17, name: "Range upon range of mountains", animated: true,  usesColor: true),
    .init(id: 18, name: "Light wind and drizzling rain", animated: true,  usesColor: true),
    .init(id: 19, name: "Shuttle back and forth",        animated: true,  usesColor: true),
]

/// The manual's 20 backlight effects, in the order the LCD knob cycles them.
///
/// The manual prints them in two columns and does not say which way to read it.
/// The measured data settles it: the eleven effect numbers recorded by hand leave
/// exactly nine free, and those nine must be the nine modes AULA names. Reading the
/// columns top-to-bottom is impossible — it puts "Static constant brightness" and
/// "was studded with stars" in occupied slots, when Static On and Starlight have to
/// be free. Reading across the rows fits perfectly, and every free slot lands on a
/// matching name: Adrift/Following Currents, Static constant brightness/Static On,
/// was studded with stars/Starlight, Dynamic respiration/Dynamic Breathing, OFF/Off.
///
/// The wording is AULA's own rough translation from the Chinese; only the first
/// letter is normalised for display.
let kManualEffectNames: [Int: String] = [
    1:  "Adrift",                            2:  "The path winds along mountain ridges",
    3:  "Be touch-and-go",                   4:  "Kill two birds with one stone",
    5:  "Ripple diffusion",                  6:  "A continuous flow",
    7:  "Range upon range of mountains",     8:  "Light wind and drizzling rain",
    9:  "Shuttle back and forth",            10: "Static constant brightness",
    11: "Single light up",                   12: "Single extinction",
    13: "Was studded with stars",            14: "Flying snow all over the sky",
    15: "Flowers are blooming",              16: "Dynamic respiration",
    17: "Spectral cycle",                    18: "Colorful spring surging",
    19: "Colorful vertical and horizontal",  20: "OFF",
]

/// Effect numbers for the modes AULA does name, derived from the same fit. They
/// rename nothing; they are what proves the two tables partition 1-20.
let kNamedModeEffects: [Int: Int] = [
    0: 20, 1: 10, 4: 13, 5: 14, 7: 16, 9: 18, 10: 19, 11: 1, 12: 2,
]

/// Protocol mode id -> the effect number the keyboard's own LCD shows for it.
///
/// AULA's driver names only nine modes; the rest it exposes as bare numbers that do
/// not match the keyboard's numbering. This table was recorded by hand against the
/// real hardware — select a mode over USB, read the LCD — and is the authoritative
/// name for those modes. A useful consistency check: these eleven use effect numbers
/// 3-9, 11, 12, 15 and 17, and the nine remaining numbers are exactly enough for the
/// nine modes AULA does name. See data/mode-labels.json.
let kKeyboardEffects: [Int: Int] = [
    2: 11, 3: 12, 6: 15, 8: 17,
    13: 3, 14: 4, 15: 5, 16: 6, 17: 7, 18: 8, 19: 9,
]

/// The effect number the keyboard's LCD shows for a mode, named or not.
func keyboardEffectNumber(for mode: Int) -> Int? {
    kKeyboardEffects[mode] ?? kNamedModeEffects[mode]
}

/// The manual's name for a mode AULA never named.
func keyboardEffectName(for mode: Int) -> String? {
    kKeyboardEffects[mode].flatMap { kManualEffectNames[$0] }
}

/// Named by the vendor's driver; everything else is reachable but unlabelled.
let kNamedModes: Set<Int> = [0, 1, 4, 5, 7, 9, 10, 11, 12]

struct LightState: Equatable, Hashable, Codable {
    var mode = 1
    var color = RGB8(r: 0, g: 255, b: 0)
    var colorful = false
    var brightness = 5
    var speed = 3
    var reverse = false

    var normalized: LightState {
        var copy = self
        if copy.mode != Proto.userLightMode && !(0...19).contains(copy.mode) { copy.mode = 1 }
        copy.brightness = max(0, min(5, copy.brightness))
        copy.speed = max(0, min(5, copy.speed))
        return copy
    }
}

/// Keyboard behaviour settings (opcode 0x17). Offsets recovered from fcn.00413ff0.
struct KeyboardConfig: Equatable, Hashable, Codable {
    var disableWin = false        // payload[2]
    var disableAltF4 = false      // payload[3]
    var disableAltTab = false     // payload[4]
    var sleepMinutes = 5          // payload[5]  (0 = never)
    var keyResponseMs = 0         // payload[6]

    var normalized: KeyboardConfig {
        var copy = self
        copy.sleepMinutes = max(0, min(60, copy.sleepMinutes))
        copy.keyResponseMs = max(0, min(255, copy.keyResponseMs))
        return copy
    }
}

// MARK: - Packet codec

/// Pure packet construction kept separate from I/O so the protocol can be unit tested.
enum AulaProtocolCodec {
    static func command(_ op: UInt8, arg: UInt8 = 0) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: Proto.packet)
        packet[0] = 0x04; packet[1] = op; packet[8] = arg
        return packet
    }

    static func lightRecord(mode: Int, state: LightState) -> [UInt8] {
        let state = state.normalized
        let color = state.color
        var packet = [UInt8](repeating: 0, count: Proto.packet)
        packet[0] = UInt8(mode & 0xFF)
        packet[1] = color.r; packet[2] = color.g; packet[3] = color.b
        packet[8] = state.colorful ? 1 : 0
        packet[9] = UInt8(state.brightness)
        packet[10] = UInt8(state.speed)
        packet[11] = state.reverse ? 1 : 0
        packet[14] = 0xAA; packet[15] = 0x55
        return packet
    }

    static func perKeyFrame(_ colors: [Int: RGB8]) -> [UInt8] {
        let total = Proto.perKeyChunks * Proto.packet
        var frame = [UInt8](repeating: 0, count: total)
        for index in 1...Proto.maxLED { frame[index * 4] = UInt8(index) }
        for (index, color) in colors where (1...Proto.maxLED).contains(index) {
            let offset = index * 4
            frame[offset + 1] = color.r
            frame[offset + 2] = color.g
            frame[offset + 3] = color.b
        }
        frame[total - 2] = 0xAA; frame[total - 1] = 0x55
        return frame
    }

    static func configRecord(_ config: KeyboardConfig) -> [UInt8] {
        let config = config.normalized
        var packet = [UInt8](repeating: 0, count: Proto.packet)
        packet[0] = 0x00; packet[1] = 0x01
        packet[2] = config.disableWin ? 1 : 0
        packet[3] = config.disableAltF4 ? 1 : 0
        packet[4] = config.disableAltTab ? 1 : 0
        packet[5] = UInt8(config.sleepMinutes)
        packet[6] = UInt8(config.keyResponseMs)
        packet[62] = 0xAA; packet[63] = 0x55
        return packet
    }

    static func timeRecord(_ date: Date, calendar supplied: Calendar? = nil) -> [UInt8]? {
        let calendar = supplied ?? Calendar(identifier: .gregorian)
        let values = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        guard let year = values.year, let month = values.month, let day = values.day,
              let hour = values.hour, let minute = values.minute, let second = values.second,
              let weekday = values.weekday, (2000...2255).contains(year) else { return nil }

        var packet = [UInt8](repeating: 0, count: Proto.packet)
        packet[0] = 0; packet[1] = 1; packet[2] = 0x5A
        packet[3] = UInt8(year - 2000)
        packet[4] = UInt8(month); packet[5] = UInt8(day)
        packet[6] = UInt8(hour); packet[7] = UInt8(minute); packet[8] = UInt8(second)
        packet[10] = UInt8(weekday - 1)
        packet[62] = 0xAA; packet[63] = 0x55
        return packet
    }
}

// MARK: - Logging

private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Aula S98 Pro Companion.log")
private let previousLogURL = logURL.appendingPathExtension("1")
/// Past this the log rolls over to Aula S98 Pro Companion.log.1, so at most two of these exist.
private let logLimit: UInt64 = 1_000_000
/// alog is called from the HID queue and the main thread; the append and the
/// rollover must not interleave.
private let logLock = NSLock()

/// Logging is best-effort: a full disk or closed redirect must not crash control.
@discardableResult
func writeAulaLog(_ data: Data, to handle: FileHandle) -> Bool {
    do { try handle.write(contentsOf: data); return true }
    catch { return false }
}

func alog(_ msg: String) {
    let line = Data("\(Date().formatted(date: .omitted, time: .standard))  \(msg)\n".utf8)
    writeAulaLog(line, to: FileHandle.standardError)
    #if AULA_LOGIC_TESTS
    return
    #else
    let environment = ProcessInfo.processInfo.environment
    guard environment["AULA_SNAPSHOT"] != "1", environment["AULA_UI_TEST"] == nil else { return }
    logLock.lock()
    defer { logLock.unlock() }
    guard let handle = try? FileHandle(forWritingTo: logURL) else {
        try? line.write(to: logURL)
        return
    }
    guard let size = try? handle.seekToEnd() else { try? handle.close(); return }
    guard size + UInt64(line.count) > logLimit else {
        writeAulaLog(line, to: handle); try? handle.close()
        return
    }
    try? handle.close()
    try? FileManager.default.removeItem(at: previousLogURL)
    try? FileManager.default.moveItem(at: logURL, to: previousLogURL)
    try? line.write(to: logURL)
    #endif
}

// MARK: - Device

enum Job {
    case mode(LightState, persist: Bool)
    case perKey([Int: RGB8], brightness: Int, persist: Bool)
    /// A temporary test colour. It must never inherit a queued lighting SAVE.
    case calibration(LightState)

    /// Whether this job commits to the keyboard's flash rather than just previewing.
    var isPersisting: Bool {
        switch self {
        case .mode(_, let persist): return persist
        case .perKey(_, _, let persist): return persist
        case .calibration: return false
        case .config, .time: return true
        }
    }

    /// The same job, upgraded to commit. Used so latest-wins coalescing can replace
    /// what is displayed without ever downgrading a save the user already asked for.
    var persisting: Job {
        switch self {
        case .mode(let state, _):
            return .mode(state, persist: true)
        case .perKey(let colors, let brightness, _):
            return .perKey(colors, brightness: brightness, persist: true)
        case .calibration, .config, .time: return self
        }
    }
    case config(KeyboardConfig)
    case time(Date)                        // sync the keyboard RTC
}

enum DevicePhase: String, Equatable {
    case searching, disconnected, connecting, ready, applying, failed
}

enum DeviceOperationError: Error, Equatable, LocalizedError {
    case unavailable
    case busy
    case lockUnavailable
    case transport(String)
    case superseded

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Keyboard not found — connect it by USB-C"
        case .busy: return "Keyboard is busy in another Aula S98 Pro Companion process"
        case .lockUnavailable:
            return "Could not open the device lock in /tmp — restart Aula S98 Pro Companion, or check /tmp is writable"
        case .transport(let message): return message
        case .superseded: return "Superseded by a newer change"
        }
    }
}

extension Notification.Name {
    static let aulaDeviceConnected = Notification.Name("io.github.lawsinex.aula-s98-pro-companion.device-connected")
}

/// The manager can deliver a queued callback while its owner is being released.
/// Keep this weak box alive through cancellation instead of passing an unretained
/// AulaDevice pointer to the C callback.
private final class AulaDeviceCallbackContext {
    weak var owner: AulaDevice?
    init(owner: AulaDevice) { self.owner = owner }
}

private let aulaDeviceMatched: IOHIDDeviceCallback = { context, result, _, device in
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<AulaDeviceCallbackContext>.fromOpaque(context).takeUnretainedValue().owner?.deviceMatched(device)
}

private let aulaDeviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    Unmanaged<AulaDeviceCallbackContext>.fromOpaque(context).takeUnretainedValue().owner?.deviceRemoved(device)
}

private struct PendingJob {
    let job: Job
    let completion: ((Result<String, DeviceOperationError>) -> Void)?
}

final class AulaDevice: ObservableObject, @unchecked Sendable {
    static let shared = AulaDevice()

    @Published private(set) var phase: DevicePhase
    /// The idle connected message. Hoisted so the two publish sites cannot drift
    /// apart from the one view rule that reads it.
    static let idleStatus = "Connected by USB"

    /// True when the status sentence says nothing the connection dot has not
    /// already said. Only this one string is suppressed — NOT the whole .ready
    /// phase, which also carries "Clock synced · <date>" and "Keyboard settings
    /// applied". Those are the results of jobs that are invisible on the board,
    /// and they are the only feedback those jobs get.
    var statusRestatesTheDot: Bool { phase == .ready && status == Self.idleStatus }

    @Published private(set) var status: String
    private(set) var deviceReady = false

    var connected: Bool { phase == .ready || phase == .applying }
    var busy: Bool { phase == .applying }

    private var device: IOHIDDevice?
    private var manager: IOHIDManager?
    private let queue = DispatchQueue(label: "aula.hid")
    private let lock = NSLock()
    private var pending: [Int: PendingJob] = [:]
    private var draining = false
    private var lastPublishedPhase: DevicePhase?
    private var lastPublishedMessage = ""
    private var transportFailure = "Keyboard communication failed"
    private let simulated: Bool
    /// Isolated tests can record or delay jobs without opening a device or a lock.
    /// Ignored for real devices; production always executes the HID protocol below.
    private let simulatedExecutor: ((Job) -> Result<String, DeviceOperationError>)?
    private let processLockFD: Int32

    init(simulated: Bool = false,
         simulatedExecutor: ((Job) -> Result<String, DeviceOperationError>)? = nil) {
        self.simulated = simulated
        self.simulatedExecutor = simulated ? simulatedExecutor : nil
        self.phase = simulated ? .disconnected : .searching
        self.status = simulated ? "Preview — no keyboard connection" : "Looking for keyboard…"
        self.processLockFD = simulated ? -1 : openAulaProcessLock()
        guard !simulated else { return }
        queue.async { self.startManager() }
    }

    deinit {
        if processLockFD >= 0 { close(processLockFD) }
        // All work blocks retain self, so no operation can still be using these
        // handles when deinit runs. Cleanup remains ordered on the HID queue.
        let current = device
        if let manager {
            queue.async {
                if let current { IOHIDDeviceClose(current, IOOptionBits(kIOHIDOptionsTypeNone)) }
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDManagerCancel(manager)
            }
        }
    }

    private func startManager() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey: Proto.vid, kIOHIDProductIDKey: Proto.pid,
            kIOHIDPrimaryUsagePageKey: Proto.usagePage,
        ] as CFDictionary)
        let context = Unmanaged.passRetained(AulaDeviceCallbackContext(owner: self)).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, aulaDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, aulaDeviceRemoved, context)
        IOHIDManagerSetDispatchQueue(mgr, queue)
        // Apple's dispatch-queue contract requires the manager and callback context
        // to outlive cancellation and its final handler.
        let retainedManager = Unmanaged.passRetained(mgr)
        IOHIDManagerSetCancelHandler(mgr) {
            Unmanaged<AulaDeviceCallbackContext>.fromOpaque(context).release()
            retainedManager.release()
        }
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerActivate(mgr)
        guard result == kIOReturnSuccess else {
            publish(.failed, "Could not start USB monitoring (\(ioCode(result)))")
            return
        }
        queue.asyncAfter(deadline: .now() + 0.25) {
            if self.device == nil { self.refreshConnection() }
        }
    }

    fileprivate func deviceMatched(_ candidate: IOHIDDevice) {
        guard device == nil else { return }
        publish(.connecting, "Opening AULA S98 Pro…")
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            publish(.failed, "Found the keyboard but could not open it (\(ioCode(result)))")
            return
        }
        device = candidate
        deviceReady = true
        publish(.ready, Self.idleStatus)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .aulaDeviceConnected, object: self)
        }
    }

    fileprivate func deviceRemoved(_ removed: IOHIDDevice) {
        guard let current = device, CFEqual(current, removed) else { return }
        IOHIDDeviceClose(current, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil; deviceReady = false
        publish(.disconnected, "Keyboard disconnected — connect it by USB-C")
    }

    private func refreshConnection() {
        guard device == nil, let manager,
              let candidates = (IOHIDManagerCopyDevices(manager) as NSSet?)?.allObjects,
              let first = candidates.first else {
            if device == nil { publish(.disconnected, "Keyboard not found — connect it by USB-C") }
            return
        }
        let candidate = first as! IOHIDDevice
        deviceMatched(candidate)
    }

    func retryConnection() {
        guard !simulated else { return }
        queue.async {
            if self.device != nil {
                self.publish(.ready, Self.idleStatus)
                return
            }
            self.publish(.searching, "Looking for keyboard…")
            self.refreshConnection()
        }
    }

    private func publish(_ nextPhase: DevicePhase, _ message: String) {
        guard nextPhase != lastPublishedPhase || message != lastPublishedMessage else { return }
        lastPublishedPhase = nextPhase; lastPublishedMessage = message
        alog((nextPhase == .failed || nextPhase == .disconnected ? "ERR " : "ok  ") + message)
        DispatchQueue.main.async {
            self.phase = nextPhase
            self.status = message
        }
    }

    private func invalidateDevice() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil; deviceReady = false
    }

    /// SetReport(Feature) + the mandatory GetReport(Feature). Returns the reply.
    @discardableResult
    private func transact(_ payload: [UInt8], expectAck: Bool = false,
                          expectedOpcode: UInt8? = nil) -> [UInt8]? {
        guard payload.count == Proto.packet else {
            transportFailure = "Refused malformed \(payload.count)-byte packet"
            return nil
        }
        guard let device else { transportFailure = "Keyboard is not connected"; return nil }
        let writeResult = payload.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, Proto.packet)
        }
        guard writeResult == kIOReturnSuccess else {
            transportFailure = "USB write failed (\(ioCode(writeResult)))"
            return nil
        }
        usleep(Proto.delay)
        var reply = [UInt8](repeating: 0, count: Proto.packet)
        var len = CFIndex(Proto.packet)
        let readResult = reply.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &len)
        }
        usleep(Proto.delay)
        guard readResult == kIOReturnSuccess, len >= 4 else {
            transportFailure = "USB reply failed (\(ioCode(readResult)), \(len) bytes)"
            return nil
        }
        if expectAck && reply[3] != 1 {
            transportFailure = "Keyboard rejected command 0x\(String(format: "%02X", expectedOpcode ?? payload[1]))"
            return nil
        }
        return reply
    }

    /// Bulk write with no read-back. The driver's multi-chunk path does the same:
    /// only the single-packet commands are acknowledged, bulk data just streams.
    @discardableResult
    private func rawSet(_ bytes: [UInt8]) -> Bool {
        guard let device, bytes.count == Proto.packet else {
            transportFailure = "Refused malformed per-key packet"
            return false
        }
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, Proto.packet)
        }
        if result != kIOReturnSuccess {
            transportFailure = "Per-key USB write failed (\(ioCode(result)))"
        }
        return result == kIOReturnSuccess
    }

    // MARK: Public API — all coalescing

    private func lane(_ job: Job) -> Int {
        // Effects and per-key output share the same firmware state. Keeping them in
        // one latest-wins lane prevents an old paint upload overriding a newer effect.
        switch job {
        case .mode, .perKey: return 0
        case .config: return 1
        case .time: return 2
        case .calibration: return 3
        }
    }

    private func operationName(_ job: Job) -> String {
        switch job {
        case .mode: return "Applying lighting…"
        case .perKey: return "Uploading per-key colour…"
        case .config: return "Applying keyboard settings…"
        case .time: return "Syncing keyboard clock…"
        case .calibration: return "Showing calibration colour…"
        }
    }

    func apply(_ job: Job,
               completion: ((Result<String, DeviceOperationError>) -> Void)? = nil) {
        let lane = lane(job)
        var replaced: [PendingJob] = []
        lock.lock()
        // Closing calibration or selecting a real output must discard a probe
        // still queued behind another operation. Calibration has its own lane so
        // it cannot replace or inherit a durable lighting change.
        if lane == 0, let staleCalibration = pending.removeValue(forKey: 3) {
            replaced.append(staleCalibration)
        }
        // Latest-wins, but persistence is sticky: a preview arriving while a durable
        // save is still queued must not silently downgrade it to a preview, or the
        // lighting looks right and is never committed to flash. Release a control and
        // start dragging again quickly and that is exactly what used to happen.
        var incoming = job
        if let queued = pending[lane], queued.job.isPersisting, !incoming.isPersisting {
            incoming = incoming.persisting
        }
        if let old = pending.updateValue(PendingJob(job: incoming, completion: completion),
                                         forKey: lane) {
            replaced.append(old)
        }
        let start = !draining
        if start { draining = true }
        lock.unlock()
        for old in replaced {
            DispatchQueue.main.async { old.completion?(.failure(.superseded)) }
        }
        guard start else { return }
        queue.async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            let nextLane = [1, 0, 3, 2].first { pending[$0] != nil }
            let next = nextLane.flatMap { pending.removeValue(forKey: $0) }
            if next == nil { draining = false; lock.unlock(); return }
            lock.unlock()

            let pendingJob = next!
            publish(.applying, operationName(pendingJob.job))
            let result = execute(pendingJob.job)
            switch result {
            case .success(let message): publish(.ready, message)
            case .failure(let error):
                let phase: DevicePhase = error == .unavailable ? .disconnected : .failed
                publish(phase, error.localizedDescription)
            }
            DispatchQueue.main.async { pendingJob.completion?(result) }
        }
    }

    private func execute(_ job: Job) -> Result<String, DeviceOperationError> {
        if simulated { return simulatedExecutor?(job) ?? .failure(.unavailable) }
        // Opened once at launch. If that failed, saying "busy" would send the user
        // looking for another process that does not exist.
        guard processLockFD >= 0 else { return .failure(.lockUnavailable) }
        guard flock(processLockFD, LOCK_EX | LOCK_NB) == 0 else { return .failure(.busy) }
        defer { flock(processLockFD, LOCK_UN) }

        for attempt in 0..<2 {
            if device == nil { refreshConnection() }
            guard device != nil else { return .failure(.unavailable) }
            transportFailure = "Keyboard communication failed"
            if let message = executeOnce(job) { return .success(message) }
            invalidateDevice()
            if attempt == 0 {
                usleep(60_000)
                refreshConnection()
            }
        }
        return .failure(.transport(transportFailure))
    }

    private func executeOnce(_ job: Job) -> String? {
        switch job {
        case .mode(let state, let persist):
            guard sendModeOnce(state, persist: persist) else { return nil }
            let modeName = kModes.first { $0.id == state.mode }?.name ?? "Lighting"
            return persist ? "\(modeName) applied · \(state.color.hex)" : "\(modeName) preview updated"
        case .calibration(let state):
            guard sendModeOnce(state, persist: false) else { return nil }
            return "Calibration preview updated"
        case .perKey(let colors, let brightness, let persist):
            guard sendPerKeyOnce(colors, brightness: brightness, persist: persist) else { return nil }
            let lit = colors.values.filter { $0 != RGB8.black }.count
            return persist ? "Per-key colour applied · \(lit) keys lit" : "Per-key preview updated"
        case .config(let config):
            guard sendConfigOnce(config) else { return nil }
            return "Keyboard settings applied"
        case .time(let date):
            guard sendTimeOnce(date) else { return nil }
            return "Clock synced · \(date.formatted(date: .abbreviated, time: .standard))"
        }
    }

    // MARK: Transactions

    private func acknowledgedCommand(_ opcode: UInt8, arg: UInt8 = 0) -> Bool {
        transact(AulaProtocolCodec.command(opcode, arg: arg), expectAck: true,
                 expectedOpcode: opcode) != nil
    }

    private func sendModeOnce(_ state: LightState, persist: Bool) -> Bool {
        let state = state.normalized
        guard acknowledgedCommand(Proto.opBegin),
              acknowledgedCommand(Proto.opLight, arg: 1),
              transact(AulaProtocolCodec.lightRecord(mode: state.mode, state: state)) != nil,
              acknowledgedCommand(Proto.opEnd) else { return false }
        return !persist || acknowledgedCommand(Proto.opSave)
    }

    private func sendPerKeyOnce(_ colors: [Int: RGB8], brightness: Int, persist: Bool) -> Bool {
        var state = LightState(); state.brightness = brightness
        // The mode-select must be committed on a durable save. Leaving it a preview
        // stores the frame but not the 0x80 selection, so after a power cycle the
        // keyboard restores its previous effect and the "applied" layout never shows.
        guard sendModeOnce(state.withMode(Proto.userLightMode), persist: persist),
              acknowledgedCommand(Proto.opBegin),
              acknowledgedCommand(Proto.opPerKey, arg: UInt8(Proto.perKeyChunks)) else { return false }

        let frame = AulaProtocolCodec.perKeyFrame(colors)
        for chunk in 0..<Proto.perKeyChunks {
            let range = (chunk * Proto.packet)..<((chunk + 1) * Proto.packet)
            guard rawSet(Array(frame[range])) else { return false }
            usleep(10_000)
        }
        guard acknowledgedCommand(Proto.opEnd) else { return false }
        return !persist || acknowledgedCommand(Proto.opSave)
    }

    private func sendConfigOnce(_ config: KeyboardConfig) -> Bool {
        var select = AulaProtocolCodec.command(Proto.opConfig, arg: 1); select[2] = 1
        guard acknowledgedCommand(Proto.opBegin),
              transact(select, expectAck: true, expectedOpcode: Proto.opConfig) != nil,
              transact(AulaProtocolCodec.configRecord(config)) != nil,
              acknowledgedCommand(Proto.opEnd) else { return false }
        return true
    }

    private func sendTimeOnce(_ date: Date) -> Bool {
        guard let record = AulaProtocolCodec.timeRecord(date) else {
            transportFailure = "Could not read the system clock"
            return false
        }
        guard acknowledgedCommand(Proto.opBegin),
              acknowledgedCommand(Proto.opTime, arg: 1),
              transact(record) != nil,
              acknowledgedCommand(Proto.opEnd) else { return false }
        return true
    }
}

private func ioCode(_ result: IOReturn) -> String {
    String(format: "0x%08X", result)
}

func hexPrefix(_ bytes: [UInt8]?) -> String {
    guard let bytes else { return "(nil)" }
    return bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
}

extension LightState {
    func withMode(_ mode: Int) -> LightState {
        var copy = self; copy.mode = mode; return copy
    }
}
