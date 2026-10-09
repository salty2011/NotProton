import Foundation
import Testing

@testable import NotProtonApp

@Suite("Free Sikarugir runner")
struct SikarugirTests {
    @Test("Free runner activation never consults a CrossOver license")
    func noPaidLicense() throws {
        let runners = FileManager.default.temporaryDirectory.appending(path: "np-free-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: runners) }
        let build = SikarugirInstaller.build
        let root = SupportPaths.clonedRoot(forBuild: build.id, runners: runners)
        try FileManager.default.createDirectory(at: root.appending(path: "lib/wine"), withIntermediateDirectories: true)
        _ = try RunnerSetup.prepare(
            build, runners: runners,
            bridge: runners.appending(path: "bridge"), toolList: runners.appending(path: "tools"),
            compatTools: runners.appending(path: "compatibilitytools.d"),
            runScript: { let script = runners.appending(path: "run"); try Data("#!/bin/sh\n".utf8).write(to: script); return script },
            license: { _ in Issue.record("A free runner requested a paid license"); return CrossOverLicense.Status(licensed: false, detail: "", diagnostic: "") },
            verify: { _, _ in }, stage: { _, _, _ in [] }, patch: { _, _, _ in RunnerPatcher.Outcome() }
        )
        #expect(RunnerStore.state(runners: runners, verify: { _, _ in [] }) == .ready(builds: [build.id]))
        #expect(RunnerStore.installedBuilds(in: runners) == [build])
        #expect(root.lastPathComponent == "Wine")
    }

    @Test("An existing free installation keeps its Steam tool mapping beside CrossOver")
    func migratesLegacyFreeTool() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "np-free-migration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let runners = dir.appending(path: "runners")
        let free = SikarugirInstaller.build
        let paid = try #require(SupportedRunners.build(id: "26.3.0.39832"))
        for build in [free, paid] {
            try FileManager.default.createDirectory(
                at: SupportPaths.clonedRoot(forBuild: build.id, runners: runners).appending(path: "lib/wine"),
                withIntermediateDirectories: true)
        }
        let current = runners.appending(path: "current")
        try FileManager.default.createSymbolicLink(atPath: current.path, withDestinationPath: "\(free.id)/Wine")
        let compatTools = dir.appending(path: "compatibilitytools.d")
        let run = compatTools.appending(path: "notproton/run")
        try FileManager.default.createDirectory(at: run.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("read /runners/current\n".utf8).write(to: run)
        let bridge = dir.appending(path: "bridge")
        let legacyDll = bridge.appending(path: "wine/x86_64-windows/ntdll.dll")
        try FileManager.default.createDirectory(at: legacyDll.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacyDll)
        let list = dir.appending(path: "tools")
        try CompatToolList.sync(runners: runners, bridge: bridge, file: list, compatTools: compatTools)
        let tools = CompatToolList.installed(runners: runners, file: list)
        #expect(tools.first?.name == "notproton")
        #expect(tools.first?.build == free.id)
        #expect(tools.contains { $0.name == "notproton-26.3" && $0.build == paid.id })
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: legacyDll.path))
        // The old paths must survive until Steam's run script has been updated.
        try Data("new per-build launcher\n".utf8).write(to: run)
        try CompatToolList.sync(runners: runners, bridge: bridge, file: list, compatTools: compatTools)
        #expect(CompatToolList.installed(runners: runners, file: list) == tools)
        #expect(!FileManager.default.fileExists(atPath: current.path))
        #expect(!FileManager.default.fileExists(atPath: legacyDll.path))
    }

    @Test("Modified archives are rejected before creating a runner")
    func rejectsModifiedArchive() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "np-free-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = dir.appending(path: "bad.tar.xz")
        try Data("not the pinned engine".utf8).write(to: archive)
        #expect(throws: StepFailure.self) {
            try SikarugirInstaller.install(engineArchive: archive, templateArchive: archive, runners: dir.appending(path: "runners"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "runners").path))
    }

    // Real release archives exercise the PE detours, dependency layout and codesigning.
    // Set NP_SIKARUGIR_ARCHIVES to a directory holding both pinned downloads.
    @Test("Published engine installs and patches without CrossOver")
    func publishedEngine() throws {
        guard let archives = ProcessInfo.processInfo.environment["NP_SIKARUGIR_ARCHIVES"] else { return }
        let dir = FileManager.default.temporaryDirectory.appending(path: "np-sikarugir-integration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = URL(filePath: archives)
        let runners = dir.appending(path: "runners")
        try SikarugirInstaller.install(
            engineArchive: cache.appending(path: SikarugirInstaller.engine.file),
            templateArchive: cache.appending(path: SikarugirInstaller.template.file), runners: runners
        )
        let root = SupportPaths.clonedRoot(forBuild: SikarugirInstaller.build.id, runners: runners)
        // Both Wine/Vulkan and GStreamer load MoltenVK in the game process.
        // Loading different images duplicates its Objective-C driver classes.
        let driverProbeSource = dir.appending(path: "driver-probe.c")
        try Data("""
            #include <dlfcn.h>
            #include <mach-o/dyld.h>
            #include <stdio.h>
            #include <string.h>
            int main(int argc, char **argv) {
                if (argc != 3) return 2;
                for (int i = 1; i < 3; i++)
                    if (!dlopen(argv[i], RTLD_NOW | RTLD_LOCAL)) { puts(dlerror()); return 3; }
                int count = 0;
                for (uint32_t i = 0; i < _dyld_image_count(); i++)
                    if (strstr(_dyld_get_image_name(i), "/libMoltenVK.dylib")) count++;
                printf("DRIVER_COUNT %d\\n", count);
                return count == 1 ? 0 : 1;
            }
            """.utf8).write(to: driverProbeSource)
        let driverProbe = dir.appending(path: "driver-probe")
        try Shell.check("/usr/bin/clang", ["-arch", "x86_64", driverProbeSource.path, "-o", driverProbe.path])
        let driverResult = try Shell.run(driverProbe.path, [
            root.appending(path: "Libraries/libMoltenVK.dylib").path,
            root.appending(path: "Libraries/GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib").path,
        ])
        #expect(driverResult.status == 0, Comment(rawValue: driverResult.stdout + driverResult.stderr))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Libraries/SikarugirSdk.framework").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "renderers/d3dmetal").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "renderers/d9vk/wine/i386-windows/d3d9.dll").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "renderers/d9vk/wine/x86_64-windows/dxgi.dll").path))
        let bridge = dir.appending(path: "bridge")
        let payload = try BridgePayload.locate()
        for builtin in RunnerPatcher.builtins(in: root) {
            let path = "\(builtin.arch)/\(builtin.name)"
            let source = try #require(payload.sources.first { $0.bridgePaths.contains(path) }).source
            let destination = bridge.appending(path: "\(builtin.arch)/\(builtin.name)")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        _ = try RunnerSetup.prepare(SikarugirInstaller.build, runners: runners, bridge: bridge,
            toolList: dir.appending(path: "tools"), compatTools: dir.appending(path: "compatibilitytools.d"))
        #expect(RunnerPatcher.verify(build: SikarugirInstaller.build, root: root, bridge: bridge).isEmpty)
        try RunnerInstaller.verifyClone(build: SikarugirInstaller.build, root: root)
        let second = try RunnerSetup.prepare(SikarugirInstaller.build, runners: runners, bridge: bridge,
            toolList: dir.appending(path: "tools"), compatTools: dir.appending(path: "compatibilitytools.d"))
        #expect(second.stagedNothing)
    }
}
