import Foundation

// Use the engine and its matching dependencies from the upstream releases.
// The wrapper UI, SDK and D3DMetal are not installed or needed by NotProton.
enum SikarugirInstaller {
    static let step = "Install Sikarugir"
    static var build: RunnerBuild { SupportedRunners.all.first { $0.provider == .sikarugir }! }

    static func problems(in root: URL) -> [String] {
        var problems = ["notproton-provider", "vulkan/MoltenVK_icd.json", "Libraries/libinotify.0.dylib", "Libraries/libMoltenVK.dylib",
         "Libraries/GStreamer.framework/Libraries/libgstvideo-1.0.0.dylib",
         "Libraries/GStreamer.framework/Libraries/gstreamer-1.0/libgstlibav.dylib",
         "renderers/dxmt/wine/x86_64-windows/d3d11.dll",
         "renderers/dxmt/wine/x86_64-unix/winemetal.so",
         "renderers/d9vk/wine/x86_64-windows/d3d9.dll",
         "renderers/dxvk/wine/x86_64-windows/d3d11.dll"].compactMap { path -> String? in
            FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
                ? nil : "Sikarugir is missing \(path)"
        }
        let version = try? String(contentsOf: root.appending(path: "renderers/dxvk/version"), encoding: .utf8)
        if version?.contains("DXVK-Sikarugir-async-v1.10.3") != true {
            problems.append("Sikarugir's DXVK build needs repair")
        }
        let driver = root.appending(path: "Libraries/libMoltenVK.dylib")
        let mediaDriver = root.appending(path: "Libraries/GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib")
        if mediaDriver.resolvingSymlinksInPath() != driver.resolvingSymlinksInPath() {
            problems.append("Wine and GStreamer need to share one MoltenVK library")
        }
        return problems
    }

    struct Archive: Sendable {
        let file: String
        let sha256: String
        let base: URL
    }

    static let engine = Archive(
        file: "WS12WineSikarugir11.0_1.tar.xz",
        sha256: "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e",
        base: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0")!
    )
    static let template = Archive(
        file: "Template-1.0.21.tar.xz",
        sha256: "bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d",
        base: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0")!
    )

    static func run(report: @escaping @Sendable (String) -> Void = { _ in }) async throws -> RunnerSetup.Outcome {
        let root = SupportPaths.clonedRoot(forBuild: build.id)
        let reusable = RunnerInstaller.hasClone(forBuild: build.id)
            && problems(in: root).isEmpty
            && (try? RunnerInstaller.verifyClone(build: build, root: root)) != nil
        if !reusable {
            let cache = SupportPaths.packageDownloads.appending(path: "sikarugir")
            var archives: [URL] = []
            for archive in [engine, template] {
                archives.append(try await PinnedDownload.obtain(
                    file: archive.file, sha256: archive.sha256, bases: [archive.base],
                    into: cache, step: step, sourceName: "Sikarugir"
                ) { report($0.label) })
            }
            let inputs = archives
            try await Task.detached(priority: .userInitiated) {
                report("Preparing Sikarugir and graphics libraries")
                try install(engineArchive: inputs[0], templateArchive: inputs[1])
            }.value
        }
        return try await Task.detached(priority: .userInitiated) {
            try RunnerSetup.prepare(build, report: { report($0.label) })
        }.value
    }

