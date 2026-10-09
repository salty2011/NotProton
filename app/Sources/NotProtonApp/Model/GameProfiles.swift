import Foundation

struct GameProfile: Decodable, Sendable {
    let id: String
    let revision: Int
    let appID: String
    let executable: String
    let runtimes: [String]
    let renderers: [String]
    let architectures: [String]
    let defaults: [String: String]
    let rationale: String
    let evidence: String
    let recipes: [String]
}

/// Defaults are data, never shell commands. Renderer files remain read-only.
enum GameProfiles {
    private struct Catalog: Decodable { let schemaVersion: Int; let profiles: [GameProfile] }
    static let all: [GameProfile] = {
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: GameProfileCatalog.data), catalog.schemaVersion == 1 else { return [] }
        return catalog.profiles
    }()
    static let disabledName = "notproton-profiles-disabled"
    static let generatedName = ".notproton-profiles"

    static func applicable(appID: String, runtime: String, renderer: String, architecture: String, executable: String) -> [GameProfile] {
        all.filter { $0.appID == appID && $0.runtimes.contains(runtime) && $0.renderers.contains(renderer)
            && $0.architectures.contains(architecture) && $0.executable == executable }
    }

    static func disabled(in root: URL) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: disabledName).path) }
    static func setDisabled(_ disabled: Bool, in root: URL) throws {
        let file = root.appending(path: disabledName)
        if disabled { try Data("1\n".utf8).write(to: file, options: .atomic) }
        else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    static func reset(in root: URL) throws {
        try setDisabled(false, in: root)
        let generated = root.appending(path: generatedName)
        if FileManager.default.fileExists(atPath: generated.path) { try FileManager.default.removeItem(at: generated) }
    }

    private static func hostPath(_ value: String, prefix: URL, cwd: URL) -> URL {
        let path = value.replacingOccurrences(of: "\\", with: "/")
        if path.count > 2, path[path.index(after: path.startIndex)] == ":" {
            let drive = path.prefix(1).lowercased(); let rest = String(path.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return (drive == "z" ? URL(filePath: "/") : prefix.appending(path: "pfx/dosdevices/\(drive):")).appending(path: rest)
        }
        return path.hasPrefix("/") ? URL(filePath: path) : cwd.appending(path: path)
    }

    static func architecture(of executable: String, root: URL, cwd: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: hostPath(executable, prefix: root, cwd: cwd)) else { return nil }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 64), header.count == 64, header[0] == 0x4d, header[1] == 0x5a else { return nil }
        let offset = (0..<4).reduce(UInt64(0)) { $0 | UInt64(header[60 + $1]) << (8 * $1) }
        guard offset >= 64, offset <= 16 * 1024 * 1024 else { return nil }
        do {
            try file.seek(toOffset: offset)
            guard let pe = try file.read(upToCount: 6), pe.count == 6, Array(pe.prefix(4)) == [0x50, 0x45, 0, 0] else { return nil }
            switch UInt16(pe[4]) | UInt16(pe[5]) << 8 {
            case 0x8664: return "x86_64"
            case 0x14c: return "i386"
            case 0xaa64: return "arm64"
            default: return nil
            }
        } catch { return nil }
    }

    // These parsers follow the shipped DXMT0.80/DXVK1.10.3 active-section rules.
    // DXMT file context continues into the inline config; it does not reset.
    private static func keys(_ lines: [String], executable: String, active: inout Bool) -> Set<String> {
        var result = Set<String>()
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), let end = line.lastIndex(of: "]") {
                active = String(line[line.index(after: line.startIndex)..<end]) == executable
            } else if active, let equals = line.firstIndex(of: "=") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._".contains($0)) }) { result.insert(key) }
            }
        }
        return result
    }

    static func launchValue(
        appID: String, runtime: String, renderer: String, architecture: String, executable: String,
        root: URL, cwd: URL, environment: [String: String], report: (String) -> Void = { _ in }
    ) throws -> String {
        let variable = renderer == "dxmt" ? "DXMT_CONFIG" : "DXVK_CONFIG_FILE"
        let original = environment[variable] ?? ""
        let matches = applicable(appID: appID, runtime: runtime, renderer: renderer, architecture: architecture, executable: executable)
        guard !disabled(in: root), environment["NOTPROTON_DISABLE_PROFILES"] != "1", let profile = matches.first else { return original }
        let configVariable = renderer == "dxmt" ? "DXMT_CONFIG_FILE" : "DXVK_CONFIG_FILE"
        let supplied = environment[configVariable]
        let source = hostPath(supplied?.isEmpty == false ? supplied! : "\(renderer).conf", prefix: root, cwd: cwd)
        let text = FileManager.default.fileExists(atPath: source.path) ? try String(contentsOf: source, encoding: .utf8) : ""
        var active = true
        var present = keys(text.components(separatedBy: "\n"), executable: executable, active: &active)
        if renderer == "dxmt" { present.formUnion(keys(original.components(separatedBy: ";"), executable: executable, active: &active)) }
        let defaults = profile.defaults.filter { !present.contains($0.key) }.sorted { $0.key < $1.key }
        report("profile=\(profile.id) revision=\(profile.revision) runtime=\(runtime) renderer=\(renderer) defaults=\(defaults.map(\.key).joined(separator: ",")) explicit=\(profile.defaults.keys.filter { present.contains($0) }.sorted().joined(separator: ","))")
        guard !defaults.isEmpty else { return original }
        if renderer == "dxmt" {
            return original + (original.isEmpty || original.hasSuffix(";") ? "" : ";")
                + "[\(executable)];" + defaults.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        }
        let directory = root.appending(path: generatedName)
        if FileManager.default.fileExists(atPath: directory.path), try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(profile.id)-v\(profile.revision)-\(renderer).conf")
        // Defaults precede the untouched user file. The renderer's own parser
        // still decides the effective user values and all unrelated options.
        let output = defaults.map { "\($0.key) = \($0.value)" }.joined(separator: "\n") + "\n" + text
        try Data(output.utf8).write(to: file, options: .atomic)
        return "Z:" + file.path(percentEncoded: false)
    }
}
