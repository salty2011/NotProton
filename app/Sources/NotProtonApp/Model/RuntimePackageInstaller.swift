import Foundation

/// Prepare in isolation, then commit only the new build and its registration.
/// Existing engines and tool records are never used as staging space.
enum RuntimePackageInstaller {
    static let step = "Install free runtime package"

    @discardableResult
    static func install(
        archive: URL, package: RuntimePackage, appVersion: String = AppVersion.bundled,
        runners: URL = SupportPaths.runners, bridge: URL = SupportPaths.bridge,
        toolList: URL = SupportPaths.toolList, compatTools: URL = SupportPaths.Steam.compatTools,
        prepare: (RunnerBuild, URL, URL, URL, URL) throws -> RunnerSetup.Outcome = { build, runners, bridge, list, tools in
            try RunnerSetup.prepare(build, runners: runners, bridge: bridge, toolList: list, compatTools: tools)
        }
    ) throws -> RunnerSetup.Outcome {
        try package.validate()
        guard appVersion.compare(package.descriptor.minimumAppVersion, options: .numeric) != .orderedAscending else {
            throw StepFailure(step: step, detail: "This runtime requires NotProton \(package.descriptor.minimumAppVersion). Update the app first.")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let currentOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        guard currentOS.compare(package.descriptor.minimumMacOSVersion, options: .numeric) != .orderedAscending else {
            throw StepFailure(step: step, detail: "This runtime requires macOS \(package.descriptor.minimumMacOSVersion).")
        }
        let fm = FileManager.default
        guard (try fm.attributesOfItem(atPath: archive.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value == package.size,
              Digest.sha256IfPresent(archive) == package.sha256 else {
            throw StepFailure(step: step, detail: "The archive is not the package approved by this app's catalog.")
        }
        let target = SupportPaths.runnerRoot(forBuild: package.id, runners: runners)
        guard !fm.fileExists(atPath: target.path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: "Runtime \(package.id) is already installed. Existing builds are immutable.")
        }
        try fm.createDirectory(at: runners, withIntermediateDirectories: true)
        let stage = runners.appending(path: ".package-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let unpacked = stage.appending(path: "unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        // The archive hash is checked before invoking tar. Catalog generation also
        // validates every archive link; the imported descriptor cannot authorize it.
        let listing = try Shell.run("/usr/bin/tar", ["-tf", archive.path(percentEncoded: false)])
        guard listing.succeeded, listing.stdout.split(separator: "\n").allSatisfy({ name in
            let value = String(name).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return !name.hasPrefix("/") && !value.split(separator: "/").contains("..")
                && (value == "package.json" || value == "Wine" || value.hasPrefix("Wine/"))
        }) else { throw StepFailure(step: step, detail: "Unsafe or unreadable package archive.") }
        let extracted = try Shell.run("/usr/bin/tar", ["-xpf", archive.path(percentEncoded: false), "-C", unpacked.path(percentEncoded: false), "--no-same-owner"])
        guard extracted.succeeded else { throw StepFailure(step: step, detail: extracted.stderr) }
        try package.verifyPayload(at: unpacked)
        let stagedRunners = stage.appending(path: "runners")
        let stagedBuild = SupportPaths.runnerRoot(forBuild: package.id, runners: stagedRunners)
        try fm.createDirectory(at: stagedBuild, withIntermediateDirectories: true)
        try fm.moveItem(at: unpacked.appending(path: "Wine"), to: stagedBuild.appending(path: "Wine"))
        try fm.moveItem(at: unpacked.appending(path: "package.json"), to: stagedBuild.appending(path: "package.json"))
        let stagedBridge = stage.appending(path: "bridge")
        let stagedTools = stage.appending(path: "compatibilitytools.d")
        let outcome = try prepare(package.build, stagedRunners, stagedBridge, stage.appending(path: "tools"), stagedTools)
        let toolName = package.build.tools[0].name
        let toolTarget = compatTools.appending(path: toolName)
        let bridgeTarget = bridge.appending(path: "wine/\(package.id)")
        guard !fm.fileExists(atPath: toolTarget.path(percentEncoded: false)),
              !fm.fileExists(atPath: bridgeTarget.path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: "Stale registration exists for \(package.id); remove that copy before installing.")
        }
        let previousList = fm.fileExists(atPath: toolList.path(percentEncoded: false))
            ? try Data(contentsOf: toolList) : nil
        var committed: [URL] = []
        do {
            for (source, destination) in [
                (stagedBuild, target),
                (stagedBridge.appending(path: "wine/\(package.id)"), bridgeTarget),
                (stagedTools.appending(path: toolName), toolTarget),
            ] {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: destination)
                committed.append(destination)
            }
            let tools = CompatToolList.installed(runners: runners, file: toolList)
            try fm.createDirectory(at: toolList.deletingLastPathComponent(), withIntermediateDirectories: true)
            try atomicReplace(toolList, with: Data(CompatToolList.contents(tools).utf8), step: step)
            return outcome
        } catch {
            var restoration: [String] = []
            for path in committed.reversed() {
                do { try fm.removeItem(at: path) } catch { restoration.append(error.localizedDescription) }
            }
            do {
                if let previousList { try atomicReplace(toolList, with: previousList, step: step) }
                else if fm.fileExists(atPath: toolList.path(percentEncoded: false)) { try fm.removeItem(at: toolList) }
            } catch { restoration.append(error.localizedDescription) }
            if !restoration.isEmpty {
                throw StepFailure(step: step, detail: "Installation failed: \(error.localizedDescription)\nRollback failed: \(restoration.joined(separator: "; "))")
            }
            throw error
        }
    }
}
