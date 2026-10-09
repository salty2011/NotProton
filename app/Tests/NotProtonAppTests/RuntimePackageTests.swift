import Foundation
import Testing
@testable import NotProtonApp

@Suite("Catalog-approved runtime packages")
struct RuntimePackageTests {
    private func prepareFixture(_ build: RunnerBuild, _ runners: URL, _ bridge: URL, _ list: URL, _ tools: URL) throws -> RunnerSetup.Outcome {
        let fm = FileManager.default
        for path in [bridge.appending(path: "wine/\(build.id)/staged"), tools.appending(path: "\(build.tools[0].name)/run")] {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("prepared fixture".utf8).write(to: path)
        }
        return .init(build: build, staged: [], installed: .init(), toolsChanged: true)
    }
    private struct Fixture {
        let directory: URL
        let archive: URL
        let package: RuntimePackage
        init() throws {
            let fm = FileManager.default
            directory = fm.temporaryDirectory.appending(path: "np-package-test-\(UUID().uuidString)")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload = directory.appending(path: "payload")
            let wine = payload.appending(path: "Wine")
            let paths = ["lib/wine/x86_64-unix/wine", "bin/wineserver", "lib/wine/x86_64-unix/ntdll.so",
                         "lib/wine/x86_64-unix/lsteamclient.so", "lib/wine/i386-windows/ntdll.dll",
                         "lib/wine/x86_64-windows/ntdll.dll", "lib/wine/i386-windows/lsteamclient.dll",
                         "lib/wine/x86_64-windows/lsteamclient.dll"]
            var files: [String: RuntimePackage.File] = [:]
            var critical: [String: String] = [:]
            for path in paths {
                let file = wine.appending(path: path)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = Data("fixture \(path)".utf8)
                try data.write(to: file)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
                let hash = Digest.sha256(of: data)
                files[path] = .init(kind: "file", sha256: hash, mode: 0o755, target: nil)
                critical[path] = hash
            }
            let descriptor = RuntimePackage.Descriptor(schemaVersion: 1, id: "freewine-26.3_2",
                displayVersion: "Test fixture", hostArchitecture: "x86_64", windowsArchitectures: ["i386", "x86_64"],
                minimumAppVersion: "1.1.3", minimumMacOSVersion: "14.0", bridgeABI: "freewine-26.3_2",
                files: files, criticalFiles: critical,
                capabilities: ["automatic": "dxmt+d9vk", "d3dmetal": "unavailable", "fex": "unavailable"],
                distributionReady: false)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(descriptor)
            try data.write(to: payload.appending(path: "package.json"))
            archive = directory.appending(path: "freewine-26.3_2.tar.xz")
            let tar = try Shell.run("/usr/bin/tar", ["-cJf", archive.path, "-C", payload.path, "package.json", "Wine"])
            #expect(tar.succeeded)
            package = .init(id: descriptor.id, file: archive.lastPathComponent, sha256: try Digest.sha256(of: archive),
                            size: (try fm.attributesOfItem(atPath: archive.path)[.size] as! NSNumber).int64Value,
                            descriptorSHA256: Digest.sha256(of: data), descriptor: descriptor)
        }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test("Bundled package identities are validated and preserve the old runtime")
    func bundledCatalog() throws {
        #expect(RuntimeCatalog.packages.count == 1)
        let package = try #require(RuntimeCatalog.packages.first)
        try package.validate()
        #expect(package.id == "freewine-26.3_2")
        #expect(!package.descriptor.distributionReady)
        #expect(SupportedRunners.build(id: "freewine-26.3_1") != nil)
        #expect(SupportedRunners.build(id: package.id)?.tools.first?.name == "notproton-freewine-26.3_2")
        #expect(SupportedRunners.build(loaderSHA256: package.build.loaderSHA256)?.id == "freewine-26.3_1")
        #expect(SupportedRunners.build(id: package.id)?.id == package.id)
    }

