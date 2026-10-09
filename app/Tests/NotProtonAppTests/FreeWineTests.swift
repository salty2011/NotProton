import Foundation
import Testing

@testable import NotProtonApp

@Suite("Source-built free Wine integration")
struct FreeWineTests {
    private let hooked = Data("already contains a Steam source hook".utf8)
    private var build: RunnerBuild {
        RunnerBuild(bundleVersion: "test-source", releaseVersion: "test", flavor: nil,
                    loaderSHA256: "", cleanNtdll: [.x86_64Windows: Digest.sha256(of: hooked)],
                    patchedNtdll: [.x86_64Windows: Digest.sha256(of: hooked)], provider: .freeWine)
    }

    @Test("Source staging preserves pre-hooked bytes without applying PE detours")
    func stagesSourceHook() throws {
        let dir = try scratchDirectory("source-hook")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try hooked.write(to: source)
        let bridge = dir.appending(path: "bridge")
        #expect(try NtdllPatcher.stage(build: build, runnerRoot: dir, bridge: bridge) == [.x86_64Windows])
        #expect(try Data(contentsOf: NtdllPatcher.stagedCopy(of: .x86_64Windows, build: build.id, in: bridge)) == hooked)
        #expect(try Data(contentsOf: source) == hooked)
        #expect(try NtdllPatcher.stage(build: build, runnerRoot: dir, bridge: bridge).isEmpty)
    }

    @Test("Mismatching source bytes cannot be staged as a qualified Steam hook")
    func rejectsUnknownSource() throws {
        let dir = try scratchDirectory("source-hook-reject")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unqualified".utf8).write(to: source)
        #expect(throws: StepFailure.self) {
            try NtdllPatcher.stage(build: build, runnerRoot: dir, bridge: dir.appending(path: "bridge"))
        }
    }

    @Test("Updating NotProton does not replace the source engine's matched Unix bridge")
    func preservesMatchedBridge() throws {
        let dir = try scratchDirectory("source-bridge")
        defer { try? FileManager.default.removeItem(at: dir) }
        let matched = dir.appending(path: "lib/wine/x86_64-unix/lsteamclient.so")
        let generic = dir.appending(path: "bridge/x86_64-unix/lsteamclient.so")
        for file in [matched, generic] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data("matches source Wine ABI".utf8).write(to: matched)
        try Data("a different Wine ABI".utf8).write(to: generic)
        var sourceBuild = build
        sourceBuild = RunnerBuild(bundleVersion: sourceBuild.bundleVersion, releaseVersion: "test", flavor: nil,
                                  loaderSHA256: "", cleanNtdll: [:], patchedNtdll: [:], provider: .freeWine)
        let outcome = try RunnerPatcher.install(build: sourceBuild, root: dir, bridge: dir.appending(path: "bridge"))
        #expect(outcome.builtins.isEmpty)
        #expect(try Data(contentsOf: matched) == Data("matches source Wine ABI".utf8))
    }

    @Test("Steam deployment never includes a generic bridge destination inside a source runner")
    func deploymentPreservesSourceABI() throws {
        let dir = try scratchDirectory("source-deployment")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runners = dir.appending(path: "runners")
        let sourceBuild = SupportedRunners.freeWine
        let sourceRoot = SupportPaths.clonedRoot(forBuild: sourceBuild.id, runners: runners)
        try FileManager.default.createDirectory(at: sourceRoot.appending(path: "lib/wine"), withIntermediateDirectories: true)
        let tool = InstalledTool(tool: sourceBuild.tools[0], build: sourceBuild.id)
        let files = DeploymentContent.files(
            payload: try InstallPayload.locate(), bridgePayload: try BridgePayload.locate(),
            app: dir.appending(path: "Steam.app"), bridge: dir.appending(path: "bridge"),
            signatures: dir.appending(path: "signatures"), overlayShim: dir.appending(path: "shim"),
            iconmaker: dir.appending(path: "iconmaker"), appinfo: dir.appending(path: "appinfo"),
            compatTools: dir.appending(path: "compatibilitytools.d"), tools: [tool], runners: runners)
        #expect(!files.contains { $0.destination.path.hasPrefix(sourceRoot.path + "/") })
        #expect(files.contains { $0.name == "notproton-freewine/run" })
    }
}
