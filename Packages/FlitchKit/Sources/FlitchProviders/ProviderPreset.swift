import FlitchCore
import Foundation

/// A provider reachable through the OpenAI-compatible Chat Completions API.
/// Adding a provider = adding an entry to `Resources/providers.json`.
public struct ProviderPreset: Codable, Sendable, Hashable, Identifiable {
    public enum Auth: String, Codable, Sendable { case bearer, none }

    public struct Models: Codable, Sendable, Hashable {
        public var fast: String
        public var balanced: String
        public var precise: String

        public func model(for speed: ResponseSpeed) -> String {
            switch speed {
            case .fast: fast
            case .balanced: balanced
            case .precise: precise
            }
        }
    }

    public var id: String
    public var name: String
    public var baseURL: URL
    public var auth: Auth
    public var models: Models
    public var capabilities: [String]
    public var headers: [String: String]?
    public var local: Bool?

    public var providerCapabilities: ProviderCapabilities {
        var c: ProviderCapabilities = []
        if capabilities.contains("webSearch") { c.insert(.webSearch) }
        if capabilities.contains("tools") { c.insert(.tools) }
        if capabilities.contains("reasoningEffort") { c.insert(.reasoningEffort) }
        return c
    }

    public var isLocal: Bool { local ?? false }
}

public enum ProviderCatalog {
    private struct File: Codable {
        var version: Int
        var presets: [ProviderPreset]
    }

    /// Presets bundled with Flitch.
    public static func bundled() throws -> [ProviderPreset] {
        guard let url = Bundle.module.url(forResource: "providers", withExtension: "json") else {
            throw FlitchError.other("providers.json is missing")
        }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).presets
    }

    public static func preset(_ id: String) -> ProviderPreset? {
        try? bundled().first { $0.id == id }
    }
}
