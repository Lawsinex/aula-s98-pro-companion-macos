import Foundation

/// The app used to be called AulaRGB. Presets, labels and settings saved under that
/// name are copied across once, on the first launch under the new name. The old
/// files and preferences are left where they are, so nothing can be lost if a copy
/// fails or someone goes back to the old build.
enum LegacyDataMigration {
    static let legacyBundleID = "local.aula.rgb"
    static let legacyFolderName = "AulaRGB"
    static let folderName = "Aula S98 Pro Companion"
    private static let doneKey = "legacyMigration.v1"
    private static let windowFrameKeys = [
        "NSWindow Frame AulaRGB.main-editor": "NSWindow Frame AulaCompanion.main-editor",
    ]

    static func runOnce(
        applicationSupport: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        defaults: UserDefaults = .standard,
        legacyDefaults: [String: Any]? = UserDefaults.standard
            .persistentDomain(forName: LegacyDataMigration.legacyBundleID)
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let filesCopied = copyFiles(from: applicationSupport.appendingPathComponent(legacyFolderName),
                                    to: applicationSupport.appendingPathComponent(folderName))
        for (key, value) in legacyDefaults ?? [:] {
            let newKey = windowFrameKeys[key] ?? key
            if defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
        // A failed copy is retried on the next launch rather than forgotten.
        if filesCopied { defaults.set(true, forKey: doneKey) }
    }

    /// Never overwrites: a file already in the new folder is newer than the old one.
    private static func copyFiles(from old: URL, to new: URL) -> Bool {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: old.path) else { return true }
        var succeeded = true
        for name in names where !name.hasPrefix(".") {
            let target = new.appendingPathComponent(name)
            guard !manager.fileExists(atPath: target.path) else { continue }
            do {
                try manager.createDirectory(at: new, withIntermediateDirectories: true)
                try manager.copyItem(at: old.appendingPathComponent(name), to: target)
            } catch {
                alog("ERR could not copy \(name) from the old app folder: \(error.localizedDescription)")
                succeeded = false
            }
        }
        return succeeded
    }
}