    @Test("Archive tampering is refused before creating an engine")
    func modifiedArchive() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try Data("unapproved".utf8).write(to: fixture.archive)
        let runners = fixture.directory.appending(path: "runners")
        #expect(throws: StepFailure.self) {
            try RuntimePackageInstaller.install(archive: fixture.archive, package: fixture.package, runners: runners)
        }
        #expect(!FileManager.default.fileExists(atPath: runners.path))
    }

    @Test("Setup failure leaves existing tools, bridges and engines intact")
    func preparationFailure() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let runners = fixture.directory.appending(path: "runners")
        let bridge = fixture.directory.appending(path: "bridge")
        let tools = fixture.directory.appending(path: "tools")
        let existing = Data("existing tool records\n".utf8)
        try existing.write(to: tools)
        var prepared = false
        #expect(throws: StepFailure.self) {
            try RuntimePackageInstaller.install(archive: fixture.archive, package: fixture.package,
                runners: runners, bridge: bridge, toolList: tools,
                compatTools: fixture.directory.appending(path: "compatibilitytools.d"),
                prepare: { _, _, _, _, _ in
                    prepared = true
                    throw StepFailure(step: "Fixture", detail: "setup failed")
                })
        }
        #expect(prepared)
        #expect(try Data(contentsOf: tools) == existing)
        #expect(!FileManager.default.fileExists(atPath: SupportPaths.runnerRoot(forBuild: fixture.package.id, runners: runners).path))
        #expect(!FileManager.default.fileExists(atPath: bridge.path))
    }

    @Test("Registration failure rolls back already moved files")
    func registrationFailure() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let runners = fixture.directory.appending(path: "runners")
        let bridge = fixture.directory.appending(path: "bridge")
        let tools = fixture.directory.appending(path: "compatibilitytools.d")
        let blocked = fixture.directory.appending(path: "blocked")
        try Data("not a directory".utf8).write(to: blocked)
        #expect(throws: (any Error).self) {
            try RuntimePackageInstaller.install(archive: fixture.archive, package: fixture.package,
                runners: runners, bridge: bridge, toolList: blocked.appending(path: "tools"), compatTools: tools,
                prepare: prepareFixture)
        }
        #expect(!FileManager.default.fileExists(atPath: SupportPaths.runnerRoot(forBuild: fixture.package.id, runners: runners).path))
        #expect(!FileManager.default.fileExists(atPath: bridge.appending(path: "wine/\(fixture.package.id)").path))
        #expect(!FileManager.default.fileExists(atPath: tools.appending(path: "notproton-\(fixture.package.id)").path))
        #expect(try String(contentsOf: blocked, encoding: .utf8) == "not a directory")
    }

    @Test("Payload verification refuses an added file and changed bridge")
    func alteredPayload() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let payload = fixture.directory.appending(path: "payload")
        try fixture.package.verifyPayload(at: payload)
        try Data("other engine".utf8).write(to: payload.appending(path: "Wine/lib/wine/x86_64-unix/lsteamclient.so"))
        #expect(throws: StepFailure.self) { try fixture.package.verifyPayload(at: payload) }
    }

    @Test("Real package installs and prepares without an installed runtime", .enabled(if: ProcessInfo.processInfo.environment["NP_FREE_RUNTIME_PACKAGE"] != nil))
    func realPackage() throws {
        let source = try #require(ProcessInfo.processInfo.environment["NP_FREE_RUNTIME_PACKAGE"])
        let package = try #require(RuntimeCatalog.package(id: "freewine-26.3_2"))
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "np-free-package-integration-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let runners = dir.appending(path: "runners")
        let bridge = dir.appending(path: "bridge")
        let list = dir.appending(path: "tools")
        let tools = dir.appending(path: "compatibilitytools.d")
        let outcome = try RuntimePackageInstaller.install(archive: URL(filePath: source), package: package,
            runners: runners, bridge: bridge, toolList: list, compatTools: tools)
        #expect(outcome.build.id == package.id)
        let root = SupportPaths.clonedRoot(forBuild: package.id, runners: runners)
        #expect(package.problems(in: root).isEmpty)
        #expect(RunnerPatcher.verify(build: package.build, root: root, bridge: bridge).isEmpty)
        try RunnerInstaller.verifyClone(build: package.build, root: root)
        #expect(CompatToolList.installed(runners: runners, file: list).map(\.build) == [package.id])
        #expect(fm.fileExists(atPath: tools.appending(path: "notproton-\(package.id)/run").path))
        #expect(!fm.fileExists(atPath: runners.appending(path: "sikarugir-11.0_1").path))
    }
}
