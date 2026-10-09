import Foundation

/// A stopped-client edit of one mapping, retaining unrelated VDF bytes.
/// Steam remains the owner of this file; never edit it while Steam is running.
enum SteamToolSelection {
    static var file: URL { SupportPaths.Steam.userData.appending(path: "config/config.vdf") }
    private static let path = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]
    private struct Token { let value: String; let range: Range<String.Index> }
    private struct Entry { let key: String; let range: Range<String.Index>; let children: [Entry]?; let close: String.Index?; let value: String? }

    private static func entries(_ text: String) throws -> [Entry] {
        func fail() -> StepFailure { StepFailure(step: "Select runtime", detail: "Steam's configuration is unreadable or ambiguous. Open Steam once, quit it, then retry.") }
        var tokens: [Token] = []; var at = text.startIndex
        while at < text.endIndex {
            if text[at].isWhitespace { at = text.index(after: at); continue }
            if text[at...].hasPrefix("//") {
                at = text[at...].firstIndex(of: "\n") ?? text.endIndex; continue
            }
            let start = at; var value = ""
            if text[at] == "{" || text[at] == "}" {
                value.append(text[at]); at = text.index(after: at)
            } else if text[at] == "\"" {
                at = text.index(after: at); var closed = false
                while at < text.endIndex {
                    let char = text[at]; at = text.index(after: at)
                    if char == "\"" { closed = true; break }
                    if char == "\\" {
                        guard at < text.endIndex else { throw fail() }
                        value.append(text[at]); at = text.index(after: at)
                    } else { value.append(char) }
                }
                guard closed else { throw fail() }
            } else {
                while at < text.endIndex, !text[at].isWhitespace, text[at] != "{", text[at] != "}" {
                    value.append(text[at]); at = text.index(after: at)
                }
            }
            tokens.append(Token(value: value, range: start..<at))
        }
        var index = 0
        func parse(nested: Bool) throws -> [Entry] {
            var result: [Entry] = []
            while index < tokens.count {
                let key = tokens[index]
                if key.value == "}" { if nested { return result }; throw fail() }
                guard key.value != "{", index + 1 < tokens.count else { throw fail() }
                index += 1; let value = tokens[index]; index += 1
                if value.value == "{" {
                    let children = try parse(nested: true)
                    guard index < tokens.count, tokens[index].value == "}" else { throw fail() }
                    let close = tokens[index]; index += 1
                    result.append(Entry(key: key.value, range: key.range.lowerBound..<close.range.upperBound,
                                        children: children, close: close.range.lowerBound, value: nil))
                } else {
                    guard value.value != "}" else { throw fail() }
                    result.append(Entry(key: key.value, range: key.range.lowerBound..<value.range.upperBound, children: nil, close: nil, value: value.value))
                }
            }
            if nested { throw fail() }
            return result
        }
        return try parse(nested: false)
    }

    private static func locate(_ path: [String], in entries: [Entry]) throws -> Entry? {
        guard let key = path.first else { return nil }
        let found = entries.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        guard found.count <= 1 else { throw StepFailure(step: "Select runtime", detail: "Steam has duplicate runtime mapping sections. Resolve them in Steam first.") }
        guard let entry = found.first else { return nil }
        if path.count == 1 { return entry }
        return try locate(Array(path.dropFirst()), in: entry.children ?? [])
    }

    static func mapping(_ appID: String, in text: String) throws -> String? {
        try locate(path + [appID], in: entries(text)).map { String(text[$0.range]) }
    }

    static func mappedGames(to names: Set<String>, in text: String) throws -> [String] {
        guard let section = try locate(path, in: entries(text)) else { return [] }
        var result: [String] = []
        for game in section.children ?? [] {
            if let name = try locate(["name"], in: game.children ?? [])?.value, names.contains(name) { result.append(game.key) }
        }
        return result.sorted()
    }

    static func replacing(_ appID: String, mapping: String?, in text: String) throws -> String {
        guard !appID.isEmpty, appID.allSatisfy(\.isNumber) else {
            throw StepFailure(step: "Select runtime", detail: "Invalid Steam game identity.")
        }
        let parsed = try entries(text)
        if let mapping {
            let candidate = try entries(mapping)
            guard candidate.count == 1, candidate[0].key == appID, candidate[0].children != nil else {
                throw StepFailure(step: "Select runtime", detail: "The retained mapping is not a single record for this game.")
            }
        }
        if let entry = try locate(path + [appID], in: parsed) {
            return text.replacingCharacters(in: entry.range, with: mapping ?? "")
        }
        guard let mapping else { return text }
        if let section = try locate(path, in: parsed), let close = section.close {
            return text.replacingCharacters(in: close..<close, with: "\n\(mapping)\n")
        }
        guard let steam = try locate(Array(path.dropLast()), in: parsed), let close = steam.close else {
            throw StepFailure(step: "Select runtime", detail: "Steam has no configuration section. Open Steam once, quit it, then retry.")
        }
        return text.replacingCharacters(in: close..<close, with: "\n\"CompatToolMapping\"\n{\n\(mapping)\n}\n")
    }

    static func mapping(_ appID: String, tool: InstalledTool) throws -> String {
        let name = tool.tool.name
        guard name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else {
            throw StepFailure(step: "Select runtime", detail: "Invalid runtime tool identity.")
        }
        return "\"\(appID)\"\n{\n\t\"name\" \"\(name)\"\n\t\"config\" \"\"\n\t\"priority\" \"250\"\n}"
    }
}