    static func install(engineArchive: URL, templateArchive: URL, runners: URL = SupportPaths.runners) throws {
        for (url, archive) in [(engineArchive, engine), (templateArchive, template)] {
            guard Digest.sha256IfPresent(url) == archive.sha256 else {
                throw StepFailure(step: step, detail: "The downloaded \(archive.file) failed verification.")
            }
        }
        let fm = FileManager.default
        let staging = runners.appending(path: ".sikarugir-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var preserveStaging = false
        defer { if !preserveStaging { try? fm.removeItem(at: staging) } }
        let extracted = staging.appending(path: "extract")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        for archive in [engineArchive, templateArchive] {
            let result = try Shell.run("/usr/bin/tar", ["-xf", archive.path(percentEncoded: false), "-C", extracted.path(percentEncoded: false)])
            guard result.status == 0 else { throw StepFailure(step: step, detail: "Could not unpack \(archive.lastPathComponent). \(result.stderr)") }
        }
        let prepared = staging.appending(path: "prepared")
        let root = prepared.appending(path: "Wine")
        try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
        try fm.moveItem(at: extracted.appending(path: "wswine.bundle"), to: root)
        let frameworks = extracted.appending(path: "Template-1.0.21.app/Contents/Frameworks")
        try assembleLibraries(from: frameworks, into: root)
        try RunnerInstaller.verifyClone(build: build, root: root)
        try Data("sikarugir\n".utf8).write(to: root.appending(path: "notproton-provider"))
        RunnerInstaller.scrubDownloadMarkers(at: root)
        let target = SupportPaths.runnerRoot(forBuild: build.id, runners: runners)
        let previous = staging.appending(path: "previous")
        let replacing = fm.fileExists(atPath: target.path(percentEncoded: false))
        if replacing { try fm.moveItem(at: target, to: previous) }
        do {
            try fm.moveItem(at: prepared, to: target)
        } catch {
            if replacing {
                do { try fm.moveItem(at: previous, to: target) }
                catch let restoreError {
                    preserveStaging = true
                    throw StepFailure(step: step, detail: "Installing failed: \(error.localizedDescription). Restoring also failed: \(restoreError.localizedDescription). The previous runner is preserved at \(previous.path(percentEncoded: false)).")
                }
            }
            throw error
        }
    }

    static func assembleLibraries(from frameworks: URL, into root: URL) throws {
        let fm = FileManager.default
        let libs = root.appending(path: "Libraries")
        try fm.createDirectory(at: libs, withIntermediateDirectories: true)
        for entry in try fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil) {
            if entry.pathExtension == "dylib" || entry.lastPathComponent == "GStreamer.framework" {
                try fm.copyItem(at: entry, to: libs.appending(path: entry.lastPathComponent))
            }
        }
        // Wine and GStreamer run in the same process. Separate MoltenVK images
        // register duplicate Objective-C driver classes and can cause crashes.
        let mediaDriver = libs.appending(path: "GStreamer.framework/Versions/1.0/lib/libMoltenVK.dylib")
        try fm.removeItem(at: mediaDriver)
        try fm.createSymbolicLink(atPath: mediaDriver.path, withDestinationPath: "../../../../libMoltenVK.dylib")
        let renderers = root.appending(path: "renderers")
        try fm.createDirectory(at: renderers, withIntermediateDirectories: true)
        for renderer in ["dxmt", "dxvk"] {
            try fm.copyItem(at: frameworks.appending(path: "renderer/\(renderer)"), to: renderers.appending(path: renderer))
        }
        // D9VK's upstream directory also contains DXGI/D3D11. Isolate D3D9
        // so enabling it alongside DXMT cannot override DXMT's DLLs.
        let d9vk = renderers.appending(path: "d9vk")
        for arch in ["x86_64-windows", "i386-windows"] {
            let destination = d9vk.appending(path: "wine/\(arch)")
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.copyItem(
                at: renderers.appending(path: "dxvk/wine/\(arch)/d3d9.dll"),
                to: destination.appending(path: "d3d9.dll")
            )
        }
        for file in ["LICENSE", "version"] {
            try fm.copyItem(at: renderers.appending(path: "dxvk/\(file)"), to: d9vk.appending(path: file))
        }
        let icdSource = frameworks.deletingLastPathComponent().appending(path: "Resources/vulkan/icd.d/MoltenVK_icd.json")
        var descriptor = try JSONSerialization.jsonObject(with: Data(contentsOf: icdSource)) as? [String: Any] ?? [:]
        guard var icd = descriptor["ICD"] as? [String: Any] else {
            throw StepFailure(step: step, detail: "Sikarugir's Vulkan driver descriptor is missing.")
        }
        icd["library_path"] = "../Libraries/libMoltenVK.dylib"
        descriptor["ICD"] = icd
        let vulkan = root.appending(path: "vulkan")
        try fm.createDirectory(at: vulkan, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: descriptor, options: [.prettyPrinted, .sortedKeys])
            .write(to: vulkan.appending(path: "MoltenVK_icd.json"))
        guard fm.fileExists(atPath: libs.appending(path: "libinotify.0.dylib").path(percentEncoded: false)),
              fm.fileExists(atPath: renderers.appending(path: "dxmt/wine/x86_64-windows/d3d11.dll").path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: "Sikarugir's runtime or graphics libraries are incomplete.")
        }
    }
}
