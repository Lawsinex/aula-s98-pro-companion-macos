import Foundation

struct Preset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var isPerKey: Bool = false
    var state: LightState = LightState()
    var keys: [Int: RGB8] = [:]
    var isBuiltIn: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, isPerKey, state, keys, isBuiltIn
    }

    init(id: UUID = UUID(), name: String, isPerKey: Bool = false,
         state: LightState = LightState(), keys: [Int: RGB8] = [:],
         isBuiltIn: Bool = false) {
        self.id = id; self.name = name; self.isPerKey = isPerKey
        self.state = state; self.keys = keys; self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        isPerKey = try values.decodeIfPresent(Bool.self, forKey: .isPerKey) ?? false
        state = try values.decodeIfPresent(LightState.self, forKey: .state) ?? LightState()
        keys = try values.decodeIfPresent([Int: RGB8].self, forKey: .keys) ?? [:]
        isBuiltIn = try values.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    /// A representative colour for the swatch in the preset list.
    var swatch: RGB8 {
        if !isPerKey { return state.color }
        let lit = keys.values.filter { $0 != .black }
        guard !lit.isEmpty else { return .black }
        let n = lit.count
        return RGB8(r: UInt8(lit.reduce(0) { $0 + Int($1.r) } / n),
                    g: UInt8(lit.reduce(0) { $0 + Int($1.g) } / n),
                    b: UInt8(lit.reduce(0) { $0 + Int($1.b) } / n))
    }
}

private struct PresetFile: Codable {
    var schemaVersion: Int
    var presets: [Preset]
}

private struct PresetSchemaHeader: Decodable {
    var schemaVersion: Int
}

enum PresetStoreError: Error, LocalizedError {
    case fileTooLarge
    case unreadable
    case noValidPresets
    case unsupportedSchema(Int)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: return "That preset file is larger than 1 MB"
        case .unreadable: return "That file is not a valid Aula S98 Pro Companion preset export"
        case .noValidPresets: return "No valid presets were found in that file"
        case .unsupportedSchema(let version):
            return "Preset schema \(version) is not supported by this Aula S98 Pro Companion version. The file is read-only and has not been changed."
        case .saveFailed(let message): return "Could not save presets: \(message)"
        }
    }
}

final class PresetStore: ObservableObject, @unchecked Sendable {
    static let shared = PresetStore()

    @Published private(set) var userPresets: [Preset] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isReadOnly = false

    var presets: [Preset] { Self.builtIns + userPresets }
    var customCount: Int { userPresets.count }

    private static let defaultURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aula S98 Pro Companion", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }()
    private let url: URL?
    private static let schemaVersion = 2
    private static let maximumImportBytes = 1_048_576
    private var readOnlyError: PresetStoreError?
    private var readOnlyData: Data?

    init(storageURL: URL? = PresetStore.defaultURL) {
        self.url = storageURL
        load()
    }

