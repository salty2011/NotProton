import Foundation
import Darwin

/// Explicit per-game migration and rollback. Whole old prefixes are retained.
enum RuntimeMigration {
    private static let stateName = ".notproton-rollback.json"
    private struct State: Codable {
        let schemaVersion: Int
        let appID: String
        let buildRecord: Data?
        let selectionRecorded: Bool
        let mapping: String?
        let resolvedBuild: String?
    }

    static func annotate(backup: URL, for prefix: WinePrefix) throws {
        let record = prefix.root.appending(path: PrefixTools.buildRecordName)
        let state = State(schemaVersion: 1, appID: prefix.appID,
            buildRecord: FileManager.default.fileExists(atPath: record.path) ? try Data(contentsOf: record) : nil,
            selectionRecorded: false, mapping: nil, resolvedBuild: PrefixTools.lastBuild(of: prefix)?.build)
        try JSONEncoder().encode(state).write(to: backup.appending(path: stateName), options: .atomic)
    }

    private static func preflight(_ prefix: WinePrefix, steamRunning: () -> Bool) throws {
        guard !steamRunning(), !PrefixStore.isInUse(prefix) else {
            throw StepFailure(step: "Change runtime", detail: "Quit the game and Steam before changing its runtime or restoring its prefix.")
        }
        if FileManager.default.fileExists(atPath: prefix.pfx.path),
           try prefix.pfx.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw StepFailure(step: "Change runtime", detail: "The game's prefix is a symbolic link. Use a real prefix directory for backed-up migration and restoration.")
        }
    }

    @discardableResult
    static func migrate(
        _ prefix: WinePrefix, to tool: InstalledTool, config: URL = SteamToolSelection.file,
        steamRunning: () -> Bool = { SteamBundle.isRunning },
        currentTool: (WinePrefix) -> InstalledTool? = {
            guard let record = PrefixTools.lastBuild(of: $0), !record.build.isEmpty else { return nil }
            return PrefixTools.tool(for: $0)
        },
        rebuild: (WinePrefix, InstalledTool) throws -> Void = { _ = try PrefixTools.recreate($0, as: $1, keepBackup: false) }
    ) throws -> URL {
        try preflight(prefix, steamRunning: steamRunning)
        let lock = try DeploymentContent.acquireInstallationLock(for: config)
        defer { close(lock) }
        let original = try Data(contentsOf: config)
        guard let text = String(data: original, encoding: .utf8) else {
            throw StepFailure(step: "Change runtime", detail: "Steam's configuration is not readable UTF-8.")
        }
        let next = try SteamToolSelection.replacing(prefix.appID, mapping: SteamToolSelection.mapping(prefix.appID, tool: tool), in: text)
        let record = prefix.root.appending(path: PrefixTools.buildRecordName)
        let previousTool = currentTool(prefix)
        let previousMapping = try SteamToolSelection.mapping(prefix.appID, in: text)
        let state = State(schemaVersion: 1, appID: prefix.appID,
            buildRecord: FileManager.default.fileExists(atPath: record.path) ? try Data(contentsOf: record) : nil,
            selectionRecorded: previousMapping != nil || previousTool != nil,
            // Snapshot the effective engine for inherited selections. Steam's
            // default may change before rollback; never rewrite that global default.
            mapping: try previousMapping ?? previousTool.map { try SteamToolSelection.mapping(prefix.appID, tool: $0) },
            resolvedBuild: previousTool?.build ?? PrefixTools.lastBuild(of: prefix)?.build)
        let backup = try PrefixTools.backUp(prefix)
        var attemptedRebuild = false
        do {
            try JSONEncoder().encode(state).write(to: backup.appending(path: stateName), options: .atomic)
            attemptedRebuild = true
            try rebuild(prefix, tool)
            guard try Data(contentsOf: config) == original, !steamRunning() else {
                throw StepFailure(step: "Change runtime", detail: "Steam's configuration changed during migration. Retry with Steam closed.")
            }
            try atomicReplace(config, with: Data(next.utf8), step: "Select runtime")
            return backup
        } catch {
            guard attemptedRebuild else { throw error }
            // Keep the original backup and the failed candidate for inspection.
            // Do not rewrite a concurrently changed Steam configuration.
            do { _ = try restore(backup: backup, for: prefix, config: config, restoreMapping: false, steamRunning: steamRunning) }
            catch let rollback {
                throw StepFailure(step: "Change runtime", detail: "Migration failed: \(error.localizedDescription). Restore \(backup.path) after stopping Steam. Rollback failed: \(rollback.localizedDescription)")
            }
            throw error
        }
    }

    @discardableResult
    static func restore(
        backup: URL, for prefix: WinePrefix, config: URL = SteamToolSelection.file,
        restoreMapping: Bool = true, steamRunning: () -> Bool = { SteamBundle.isRunning },
        runtimeAvailable: (String) -> Bool = { id in CompatToolList.installed().contains { $0.build == id } },
        selectedBuild: (String) -> String? = { name in CompatToolList.installed().first { $0.tool.name == name }?.build }
    ) throws -> URL? {
        try preflight(prefix, steamRunning: steamRunning)
        let lock = restoreMapping ? try DeploymentContent.acquireInstallationLock(for: config) : nil
        defer { if let lock { close(lock) } }
        let fm = FileManager.default
        guard PrefixStore.backups(of: prefix).contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == backup.resolvingSymlinksInPath().standardizedFileURL.path }),
              try backup.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]).isSymbolicLink != true else {
            throw StepFailure(step: "Restore prefix", detail: "Select a retained backup belonging to this game.")
        }
        let stateURL = backup.appending(path: stateName)
        let state = fm.fileExists(atPath: stateURL.path) ? try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) : nil
        if let state, state.schemaVersion != 1 || state.appID != prefix.appID {
            throw StepFailure(step: "Restore prefix", detail: "This backup belongs to another game or format.")
        }
        if restoreMapping, state?.selectionRecorded != true || (state?.mapping == nil && state?.buildRecord == nil && state?.resolvedBuild == nil) {
            throw StepFailure(step: "Restore prefix", detail: "This older backup has no runtime selection record. Use Restore Prefix Only, then select its original runtime in Steam.")
        }
        let savedBuild = state?.resolvedBuild ?? state?.buildRecord.flatMap { String(data: $0, encoding: .utf8)?.split(separator: "\n").first.map(String.init) }
        if restoreMapping, savedBuild?.isEmpty != false {
            throw StepFailure(step: "Restore prefix", detail: "This backup has no verified runtime identity. Use Restore Prefix Only, then select its original runtime in Steam.")
        }
        if restoreMapping, let build = savedBuild, !runtimeAvailable(build) {
            throw StepFailure(step: "Restore prefix", detail: "The backup needs runtime \(build), which is no longer installed. Reinstall that revision before restoring its prefix and selection.")
        }
        if restoreMapping, let build = savedBuild, let mapping = state?.mapping,
           let name = try SteamToolSelection.name(prefix.appID, inMapping: mapping), selectedBuild(name) != build {
            throw StepFailure(step: "Restore prefix", detail: "The retained tool name \(name) no longer selects runtime \(build). Use Restore Prefix Only, then choose that installed revision explicitly in Steam.")
        }
        let originalConfig = restoreMapping ? try Data(contentsOf: config) : nil
        if let originalConfig, String(data: originalConfig, encoding: .utf8) == nil {
            throw StepFailure(step: "Restore prefix", detail: "Steam's configuration is not readable UTF-8.")
        }
        let nextConfig: Data?
        if let originalConfig, let text = String(data: originalConfig, encoding: .utf8), let state {
            nextConfig = Data(try SteamToolSelection.replacing(prefix.appID, mapping: state.mapping, in: text).utf8)
        } else { nextConfig = nil }
        let record = prefix.root.appending(path: PrefixTools.buildRecordName)
        let oldRecord = fm.fileExists(atPath: record.path) ? try Data(contentsOf: record) : nil
        let fresh = prefix.root.appending(path: ".restore-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: fresh) }
        try fm.copyItem(at: backup, to: fresh)
        if fm.fileExists(atPath: fresh.appending(path: stateName).path) { try fm.removeItem(at: fresh.appending(path: stateName)) }
        let retained = fm.fileExists(atPath: prefix.pfx.path) ? try PrefixTools.backUp(prefix) : nil
        if let retained {
            let currentMapping = try originalConfig.flatMap { data -> String? in
                guard let text = String(data: data, encoding: .utf8) else { return nil }
                return try SteamToolSelection.mapping(prefix.appID, in: text)
            }
            let retainedState = State(schemaVersion: 1, appID: prefix.appID, buildRecord: oldRecord,
                selectionRecorded: originalConfig != nil, mapping: currentMapping, resolvedBuild: PrefixTools.lastBuild(of: prefix)?.build)
            try JSONEncoder().encode(retainedState).write(to: retained.appending(path: stateName), options: .atomic)
        }
        do {
            if fm.fileExists(atPath: prefix.pfx.path) { try fm.removeItem(at: prefix.pfx) }
            try fm.moveItem(at: fresh, to: prefix.pfx)
            if let state {
                if let data = state.buildRecord { try atomicReplace(record, with: data, step: "Restore runtime identity") }
                else if fm.fileExists(atPath: record.path) { try fm.removeItem(at: record) }
            } else if fm.fileExists(atPath: record.path) { try fm.removeItem(at: record) }
            if let nextConfig, let originalConfig {
                guard try Data(contentsOf: config) == originalConfig, !steamRunning() else {
                    throw StepFailure(step: "Restore prefix", detail: "Steam's configuration changed during restoration. Retry with Steam closed.")
                }
                try atomicReplace(config, with: nextConfig, step: "Restore runtime selection")
            }
        } catch {
            if let retained {
                do {
                    if fm.fileExists(atPath: prefix.pfx.path) { try fm.removeItem(at: prefix.pfx) }
                    try fm.copyItem(at: retained, to: prefix.pfx)
                    if let oldRecord { try atomicReplace(record, with: oldRecord, step: "Restore previous identity") }
                    else if fm.fileExists(atPath: record.path) { try fm.removeItem(at: record) }
                } catch let rollback {
                    throw StepFailure(step: "Restore prefix", detail: "Restoration failed: \(error.localizedDescription). Previous prefix retained at \(retained.path). Rollback failed: \(rollback.localizedDescription)")
                }
            }
            throw error
        }
        return retained
    }
}
