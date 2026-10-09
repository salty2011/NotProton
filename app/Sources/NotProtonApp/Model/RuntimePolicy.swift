import Foundation

/// The same reviewed descriptors generate Steam's controls and the shell policy.
enum RuntimePolicy {
    enum State: String, Codable, Sendable { case supported, experimental, unavailable }
    struct Runtime: Codable, Sendable {
        let tools: [String]
        let automatic: String
        let capabilities: [String: String]
    }
    struct Option: Codable, Sendable {
        let feature: String
        let label: String
        let renderers: [String]
    }
    struct Document: Codable, Sendable {
        let schemaVersion: Int
        let runtimes: [String: Runtime]
        let options: [String: Option]
    }
    struct Effective: Sendable {
        let renderer: String
        let state: State
        let experimentalOptions: [String]
    }
    static let document: Document? = {
        guard let path = Bundle.module.url(forResource: "runtime-policy", withExtension: "json"),
              let data = try? Data(contentsOf: path), let value = try? JSONDecoder().decode(Document.self, from: data),
              value.schemaVersion == 1 else { return nil }
        return value
    }()

    static func resolve(build: String, renderer requested: String?, options: [String: String] = [:]) throws -> Effective {
        guard let document, let runtime = document.runtimes[build] else {
            throw StepFailure(step: "Resolve runtime settings", detail: "No reviewed settings exist for runtime \(build).")
        }
        let renderer = requested.flatMap { $0.isEmpty ? nil : $0 } ?? runtime.automatic
        guard let state = runtime.capabilities[renderer].flatMap(State.init(rawValue:)), state != .unavailable else {
            throw StepFailure(step: "Resolve runtime settings", detail: "The requested renderer is unavailable for runtime \(build).")
        }
        var experimental: [String] = []
        for (key, option) in document.options {
            guard let value = options[key], !value.isEmpty, value != "0" else { continue }
            let capability = runtime.capabilities[option.feature].flatMap(State.init(rawValue:)) ?? .unavailable
            guard capability != .unavailable, option.renderers.contains(renderer) else {
                throw StepFailure(step: "Resolve runtime settings", detail: "\(option.label) is unavailable with this runtime and renderer.")
            }
            if capability == .experimental { experimental.append(option.label) }
        }
        return Effective(renderer: renderer, state: state, experimentalOptions: experimental.sorted())
    }
}
