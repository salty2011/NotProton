import Foundation
import Darwin

/// Bundled catalog entries, rather than an imported manifest, authorize packages.
struct RuntimePackage: Codable, Sendable, Equatable {
    struct File: Codable, Sendable, Equatable {
        let kind: String
        let sha256: String?
        let mode: Int?
        let target: String?
    }
    struct Descriptor: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let id: String
        let displayVersion: String
        let hostArchitecture: String
        let windowsArchitectures: [String]
        let minimumAppVersion: String
        let minimumMacOSVersion: String
        let bridgeABI: String
        let files: [String: File]
        let criticalFiles: [String: String]
        let capabilities: [String: String]
        let distributionReady: Bool
    }
    let id: String
    let file: String
    let sha256: String
    let size: Int64
    let descriptorSHA256: String
    let descriptor: Descriptor
    var url: URL? = nil

    private static let step = "Install free runtime package"

    func validate() throws {
        func refuse(_ detail: String) throws { throw StepFailure(step: Self.step, detail: detail) }
        guard descriptor.schemaVersion == 1, id == descriptor.id,
              id.hasPrefix("freewine-"), id.count > 9,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }),
              file == id + ".tar.xz", size > 0,
              Self.isDigest(sha256), Self.isDigest(descriptorSHA256),
              descriptor.hostArchitecture == "x86_64",
              descriptor.windowsArchitectures == ["i386", "x86_64"], descriptor.bridgeABI == id,
              !descriptor.files.isEmpty else { try refuse("Invalid or unsupported runtime catalog entry."); return }
        for (path, entry) in descriptor.files {
            guard Self.isPath(path) else { try refuse("Unsafe package path: \(path)"); return }
            switch entry.kind {
            case "file":
                guard let hash = entry.sha256, Self.isDigest(hash), let mode = entry.mode,
                      (0...0o777).contains(mode), entry.target == nil else {
                    try refuse("Invalid package file: \(path)"); return
                }
            case "link":
                guard let target = entry.target, !target.isEmpty, !target.hasPrefix("/"),
                      !target.contains("\\"), !target.contains("\0"), entry.sha256 == nil,
                      Self.linkIsInternal(path: path, target: target) else {
                    try refuse("External package link: \(path)"); return
                }
            default: try refuse("Unknown package inventory kind: \(path)")
            }
        }
        for (path, hash) in descriptor.criticalFiles {
            guard descriptor.files[path]?.sha256 == hash else {
                try refuse("Critical file is not pinned in the inventory: \(path)"); return
            }
        }
        for path in ["lib/wine/x86_64-unix/wine", "bin/wineserver",
                     "lib/wine/x86_64-unix/ntdll.so", "lib/wine/x86_64-unix/lsteamclient.so",
                     "lib/wine/i386-windows/ntdll.dll", "lib/wine/x86_64-windows/ntdll.dll",
                     "lib/wine/i386-windows/lsteamclient.dll", "lib/wine/x86_64-windows/lsteamclient.dll"] {
            guard descriptor.criticalFiles[path] != nil else {
                try refuse("Package lacks its matching engine or bridge: \(path)"); return
            }
        }
        guard descriptor.capabilities["automatic"] == "dxmt+d9vk",
              descriptor.capabilities["d3dmetal"] == "unavailable", descriptor.capabilities["fex"] == "unavailable" else {
            try refuse("Unsupported runtime capability contract."); return
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func isPath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.contains("\0")
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func linkIsInternal(path: String, target: String) -> Bool {
        var parts = Array(path.split(separator: "/").dropLast())
        for component in target.split(separator: "/") {
            if component == ".." { guard !parts.isEmpty else { return false }; parts.removeLast() }
            else if component != "." { parts.append(component) }
        }
        return !parts.isEmpty
    }

    private static func canonicalPath(_ file: URL) -> String? {
        file.withUnsafeFileSystemRepresentation { value in
            guard let value, let resolved = realpath(value, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    var build: RunnerBuild {
        let ntdll = Dictionary(uniqueKeysWithValues: [WineArch.i386Windows, .x86_64Windows].map { arch in
            (arch, descriptor.criticalFiles["lib/wine/\(arch.rawValue)/ntdll.dll"]!)
        })
        return RunnerBuild(bundleVersion: String(id.dropFirst("freewine-".count)),
            releaseVersion: descriptor.displayVersion, flavor: nil,
            loaderSHA256: descriptor.criticalFiles["lib/wine/x86_64-unix/wine"]!,
            cleanNtdll: ntdll, patchedNtdll: ntdll,
            tools: [CompatTool(name: "notproton-\(id)", flavor: .rosetta,
                              display: "Free Wine \(descriptor.displayVersion) (Experimental)")], provider: .freeWine)
    }

    func verifyPayload(at directory: URL) throws {
        let fm = FileManager.default
        let manifest = directory.appending(path: "package.json")
        guard Digest.sha256IfPresent(manifest) == descriptorSHA256,
              try JSONDecoder().decode(Descriptor.self, from: Data(contentsOf: manifest)) == descriptor else {
            throw StepFailure(step: Self.step, detail: "The package descriptor does not match the bundled catalog.")
        }
        let wine = directory.appending(path: "Wine")
        guard try fm.attributesOfItem(atPath: wine.path(percentEncoded: false))[.type] as? FileAttributeType == .typeDirectory else {
            throw StepFailure(step: Self.step, detail: "Wine must be a package directory, not a link.")
        }
        let root = wine.resolvingSymlinksInPath()
        guard let canonicalRoot = Self.canonicalPath(root) else {
            throw StepFailure(step: Self.step, detail: "Cannot resolve the Wine package directory.")
        }
        var observed = Set<String>()
        guard let walk = fm.enumerator(atPath: root.path(percentEncoded: false)) else {
            throw StepFailure(step: Self.step, detail: "The package contains no Wine tree.")
        }
        for case let relative as String in walk {
            let path = root.appending(path: relative)
            let attributes = try fm.attributesOfItem(atPath: path.path(percentEncoded: false))
            if attributes[.type] as? FileAttributeType == .typeDirectory { continue }
            observed.insert(relative)
            guard let entry = descriptor.files[relative],
                  Self.canonicalPath(path)?.hasPrefix(canonicalRoot + "/") == true else {
                throw StepFailure(step: Self.step, detail: "Unlisted or external package file: \(relative)")
            }
            if entry.kind == "link" {
                guard attributes[.type] as? FileAttributeType == .typeSymbolicLink,
                      try fm.destinationOfSymbolicLink(atPath: path.path(percentEncoded: false)) == entry.target,
                      fm.fileExists(atPath: path.path(percentEncoded: false)) else {
                    throw StepFailure(step: Self.step, detail: "Invalid package link: \(relative)")
                }
            } else {
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      Digest.sha256IfPresent(path) == entry.sha256,
                      (attributes[.posixPermissions] as? NSNumber)?.intValue == entry.mode else {
                    throw StepFailure(step: Self.step, detail: "Package file differs from the catalog: \(relative)")
                }
            }
        }
        guard observed == Set(descriptor.files.keys) else {
            throw StepFailure(step: Self.step, detail: "Package inventory is incomplete.")
        }
    }

    func problems(in root: URL) -> [String] {
        descriptor.criticalFiles.keys.sorted().compactMap { path in
            let file = root.appending(path: path)
            let checked = path == "lib/wine/x86_64-unix/wine" ? Clean.copy(of: file) : file
            return Digest.sha256IfPresent(checked) == descriptor.criticalFiles[path]
                ? nil : "\(path) does not match runtime package \(id)"
        }
    }
}

enum RuntimeCatalog {
    struct Document: Decodable { let schemaVersion: Int; let packages: [RuntimePackage] }
    static func decode(_ data: Data) throws -> [RuntimePackage] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, Set(document.packages.map(\.id)).count == document.packages.count else {
            throw StepFailure(step: "Read runtime catalog", detail: "Unsupported or duplicate runtime catalog entries.")
        }
        for package in document.packages { try package.validate() }
        return document.packages
    }
    static let packages: [RuntimePackage] = {
        guard let file = Bundle.module.url(forResource: "free-runtime-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: file), let packages = try? decode(data) else { return [] }
        return packages
    }()
    static func package(id: String) -> RuntimePackage? { packages.first { $0.id == id } }
}