    func load() {
        isReadOnly = false; readOnlyError = nil; readOnlyData = nil
        guard let url, let data = try? Data(contentsOf: url) else {
            userPresets = []
            lastError = nil
            return
        }

        let decoder = JSONDecoder()
        if let header = try? decoder.decode(PresetSchemaHeader.self, from: data),
           !(1...Self.schemaVersion).contains(header.schemaVersion) {
            readOnlyError = .unsupportedSchema(header.schemaVersion)
            readOnlyData = data
            isReadOnly = true
            lastError = readOnlyError?.localizedDescription
            // Known fields may be displayed, but an unfamiliar future preset shape
            // must remain protected even when the current decoder cannot read it.
            userPresets = (try? decoder.decode(PresetFile.self, from: data))?
                .presets.compactMap(Self.sanitizeStored) ?? []
            return
        }
        if let file = try? decoder.decode(PresetFile.self, from: data) {
            lastError = nil
            userPresets = file.presets.compactMap(Self.sanitizeStored)
            if file.schemaVersion != Self.schemaVersion { _ = save() }
            return
        }
        if let legacy = try? decoder.decode([Preset].self, from: data) {
            userPresets = legacy.filter { !Self.isLegacyBuiltIn($0) }
                .compactMap(Self.sanitizeStored)
            _ = save()
            alog("ok  migrated legacy presets to schema \(Self.schemaVersion)")
            return
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("presets-unreadable-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            lastError = "Presets were unreadable. A copy was kept as \(backup.lastPathComponent)."
            alog("ERR presets unreadable; kept a copy at \(backup.path)")
        } catch {
            lastError = "Presets were unreadable and could not be backed up: \(error.localizedDescription)"
            alog("ERR \(lastError!)")
        }
        userPresets = []
    }

    @discardableResult
    private func save() -> Bool {
        guard canMutate() else { return false }
        guard let url else { return true }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(PresetFile(schemaVersion: Self.schemaVersion,
                                                 presets: userPresets))
            try data.write(to: url, options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = PresetStoreError.saveFailed(error.localizedDescription).localizedDescription
            alog("ERR \(lastError!)")
            return false
        }
    }

    @discardableResult
    func add(_ preset: Preset) -> Bool {
        guard canMutate() else { return false }
        guard var clean = Self.sanitizeStored(preset) else { return false }
        clean.id = UUID(); clean.isBuiltIn = false
        let previous = userPresets
        userPresets.append(clean)
        guard save() else { userPresets = previous; return false }
        return true
    }

    @discardableResult
    func delete(_ preset: Preset) -> Bool {
        guard canMutate() else { return false }
        guard !preset.isBuiltIn else { return false }
        let previous = userPresets
        userPresets.removeAll { $0.id == preset.id }
        guard save() else { userPresets = previous; return false }
        return true
    }

    @discardableResult
    func rename(_ preset: Preset, to name: String) -> Bool {
        guard canMutate() else { return false }
        guard !preset.isBuiltIn,
              let index = userPresets.firstIndex(where: { $0.id == preset.id }) else { return false }
        let cleanName = Self.cleanName(name)
        guard !cleanName.isEmpty else { return false }
        let previous = userPresets
        userPresets[index].name = cleanName
        guard save() else { userPresets = previous; return false }
        return true
    }

    @discardableResult
    func update(_ preset: Preset, with replacement: Preset) -> Bool {
        guard canMutate() else { return false }
        guard !preset.isBuiltIn,
              let index = userPresets.firstIndex(where: { $0.id == preset.id }),
              var clean = Self.sanitizeStored(replacement) else { return false }
        clean.id = preset.id; clean.name = preset.name; clean.isBuiltIn = false
        let previous = userPresets
        userPresets[index] = clean
        guard save() else { userPresets = previous; return false }
        return true
    }

    /// Exported so the user can share a preset file.
    func exportJSON() -> Data? {
        if let readOnlyData { return readOnlyData }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(PresetFile(schemaVersion: Self.schemaVersion,
                                          presets: userPresets))
    }

    func importJSON(_ data: Data) -> Result<Int, PresetStoreError> {
        if let readOnlyError { return .failure(readOnlyError) }
        guard data.count <= Self.maximumImportBytes else { return .failure(.fileTooLarge) }
        let decoder = JSONDecoder()
        if let header = try? decoder.decode(PresetSchemaHeader.self, from: data),
           !(1...Self.schemaVersion).contains(header.schemaVersion) {
            return .failure(.unsupportedSchema(header.schemaVersion))
        }
        let decoded: [Preset]
        if let file = try? decoder.decode(PresetFile.self, from: data) {
            decoded = file.presets
        } else if let legacy = try? decoder.decode([Preset].self, from: data) {
            decoded = legacy.filter { !Self.isLegacyBuiltIn($0) }
        } else {
            return .failure(.unreadable)
        }
        let clean = decoded.compactMap(Self.sanitizeStored)
        guard !clean.isEmpty else { return .failure(.noValidPresets) }
        let previous = userPresets
        userPresets.append(contentsOf: clean.map {
            var copy = $0; copy.id = UUID(); copy.isBuiltIn = false; return copy
        })
        guard save() else {
            userPresets = previous
            return .failure(.saveFailed(lastError ?? "unknown error"))
        }
        return .success(clean.count)
    }

    private func canMutate() -> Bool {
        guard let readOnlyError else { return true }
        lastError = readOnlyError.localizedDescription
        return false
    }

    private static func cleanName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    private static func sanitizeStored(_ preset: Preset) -> Preset? {
        var copy = preset
        copy.name = cleanName(copy.name)
        guard !copy.name.isEmpty else { return nil }
        copy.state = copy.state.normalized
        if !copy.isPerKey && !(0...19).contains(copy.state.mode) { return nil }
        let validLEDs = Set(kLedIndices)
        copy.keys = copy.keys.filter { validLEDs.contains($0.key) }
        copy.isBuiltIn = false
        return copy
    }

    private static func isLegacyBuiltIn(_ preset: Preset) -> Bool {
        guard !preset.isPerKey else { return false }
        let signatures: [(String, RGB8, Set<Int>)] = [
            ("Green Static", RGB8(r: 0, g: 255, b: 0), [1]),
            ("Warm Amber", RGB8(r: 255, g: 110, b: 0), [1]),
            ("Cyan Breathe", RGB8(r: 0, g: 220, b: 255), [4, 7]),
            ("Rainbow Wave", RGB8(r: 255, g: 0, b: 0), [6, 10]),
            ("Magenta Stars", RGB8(r: 255, g: 0, b: 200), [2, 4]),
        ]
        return signatures.contains {
            preset.name == $0.0 && preset.state.color == $0.1 && $0.2.contains(preset.state.mode)
        }
    }

    static var builtIns: [Preset] {
        func eff(_ id: String, _ name: String, _ mode: Int, _ color: RGB8,
                 speed: Int = 3) -> Preset {
            var s = LightState(); s.mode = mode; s.color = color; s.speed = speed
            return Preset(id: UUID(uuidString: id)!, name: name, state: s, isBuiltIn: true)
        }
        return [
            eff("A11A0001-0000-4000-8000-000000000001", "Green Static", 1,
                RGB8(r: 0, g: 255, b: 0)),
            eff("A11A0001-0000-4000-8000-000000000002", "Warm Amber", 1,
                RGB8(r: 255, g: 110, b: 0)),
            eff("A11A0001-0000-4000-8000-000000000003", "Cyan Breathe", 7,
                RGB8(r: 0, g: 220, b: 255)),
            eff("A11A0001-0000-4000-8000-000000000004", "Rainbow Wave", 10,
                RGB8(r: 255, g: 0, b: 0), speed: 4),
            eff("A11A0001-0000-4000-8000-000000000005", "Magenta Stars", 4,
                RGB8(r: 255, g: 0, b: 200)),
        ]
    }
}

// MARK: - Painting helpers (the "extras")

enum Paint {
    static func hsv(_ h: Double, _ s: Double = 1, _ v: Double = 1) -> RGB8 {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        var r = 0.0, g = 0.0, b = 0.0
        switch h {
        case ..<60:   r = c; g = x
        case ..<120:  r = x; g = c
        case ..<180:  g = c; b = x
        case ..<240:  g = x; b = c
        case ..<300:  r = x; b = c
        default:      r = c; b = x
        }
        return RGB8(r: UInt8((r + m) * 255), g: UInt8((g + m) * 255), b: UInt8((b + m) * 255))
    }

