import Foundation

// Imports the qualified local build. A different compilation needs its own
// identity/hashes; a self-authored manifest alone is not an allow-list.
enum FreeWineInstaller {
    static let step = "Import experimental free runtime"
    static var build: RunnerBuild { SupportedRunners.freeWine }
    static let binaryHashes = [
        "lib/wine/x86_64-unix/ntdll.so": "07f68c99e9fc3b425f5431477b8b35244a4fb81f4937348de417f869221dcdf3",
        "lib/wine/x86_64-unix/lsteamclient.so": "ae232ce279040a0e4fc056943a37fa7ef0e989be61df76dfd840cdc1f092e75a",
        "lib/wine/x86_64-windows/lsteamclient.dll": "055faa1f0d24f26745ed548e96f5ac2c95b6a179791a7509ddee4f98ce6b8d47",
        "lib/wine/i386-windows/lsteamclient.dll": "a389d7a0b74031e1b7494340cbb433dd7cc5f897a17f7e303709bde565a2a385",
        "lib/wine/x86_64-unix/winemetal.so": "3d50d7f39c64778c71d0af2fce1cde818d09ffbce7c4f7b8ae24ae1df567c0ca",
        "bin/wineserver": "fd9c6d159774ad95611ccbfc47ac4519953c511e02cf12e67bae9d940fbc1064",
    ]
    static let rendererHashes = [
        "x86_64-windows/d3d11.dll": "7ca382af0eb32d8a432f6efb14d594fefb45673663be1f7e6682254bff885c47",
        "i386-windows/d3d11.dll": "9afc2b3419818618c4c87274435a28935b0df002caa4b9a8d3a88d3dc846b17d",
        "x86_64-windows/dxgi.dll": "fc58aae0aba511a1ec4d2417e5bba6adb888bb14315d0f59cccdfd27f670d544",
        "i386-windows/dxgi.dll": "7df8cdf66e12a108410002abc77b01f70aa59b8a36a70fa0bc6ae3b056841319",
    ]

    static func mismatches(in root: URL, hashes: [String: String]) -> [String] {
        hashes.keys.sorted().compactMap { path in
            Digest.sha256IfPresent(root.appending(path: path)) == hashes[path]
                ? nil : "\(path) does not match the qualified source build"
        }
    }

    static func problems(in root: URL) -> [String] {
        var result = mismatches(in: root, hashes: binaryHashes)
        do { try RunnerInstaller.verifyClone(build: build, root: root) }
        catch { result.append("Source runtime loader or ntdll does not match the qualified build") }
        result += mismatches(in: root.appending(path: "renderers/dxmt/wine"), hashes: rendererHashes)
        for path in ["notproton-provider", "Libraries/libgnutls.dylib", "Libraries/libfreetype.dylib",
                     "Libraries/libMoltenVK.dylib", "vulkan/MoltenVK_icd.json",
                     "Libraries/GStreamer.framework/Libraries/gstreamer-1.0/libgstlibav.dylib",
                     "renderers/d9vk/wine/x86_64-windows/d3d9.dll", "renderers/dxvk/wine/x86_64-windows/d3d11.dll",
                     "COPYING.LIB", "LICENSE.NotProton", "LICENSE.DXMT", "notproton-source-manifest.json"] {
            if !FileManager.default.fileExists(atPath: root.appending(path: path).path) {
                result.append("Source runtime is missing \(path)")
            }
        }
        return result
    }

    static func assemble(from source: URL, components: URL, renderer: URL, runners: URL = SupportPaths.runners) throws {
        let fm = FileManager.default
        try RunnerInstaller.verifyClone(build: build, root: source)
        let wrong = mismatches(in: source, hashes: binaryHashes) + mismatches(in: renderer, hashes: rendererHashes)
        guard wrong.isEmpty else { throw StepFailure(step: step, detail: wrong.joined(separator: "\n")) }
        try RunnerInstaller.verifyClone(build: SikarugirInstaller.build, root: components)
        guard SikarugirInstaller.problems(in: components).isEmpty else {
            throw StepFailure(step: step, detail: "Set up or repair Sikarugir's matching dependencies first.")
        }
        let target = SupportPaths.runnerRoot(forBuild: build.id, runners: runners)
        guard !fm.fileExists(atPath: target.path) else {
            throw StepFailure(step: step, detail: "This source runtime is already imported. Remove its copy before importing another build.")
        }
        let staging = runners.appending(path: ".freewine-\(UUID().uuidString)")
        let root = staging.appending(path: "Wine")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        func copy(_ source: URL, _ destination: URL) throws {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let result = try Shell.run("/bin/cp", ["-cR", source.path, destination.path])
            guard result.succeeded else { throw StepFailure(step: step, detail: result.stderr) }
        }
        try copy(source, root)
        // Materialize dependencies so removing Sikarugir cannot break this runner.
        for path in ["Libraries", "vulkan", "renderers"] {
            let destination = root.appending(path: path)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        }
        for path in ["Libraries", "vulkan", "renderers/d9vk", "renderers/dxvk"] {
            try copy(components.appending(path: path), root.appending(path: path))
        }
        try copy(renderer, root.appending(path: "renderers/dxmt/wine"))
        try Data("freewine\n".utf8).write(to: root.appending(path: "notproton-provider"))
        try Data("Free Wine 26.3 revision 1\n".utf8).write(to: root.appending(path: "version"))
        let faults = problems(in: root)
        guard faults.isEmpty else { throw StepFailure(step: step, detail: faults.joined(separator: "\n")) }
        try fm.moveItem(at: staging, to: target)
    }

    static func run(from source: URL, report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> RunnerSetup.Outcome {
        report("Copying experimental source runtime")
        let components = SupportPaths.clonedRoot(forBuild: SikarugirInstaller.build.id)
        let renderer = source.deletingLastPathComponent().appending(path: "dxmt-v0.80/v0.80")
        return try await Task.detached(priority: .userInitiated) {
            try assemble(from: source, components: components, renderer: renderer)
            return try RunnerSetup.prepare(build, report: { report($0.label) })
        }.value
    }
}
