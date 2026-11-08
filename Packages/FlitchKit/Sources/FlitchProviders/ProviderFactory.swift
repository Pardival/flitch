import FlitchCore
import Foundation

/// Builds the LLM provider for the user's choice from its stored credential.
public enum ProviderFactory {
    /// Provider ids that are not presets.
    public static let anthropic = "anthropic"
    public static let chatgpt = "chatgpt"
    public static let openai = "openai"

    /// `chatgptToken` returns a fresh plan-usage access token (refreshing it when needed).
    public static func make(
        id: String, credential: Credential?, http: HTTPTransport = .makeDefault(),
        chatgptToken: (@Sendable () async throws -> String)? = nil
    ) -> (any LLMProvider)? {
        switch id {
        case chatgpt:
            guard case .oauth = credential, let chatgptToken else { return nil }
            return OpenAIResponsesAdapter(auth: .chatgpt(chatgptToken), http: http)
        case openai:
            guard let key = credential?.secret, !key.isEmpty else { return nil }
            return OpenAIResponsesAdapter(auth: .apiKey(key), http: http)
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
