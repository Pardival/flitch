import AppKit
import FlitchCore
import FlitchProviders
import Observation

/// Connecting Flitch to an AI: shared by onboarding and Settings › Brain.
@MainActor
@Observable
final class BrainConnector {
    /// Providers reachable with an API key, in the order shown.
    struct KeyProvider: Identifiable, Hashable {
        let id: String
        let name: String
        let keyURL: URL
    }

    static let keyProviders: [KeyProvider] =
        [
            .init(
                id: ProviderFactory.anthropic, name: "Claude (Anthropic)",
                keyURL: URL(string: "https://console.anthropic.com/settings/keys")!),
            .init(
                id: ProviderFactory.openai, name: "OpenAI", keyURL: URL(string: "https://platform.openai.com/api-keys")!
            ),
            .init(id: "openrouter", name: "OpenRouter", keyURL: URL(string: "https://openrouter.ai/keys")!),
        ]
        + ProviderCatalog.keyPresets.map {
            KeyProvider(
                id: $0.id, name: $0.name, keyURL: $0.keyURL ?? URL(string: "https://github.com/Pardival/flitch")!)
        }

    static var localProviders: [ProviderPreset] { (try? ProviderCatalog.bundled().filter(\.isLocal)) ?? [] }

    var busy = false
    var errorMessage: String?
    /// "ChatGPT · me@example.com", "OpenRouter"…
    var connectedLabel: String?

    private let app: AppController
    init(app: AppController) {
        self.app = app
        Task { await refreshLabel() }
    }

    var settings: FlitchSettings { app.settings }

    func refreshLabel() async {
        guard let id = settings.providerID else {
            connectedLabel = nil
            return
        }
        let name = Self.displayName(id)
        if case .oauth(let t) = try? await app.credentials.credential(for: id), let account = t.accountName {
            connectedLabel = "\(name) · \(account)"
        } else {
            connectedLabel = name
        }
    }

    static func displayName(_ id: String) -> String {
        switch id {
        case ProviderFactory.chatgpt: "ChatGPT"
        case ProviderFactory.anthropic: "Claude"
        case ProviderFactory.openai: "OpenAI"
        default: ProviderCatalog.preset(id)?.name ?? id
        }
    }

    // MARK: - Flows

    func continueWithChatGPT() async -> Bool {
        await run {
            let previous: String? =
                if case .oauth(let t) = try? await self.app.credentials.credential(for: ProviderFactory.chatgpt) {
                    t.clientID
                } else { nil }
            let token = try await ChatGPTAuth().signIn(previousClientID: previous) { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
            try await self.app.credentials.save(.oauth(token), for: ProviderFactory.chatgpt)
            self.use(ProviderFactory.chatgpt)
        }
    }

    func signInWithOpenRouter() async -> Bool {
        await run {
            let key = try await OpenRouterAuth().signIn { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
            try await self.app.credentials.save(.apiKey(key), for: "openrouter")
            self.use("openrouter")
        }
    }

    /// Checks the key with a free call before saving it.
    func saveKey(_ key: String, for id: String) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return await run {
            if id == ProviderFactory.anthropic {
                try await AnthropicAdapter(apiKey: key).verifyKey()
            } else if let provider = ProviderFactory.make(id: id, credential: .apiKey(key)) {
                _ = try await provider.models()
            }
            try await self.app.credentials.save(.apiKey(key), for: id)
            self.use(id)
        }
    }

    func useLocal(_ preset: ProviderPreset) async -> Bool {
        await run {
            let provider = OpenAICompatibleAdapter(preset: preset, apiKey: nil)
            guard let first = try? await provider.models(), !first.isEmpty else {
                throw FlitchError.other(
                    String(localized: "\(preset.name) isn't running, or has no model loaded."))
            }
            self.use(preset.id)
        }
    }

    func signOut() async {
        guard let id = settings.providerID else { return }
        try? await app.credentials.remove(id)
        settings.providerID = nil
        await refreshLabel()
    }

    private func use(_ id: String) {
        settings.providerID = id
        app.refreshProvider()
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) async -> Bool {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await body()
            await refreshLabel()
            return true
        } catch {
            errorMessage = FlitchError(error)?.userMessage
            return false
        }
    }
}
