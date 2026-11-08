import FlitchCore
import Foundation

/// Builds the LLM provider for the user's choice from its stored credential.
public enum ProviderFactory {
    /// Provider ids that are not presets.
    public static let anthropic = "anthropic"
    public static let chatgpt = "chatgpt"

    public static func make(id: String, credential: Credential?, http: HTTPTransport = .makeDefault()) -> (
        any LLMProvider
    )? {
        switch id {
        case anthropic:
            guard let key = credential?.secret, !key.isEmpty else { return nil }
            return AnthropicAdapter(apiKey: key, http: http)
        default:
            guard let preset = ProviderCatalog.preset(id) else { return nil }
            if preset.isLocal { return OpenAICompatibleAdapter(preset: preset, apiKey: nil, http: http) }
            guard let key = credential?.secret, !key.isEmpty else { return nil }
            return OpenAICompatibleAdapter(preset: preset, apiKey: key, http: http)
        }
    }
}
