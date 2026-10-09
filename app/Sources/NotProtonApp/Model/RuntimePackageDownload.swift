import Foundation
import Darwin

/// Only the app's approved digest authorizes reuse, including offline reuse.
enum RuntimePackageDownload {
    static var cache: URL { SupportPaths.home.appending(path: "Library/Caches/notproton/free-runtime") }

    static func cached(_ package: RuntimePackage, in directory: URL = cache) -> URL? {
        let file = directory.appending(path: package.file)
        guard valid(file, package: package) else { return nil }
        return file
    }

    static func valid(_ file: URL, package: RuntimePackage) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value == package.size
            && Digest.sha256IfPresent(file) == package.sha256
    }

    @discardableResult
    static func remember(_ source: URL, package: RuntimePackage, in directory: URL = cache) throws -> URL {
        try package.validate()
        guard valid(source, package: package) else {
            throw StepFailure(step: RuntimePackageInstaller.step, detail: "The package does not match this app's approved size and digest.")
        }
        if let present = cached(package, in: directory) { return present }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".download-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        guard valid(temporary, package: package) else {
            throw StepFailure(step: RuntimePackageInstaller.step, detail: "The cached package failed verification. Retry the copy.")
        }
        let destination = directory.appending(path: package.file)
        // Rename replaces a damaged cache atomically, retaining a valid copy on failure.
        guard rename(temporary.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return destination
    }

    static func obtain(
        _ package: RuntimePackage, in directory: URL = cache,
        report: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> URL {
        try package.validate()
        report("Checking the approved package cache")
        if let present = cached(package, in: directory) { return present }
        guard package.descriptor.distributionReady, let url = package.url,
              url.scheme == "https", url.lastPathComponent == package.file else {
            throw StepFailure(step: RuntimePackageInstaller.step,
                detail: "This candidate has no approved public download yet. Select its locally reviewed package with Install Package.")
        }
        let archive = try await PinnedDownload.obtain(file: package.file, sha256: package.sha256,
            bases: [url.deletingLastPathComponent()], into: directory,
            step: RuntimePackageInstaller.step, sourceName: "the free runtime release",
            report: { report($0.label) })
        guard valid(archive, package: package) else {
            throw StepFailure(step: RuntimePackageInstaller.step, detail: "The downloaded package has an unexpected size. Retry the download.")
        }
        return archive
    }
}
