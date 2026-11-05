import Foundation

@MainActor
enum LegacyDataMigrationTests {
    static func run(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("AulaCompanion-migration-\(UUID().uuidString)", isDirectory: true)
        let suite = "aula-migration-tests-\(UUID().uuidString)"
        defer {
            try? manager.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "migration test could not create a defaults suite")
            return
        }
        let old = root.appendingPathComponent(LegacyDataMigration.legacyFolderName)
        let new = root.appendingPathComponent(LegacyDataMigration.folderName)
        try? manager.createDirectory(at: old, withIntermediateDirectories: true)
        try? manager.createDirectory(at: new, withIntermediateDirectories: true)
        try? Data("old presets".utf8).write(to: old.appendingPathComponent("presets.json"))
        try? Data("old labels".utf8).write(to: old.appendingPathComponent("mode-labels.json"))
        try? Data("newer labels".utf8).write(to: new.appendingPathComponent("mode-labels.json"))
        defaults.set(false, forKey: "timeSyncEnabled")

        let legacy: [String: Any] = [
            "workspace.v1": Data("workspace".utf8),
            "timeSyncEnabled": true,
            "NSWindow Frame AulaRGB.main-editor": "1 2 3 4",
        ]
        LegacyDataMigration.runOnce(applicationSupport: root, defaults: defaults, legacyDefaults: legacy)

        func text(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
        }
        expect(text(new.appendingPathComponent("presets.json")) == "old presets",
               "migration copies saved presets into the new folder")
        expect(text(old.appendingPathComponent("presets.json")) == "old presets",
               "migration leaves the old folder intact")
        expect(text(new.appendingPathComponent("mode-labels.json")) == "newer labels",
               "migration never overwrites a file already in the new folder")
        expect(defaults.data(forKey: "workspace.v1") == Data("workspace".utf8),
               "migration copies the saved workspace")
        expect(defaults.object(forKey: "timeSyncEnabled") as? Bool == false,
               "migration never overwrites a newer preference")
        expect(defaults.string(forKey: "NSWindow Frame AulaCompanion.main-editor") == "1 2 3 4",
               "migration carries the editor window's position to its new key")

        defaults.removeObject(forKey: "workspace.v1")
        LegacyDataMigration.runOnce(applicationSupport: root, defaults: defaults, legacyDefaults: legacy)
        expect(defaults.data(forKey: "workspace.v1") == nil, "migration runs only once")
    }
}