    static func solid(_ c: RGB8) -> [Int: RGB8] {
        Dictionary(uniqueKeysWithValues: kKeyCaps.map { ($0.id, c) })
    }

    /// Hue swept left-to-right across the physical keyboard.
    static func rainbowHorizontal() -> [Int: RGB8] {
        let w = max(1, kLayoutSize.width)
        return Dictionary(uniqueKeysWithValues: kKeyCaps.map {
            ($0.id, hsv(Double(($0.x + $0.w / 2) / w) * 360))
        })
    }

    /// Two-colour linear gradient across the keyboard.
    static func gradient(_ a: RGB8, _ b: RGB8) -> [Int: RGB8] {
        let w = max(1, kLayoutSize.width)
        return Dictionary(uniqueKeysWithValues: kKeyCaps.map { k in
            let t = (k.x + k.w / 2) / w
            return (k.id, RGB8(r: UInt8(Double(a.r) + (Double(b.r) - Double(a.r)) * t),
                               g: UInt8(Double(a.g) + (Double(b.g) - Double(a.g)) * t),
                               b: UInt8(Double(a.b) + (Double(b.b) - Double(a.b)) * t)))
        })
    }

    static func random() -> [Int: RGB8] {
        Dictionary(uniqueKeysWithValues: kKeyCaps.map {
            ($0.id, hsv(Double.random(in: 0..<360)))
        })
    }
}
