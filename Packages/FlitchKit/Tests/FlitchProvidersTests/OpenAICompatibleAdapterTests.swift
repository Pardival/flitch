import FlitchCore
import Foundation
import Testing

@testable import FlitchProviders

struct SSEParserTests {
    @Test func parsesEventsWithAndWithoutBlankLines() {
        var p = SSEParser()
        #expect(p.feed("event: a") == nil)
        #expect(p.feed("data: 1") == nil)
        #expect(p.feed("") == SSEEvent(event: "a", data: "1"))
        #expect(p.feed(": keep-alive") == nil)
        #expect(p.feed("data: 2") == nil)
        #expect(p.feed("data: 3") == SSEEvent(event: nil, data: "2"))  // no blank line: next data closes it
        #expect(p.finish() == SSEEvent(event: nil, data: "3"))
    }
}

struct ProviderCatalogTests {
    @Test func bundledPresetsLoad() throws {
        let presets = try ProviderCatalog.bundled()
        #expect(Set(presets.map(\.id)).isSuperset(of: ["openrouter", "ollama", "lmstudio"]))
        let or = try #require(ProviderCatalog.preset("openrouter"))
        #expect(or.models.model(for: .precise).hasPrefix("anthropic/"))
        #expect(!or.isLocal && or.auth == .bearer)
        #expect(ProviderCatalog.preset("ollama")?.isLocal == true)
    }
}

struct OpenAICompatibleAdapterTests {
    func adapter(host: String, key: String? = "sk-or-test-123456", status: Int = 200, body: Data)
        -> OpenAICompatibleAdapter
    {
        var preset = ProviderCatalog.preset("openrouter")!
        preset.baseURL = URL(string: "https://\(host)/api/v1")!
        let session = StubURLProtocol.session(host: host) { _ in .init(status: status, body: body) }
        return OpenAICompatibleAdapter(preset: preset, apiKey: key, http: HTTPTransport(session: session))
    }

    @Test func streamsTextToolCallsAndUsage() async throws {
        let host = uniqueHost()
        let a = adapter(host: host, body: try fixture("chat_completions_stream.txt"))
        let events = try await collect(
            a.stream(LLMRequest(system: "You are Flitch.", messages: [.user("Napoléon ?")], speed: .fast)))
        #expect(
            events == [
                .textDelta("Napoléon est né "), .textDelta("en 1769."),
                .toolCall(ToolCall(id: "call_1", name: "remember", argumentsJSON: #"{"fact":"Loves history"}"#)),
                .done(TokenUsage(input: 120, output: 14)),
            ])
    }

    @Test func sendsModelMessagesAuthAndHeaders() async throws {
        let host = uniqueHost()
        let a = adapter(host: host, body: try fixture("chat_completions_stream.txt"))
        _ = try await collect(
            a.stream(
                LLMRequest(system: "SYS", messages: [.user("Hi"), .assistant("Hey"), .user("Bye")], speed: .precise)))
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.url?.path == "/api/v1/chat/completions")
        #expect(r.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test-123456")
        #expect(r.request.value(forHTTPHeaderField: "X-Title") == "Flitch")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "anthropic/claude-opus-5.5")
        #expect(body["stream"] as? Bool == true)
        let messages = body["messages"] as? [[String: String]]
        #expect(messages?.map { $0["role"]! } == ["system", "user", "assistant", "user"])
        #expect(messages?.first?["content"] == "SYS")
    }

    @Test func customModelOverridesPreset() throws {
        let a = adapter(host: uniqueHost(), body: Data())
        let req = try a.makeRequest(
            LLMRequest(system: "", messages: [], model: "x-ai/grok-4.7"), model: "x-ai/grok-4.7")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect(body?["model"] as? String == "x-ai/grok-4.7")
    }

    @Test(arguments: [
        (401, FlitchError.invalidCredentials(provider: "OpenRouter")),
        (429, FlitchError.rateLimited(provider: "OpenRouter")),
    ])
    func mapsHTTPErrors(status: Int, expected: FlitchError) async {
        let a = adapter(host: uniqueHost(), status: status, body: Data(#"{"error":{"message":"nope"}}"#.utf8))
        await #expect(throws: expected) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }

    @Test func errorMessagesNeverContainTheKey() async {
        let key = "sk-or-SECRET-abcdef"
        let a = adapter(
            host: uniqueHost(), key: key, status: 500,
            body: Data(#"{"error":{"message":"bad key sk-or-SECRET-abcdef"}}"#.utf8))
        do {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
            Issue.record("expected an error")
        } catch {
            #expect(!"\(error)".contains(key))
            #expect(!error.localizedDescription.contains(key))
        }
    }

    @Test func localServerUsesTheLoadedModel() async throws {
        let host = uniqueHost()
        var preset = ProviderCatalog.preset("ollama")!
        preset.baseURL = URL(string: "http://\(host)/v1")!
        let stream = try fixture("chat_completions_stream.txt")
        let session = StubURLProtocol.session(host: host) { req in
            req.url!.path.hasSuffix("/models")
                ? .init(body: Data(#"{"data":[{"id":"llama3.2"}]}"#.utf8)) : .init(body: stream)
        }
        let a = OpenAICompatibleAdapter(preset: preset, apiKey: nil, http: HTTPTransport(session: session))
        _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        let chat = try #require(StubURLProtocol.requests(host: host).last)
        let body = try JSONSerialization.jsonObject(with: chat.body ?? Data()) as? [String: Any]
        #expect(body?["model"] as? String == "llama3.2")
        #expect(chat.request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

struct CloudPresetTests {
    static let cloudIDs = ["xai", "deepseek", "mistral", "qwen", "kimi", "gemini"]

    @Test(arguments: cloudIDs)
    func presetIsComplete(id: String) throws {
        let p = try #require(ProviderCatalog.preset(id))
        #expect(p.auth == .bearer && !p.isLocal)
        #expect(p.baseURL.scheme == "https")
        for speed in ResponseSpeed.allCases { #expect(!p.models.model(for: speed).isEmpty) }
        #expect(p.keyURL != nil)
        #expect(ProviderCatalog.keyPresets.contains { $0.id == id })
    }

    /// Each provider streams the shared Chat Completions fixture through its own base path.
    @Test(arguments: cloudIDs)
    func streamsThroughItsEndpoint(id: String) async throws {
        let host = uniqueHost()
        var preset = try #require(ProviderCatalog.preset(id))
        let path = preset.baseURL.path()
        preset.baseURL = URL(string: "https://\(host)\(path)")!
        let body = try fixture("chat_completions_stream.txt")
        let session = StubURLProtocol.session(host: host) { _ in .init(body: body) }
        let a = OpenAICompatibleAdapter(preset: preset, apiKey: "key-123456", http: HTTPTransport(session: session))
        let events = try await collect(a.stream(LLMRequest(system: "S", messages: [.user("x")], speed: .balanced)))
        #expect(events.first == .textDelta("Napoléon est né "))
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.url?.path == path + "/chat/completions")
        let json = try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any]
        #expect(json?["model"] as? String == preset.models.balanced)
    }
}
