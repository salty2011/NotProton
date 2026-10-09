import Foundation
import Testing
@testable import NotProtonApp

@Suite("Scoped dependency preparation")
struct DependencyRecipeTests {
    private struct Fixture {
        let root: URL
        let prefix: WinePrefix
        let recipe = DependencyRecipe(id: "fixture-library", revision: 1, reason: "Fixture missing library", evidence: "fixture only; no shipping game claim",
            appIDs: ["42"], runtimes: ["freewine-26.3_2"], architectures: ["x86_64"],
            requirements: [.init(path: "drive_c/windows/system32/fixture.dll", sha256: nil)],
            toolURL: URL(string: "https://example.invalid/pinned-winetricks")!, toolSHA256: String(repeating: "0", count: 64), verbs: ["fixture"])
        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "np-recipe-\(UUID().uuidString)")
            prefix = WinePrefix(appID: "42", name: "Fixture", library: .init(root: root, volume: nil), lastUsed: nil)
            try FileManager.default.createDirectory(at: prefix.pfx.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true)
            try Data("original registry".utf8).write(to: prefix.pfx.appending(path: "user.reg"))
            try Data("freewine-26.3_2\nFixture engine\n".utf8).write(to: prefix.root.appending(path: PrefixTools.buildRecordName))
        }
        var module: URL { prefix.pfx.appending(path: recipe.requirements[0].path) }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
        func install(_ prefix: WinePrefix) throws { try Data("fixture module".utf8).write(to: module) }
        func apply(architecture: String = "x86_64", installer: (WinePrefix) throws -> Void) throws -> DependencyRecipes.Outcome {
            try DependencyRecipes.apply(recipe, for: prefix, runtime: "freewine-26.3_2", architecture: architecture, steamRunning: { false }, installer: installer)
        }
    }

    @Test("Preparation is backed up, verified and idempotent; rebuild invalidates stale receipts")
    func successfulRetry() throws {
        let f = try Fixture(); defer { f.cleanup() }
        var attempts = 0
        let first = try f.apply { prefix in attempts += 1; try f.install(prefix) }
        #expect(!first.alreadySatisfied)
        #expect(first.backup != nil)
        let second = try f.apply { _ in attempts += 1 }
        #expect(second.alreadySatisfied)
        #expect(attempts == 1)
        try FileManager.default.removeItem(at: f.module)
        // Even a retained receipt cannot authorize an absent dependency.
        let third = try f.apply { prefix in attempts += 1; try f.install(prefix) }
        #expect(!third.alreadySatisfied)
        #expect(attempts == 2)
    }

    @Test("Installer failure or missing postcondition restores registry and retains recovery copies")
    func failedPreparation() throws {
        for installerFails in [true, false] {
            let f = try Fixture(); defer { f.cleanup() }
            #expect(throws: StepFailure.self) {
                try f.apply { prefix in
                    try Data("partial state".utf8).write(to: prefix.pfx.appending(path: "user.reg"))
                    if installerFails { throw StepFailure(step: "fixture", detail: "interrupted") }
                }
            }
            #expect(try String(contentsOf: f.prefix.pfx.appending(path: "user.reg"), encoding: .utf8) == "original registry")
            #expect(PrefixTools.buildRecord(of: f.prefix)?.build == "freewine-26.3_2")
            #expect(!FileManager.default.fileExists(atPath: f.module.path))
            #expect(PrefixStore.backups(of: f.prefix).count == 2)
            #expect(!FileManager.default.fileExists(atPath: f.prefix.pfx.appending(path: ".notproton-recipes/fixture-library.json").path))
        }
    }

    @Test("Architecture mismatch does not mutate; external links cannot satisfy a requirement")
    func preflightAndPresence() throws {
        let f = try Fixture(); defer { f.cleanup() }
        #expect(throws: StepFailure.self) { try f.apply(architecture: "i386", installer: f.install) }
        #expect(PrefixStore.backups(of: f.prefix).isEmpty)
        let external = f.root.appending(path: "host.dll")
        try Data("host file".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: f.module, withDestinationURL: external)
        #expect(!DependencyRecipes.satisfied(f.recipe, in: f.prefix))
    }

    @Test("No speculative dependency installer is enabled for working games")
    func emptyApprovedCatalog() {
        #expect(DependencyRecipes.all.isEmpty)
        #expect(GameProfiles.all.allSatisfy { $0.recipes.isEmpty })
    }
}
