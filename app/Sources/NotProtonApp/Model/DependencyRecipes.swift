import Foundation
import Darwin

struct DependencyRecipe: Codable, Sendable, Equatable {
    struct Requirement: Codable, Sendable, Equatable {
        let path: String
        let sha256: String?
    }
    let id: String
    let revision: Int
    let reason: String
    let evidence: String
    let appIDs: [String]
    let runtimes: [String]
    let architectures: [String]
    let requirements: [Requirement]
    let toolURL: URL
    let toolSHA256: String
    let verbs: [String]
}

/// Separately invoked preparation; markers never replace a presence check.
/// No real recipes are approved until a failing game proves a missing dependency.
enum DependencyRecipes {
    private struct Catalog: Decodable { let recipes: [DependencyRecipe] }
    static let all = (try? JSONDecoder().decode(Catalog.self, from: GameProfileCatalog.data).recipes) ?? []
    private struct Receipt: Codable { let schemaVersion: Int; let recipe: String; let revision: Int; let runtime: String }
    struct Outcome: Sendable { let alreadySatisfied: Bool; let backup: URL? }

    private static func validate(_ recipe: DependencyRecipe) throws {
        func token(_ value: String) -> Bool {
            !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
        guard token(recipe.id), recipe.revision > 0, !recipe.reason.isEmpty, !recipe.evidence.isEmpty,
              !recipe.requirements.isEmpty, recipe.toolURL.scheme == "https", recipe.toolSHA256.count == 64,
              recipe.toolSHA256.allSatisfy({ "0123456789abcdef".contains($0) }),
              !recipe.verbs.isEmpty, recipe.verbs.allSatisfy(token),
              recipe.requirements.allSatisfy({ item in
                  !item.path.hasPrefix("/") && !item.path.contains("\\") && !item.path.split(separator: "/").contains("..")
                    && item.path.hasPrefix("drive_c/") && (item.sha256 == nil || item.sha256?.count == 64)
              }) else { throw StepFailure(step: "Prepare game dependencies", detail: "Invalid approved dependency recipe.") }
    }

    static func satisfied(_ recipe: DependencyRecipe, in prefix: WinePrefix) -> Bool {
        recipe.requirements.allSatisfy { item in
            let file = prefix.pfx.appending(path: item.path)
            // Do not accept a host file masquerading as an installed module.
            let root = prefix.pfx.resolvingSymlinksInPath().path
            guard file.resolvingSymlinksInPath().path.hasPrefix(root + "/"),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return false }
            return item.sha256.map { Digest.sha256IfPresent(file) == $0 } ?? true
        }
    }

    static func prepare(_ recipeID: String, for prefix: WinePrefix, report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Outcome {
        guard let recipe = all.first(where: { $0.id == recipeID }) else {
            throw StepFailure(step: "Prepare game dependencies", detail: "No approved recipe for this dependency. Let Steam run its install scripts first.")
        }
        try validate(recipe)
        guard let tool = PrefixTools.tool(for: prefix), let arch = PrefixStore.arch(of: prefix) else {
            throw StepFailure(step: "Prepare game dependencies", detail: "Select a working runtime and rebuild the prefix first.")
        }
        let architecture = arch == .x86_64 ? "x86_64" : arch == .i386 ? "i386" : "arm64"
        guard recipe.appIDs.contains(prefix.appID), recipe.runtimes.contains(tool.build), recipe.architectures.contains(architecture),
              !SteamBundle.isRunning, !PrefixStore.isInUse(prefix) else {
            throw StepFailure(step: "Prepare game dependencies", detail: "Quit Steam and the game, and select the matching runtime and architecture before preparation.")
        }
        if satisfied(recipe, in: prefix) {
            return try apply(recipe, for: prefix, runtime: tool.build, architecture: architecture, report: report) { _ in }
        }
        let script = try await PinnedDownload.obtain(file: recipe.toolURL.lastPathComponent, sha256: recipe.toolSHA256,
            bases: [recipe.toolURL.deletingLastPathComponent()], into: SupportPaths.home.appending(path: "Library/Caches/notproton/recipe-tools/\(recipe.toolSHA256)"),
            step: "Prepare game dependencies", sourceName: "the approved preparation tool", report: { report($0.label) })
        return try await Task.detached {
            try apply(recipe, for: prefix, runtime: tool.build, architecture: architecture, report: report) { prefix in
                var environment = PrefixTools.environment(prefix: prefix, runner: SupportPaths.clonedRoot(forBuild: tool.build), flavor: tool.tool.flavor)
                environment["WINE"] = PrefixTools.loader(runner: SupportPaths.clonedRoot(forBuild: tool.build), flavor: tool.tool.flavor).path
                defer {
                    _ = try? Shell.run(SupportPaths.clonedRoot(forBuild: tool.build).appending(path: "bin/wineserver").path, ["-k"], environment: environment)
                }
                _ = try Shell.check("/bin/sh", [script.path] + recipe.verbs, environment: environment)
            }
        }.value
    }

    static func apply(
        _ recipe: DependencyRecipe, for prefix: WinePrefix, runtime: String, architecture: String,
        steamRunning: () -> Bool = { SteamBundle.isRunning }, report: (String) -> Void = { _ in },
        installer: (WinePrefix) throws -> Void
    ) throws -> Outcome {
        try validate(recipe)
        guard recipe.appIDs.contains(prefix.appID), recipe.runtimes.contains(runtime), recipe.architectures.contains(architecture) else {
            throw StepFailure(step: "Prepare game dependencies", detail: "This recipe does not match this game's runtime and architecture.")
        }
        guard !steamRunning(), !PrefixStore.isInUse(prefix) else {
            throw StepFailure(step: "Prepare game dependencies", detail: "Quit the game and Steam before preparing its stopped prefix.")
        }
        let lock = try DeploymentContent.acquireInstallationLock(for: prefix.root)
        defer { close(lock) }
        report("Checking \(recipe.id) v\(recipe.revision): \(recipe.reason)")
        if satisfied(recipe, in: prefix) { return Outcome(alreadySatisfied: true, backup: nil) }
        report("Backing up the prefix before dependency preparation")
        let backup = try PrefixTools.backUp(prefix)
        try RuntimeMigration.annotate(backup: backup, for: prefix)
        do {
            report("Preparing \(recipe.id) v\(recipe.revision)")
            try installer(prefix)
            guard satisfied(recipe, in: prefix) else {
                throw StepFailure(step: "Prepare game dependencies", detail: "The installer completed but the required dependency is still absent.")
            }
            let receipt = Receipt(schemaVersion: 1, recipe: recipe.id, revision: recipe.revision, runtime: runtime)
            let directory = prefix.pfx.appending(path: ".notproton-recipes")
            if FileManager.default.fileExists(atPath: directory.path),
               try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw StepFailure(step: "Prepare game dependencies", detail: "Dependency receipts must remain inside the prefix.")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(receipt).write(to: directory.appending(path: recipe.id + ".json"), options: .atomic)
            report("Verified \(recipe.id) v\(recipe.revision)")
            return Outcome(alreadySatisfied: false, backup: backup)
        } catch {
            do { _ = try RuntimeMigration.restore(backup: backup, for: prefix, restoreMapping: false, steamRunning: steamRunning) }
            catch let rollback {
                throw StepFailure(step: "Prepare game dependencies", detail: "Preparation failed: \(error.localizedDescription). Original prefix retained at \(backup.path). Restore it after quitting Steam. Rollback failed: \(rollback.localizedDescription)")
            }
            throw error
        }
    }
}
