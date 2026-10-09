import Foundation
import Testing
@testable import NotProtonApp

@Suite("Per-game runtime migration and rollback")
struct RuntimeMigrationTests {
    private struct Fixture {
        let directory: URL
        let prefix: WinePrefix
        let config: URL
        let originalConfig: Data
        let oldRecord = Data("freewine-26.3_1\nOld engine\n".utf8)
        let tool = InstalledTool(tool: RuntimeCatalog.packages[0].build.tools[0], build: "freewine-26.3_2")
        init() throws {
            let fm = FileManager.default
            directory = fm.temporaryDirectory.appending(path: "np-migration-\(UUID().uuidString)")
            prefix = WinePrefix(appID: "1017900", name: "Test game", library: .init(root: directory, volume: nil), lastUsed: nil)
            config = directory.appending(path: "config.vdf")
            originalConfig = Data("""
            // unrelated bytes must survive
            "InstallConfigStore" { "Software" { "Valve" { "Steam" {
              "Other" "keep \\\"quoted\\\" text"
              "CompatToolMapping" { "0" { "name" "default" } "1017900" { "name" "notproton-freewine" } "42" { "name" "other" } }
            } } } }
            "Elsewhere" { "keep" "yes" }
            """.utf8)
            try fm.createDirectory(at: prefix.pfx, withIntermediateDirectories: true)
            try Data("old saves and registry".utf8).write(to: prefix.pfx.appending(path: "user.reg"))
            try oldRecord.write(to: prefix.root.appending(path: PrefixTools.buildRecordName))
            try originalConfig.write(to: config)
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
        func rebuild(_ prefix: WinePrefix, _ tool: InstalledTool) throws {
            try Data("candidate state".utf8).write(to: prefix.pfx.appending(path: "user.reg"))
            try PrefixTools.writeBuildRecord(tool, for: prefix)
        }
    }

    @Test("Migration changes one selection; rollback restores its selection and old prefix while retaining the candidate")
    func migrateAndRestore() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let backup = try RuntimeMigration.migrate(f.prefix, to: f.tool, config: f.config, steamRunning: { false }, rebuild: f.rebuild)
        let text = try String(contentsOf: f.config, encoding: .utf8)
        #expect(try SteamToolSelection.mapping("1017900", in: text)?.contains("notproton-freewine-26.3_2") == true)
        #expect(text.contains("\"42\" { \"name\" \"other\" }"))
        #expect(text.contains("\"0\" { \"name\" \"default\" }"))
        #expect(PrefixTools.buildRecord(of: f.prefix)?.build == f.tool.build)
        #expect(throws: StepFailure.self) {
            try RuntimeMigration.restore(backup: backup, for: f.prefix, config: f.config, steamRunning: { false }, runtimeAvailable: { _ in false })
        }
        let retained = try #require(try RuntimeMigration.restore(backup: backup, for: f.prefix, config: f.config, steamRunning: { false }, runtimeAvailable: { _ in true }))
        #expect(try Data(contentsOf: f.config) == f.originalConfig)
        #expect(try Data(contentsOf: f.prefix.root.appending(path: PrefixTools.buildRecordName)) == f.oldRecord)
        #expect(try String(contentsOf: f.prefix.pfx.appending(path: "user.reg"), encoding: .utf8) == "old saves and registry")
        #expect(try String(contentsOf: retained.appending(path: "user.reg"), encoding: .utf8) == "candidate state")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test("Failed rebuild restores state and leaves Steam selection unchanged")
    func failedRebuild() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: StepFailure.self) {
            try RuntimeMigration.migrate(f.prefix, to: f.tool, config: f.config, steamRunning: { false }) { prefix, tool in
                try f.rebuild(prefix, tool)
                throw StepFailure(step: "fixture", detail: "wineboot failed")
            }
        }
        #expect(try Data(contentsOf: f.config) == f.originalConfig)
        #expect(PrefixTools.buildRecord(of: f.prefix)?.build == "freewine-26.3_1")
        #expect(try String(contentsOf: f.prefix.pfx.appending(path: "user.reg"), encoding: .utf8) == "old saves and registry")
        #expect(PrefixStore.backups(of: f.prefix).count == 2)
    }

    @Test("A running Steam client is refused before creating a backup")
    func runningClient() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: StepFailure.self) {
            try RuntimeMigration.migrate(f.prefix, to: f.tool, config: f.config, steamRunning: { true }, rebuild: f.rebuild)
        }
        #expect(PrefixStore.backups(of: f.prefix).isEmpty)
        #expect(try Data(contentsOf: f.config) == f.originalConfig)
    }

    @Test("Concurrent configuration changes are retained while the rebuilt prefix rolls back")
    func concurrentSelection() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let changed = String(decoding: f.originalConfig, as: UTF8.self) + "\n\"Concurrent\" \"retained\"\n"
        #expect(throws: StepFailure.self) {
            try RuntimeMigration.migrate(f.prefix, to: f.tool, config: f.config, steamRunning: { false }) { prefix, tool in
                try f.rebuild(prefix, tool)
                try Data(changed.utf8).write(to: f.config)
            }
        }
        #expect(try String(contentsOf: f.config, encoding: .utf8) == changed)
        #expect(PrefixTools.buildRecord(of: f.prefix)?.build == "freewine-26.3_1")
        #expect(try String(contentsOf: f.prefix.pfx.appending(path: "user.reg"), encoding: .utf8) == "old saves and registry")
    }

    @Test("An interrupted swap with only a backup remains discoverable and restorable")
    func interruptedSwap() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let backup = try RuntimeMigration.migrate(f.prefix, to: f.tool, config: f.config, steamRunning: { false }, rebuild: f.rebuild)
        try FileManager.default.removeItem(at: f.prefix.pfx)
        #expect(PrefixStore.all(libraries: [f.prefix.library]).map(\.appID) == [f.prefix.appID])
        #expect(try RuntimeMigration.restore(backup: backup, for: f.prefix, config: f.config, steamRunning: { false }, runtimeAvailable: { _ in true }) == nil)
        #expect(try String(contentsOf: f.prefix.pfx.appending(path: "user.reg"), encoding: .utf8) == "old saves and registry")
        #expect(try Data(contentsOf: f.config) == f.originalConfig)
    }

    @Test("Absent per-game mappings restore inheritance and duplicate sections fail safely")
    func inheritedMapping() throws {
        let original = "\"InstallConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"Keep\" \"yes\" } } } }"
        let added = try SteamToolSelection.replacing("1017900", mapping: "\"1017900\" { \"name\" \"new\" }", in: original)
        let removed = try SteamToolSelection.replacing("1017900", mapping: nil, in: added)
        #expect(try SteamToolSelection.mapping("1017900", in: removed) == nil)
        #expect(removed.contains("\"Keep\" \"yes\""))
        #expect(throws: StepFailure.self) { try SteamToolSelection.mapping("42", in: "\"InstallConfigStore\" {} \"InstallConfigStore\" {}") }
        #expect(throws: StepFailure.self) { try SteamToolSelection.replacing("1017900", mapping: "\"42\" {}", in: original) }
    }
}
