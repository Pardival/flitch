import FlitchCore
import Foundation
import Testing

@testable import FlitchProviders

struct AnthropicAdapterTests {
    func adapter(host: String, status: Int = 200, body: Data) -> AnthropicAdapter {
        let session = StubURLProtocol.session(host: host) { _ in .init(status: status, body: body) }
        return AnthropicAdapter(
            apiKey: "sk-ant-test-123456", baseURL: URL(string: "https://\(host)/v1")!,
            http: HTTPTransport(session: session))
    }

    @Test func streamsTextCitationsToolUseAndUsage() async throws {
        let a = adapter(host: uniqueHost(), body: try fixture("anthropic_stream.txt"))
        let events = try await collect(a.stream(LLMRequest(system: "S", messages: [.user("Napoléon ?")])))
        let cite = Citation(
            title: "Napoléon Ier — Wikipédia", url: URL(string: "https://fr.wikipedia.org/wiki/Napol%C3%A9on_Ier")!)
        #expect(
            events == [
                .textDelta("Napoléon est né "), .citation(cite), .textDelta("en 1769."),
                .toolCall(ToolCall(id: "toolu_1", name: "remember", argumentsJSON: #"{"fact": "Loves history"}"#)),
                .done(TokenUsage(input: 200, output: 42)),
            ])
    }

    @Test func requestUsesHeadersModelEffortAndTools() async throws {
        let host = uniqueHost()
        let a = adapter(host: host, body: try fixture("anthropic_stream.txt"))
        let remember = ToolSpec(
            name: "remember", description: "Remember a fact",
            parametersJSON: #"{"type":"object","properties":{"fact":{"type":"string"}},"required":["fact"]}"#)
        _ = try await collect(
            a.stream(
                LLMRequest(
                    system: "SYS", messages: [.user("Hi")], speed: .precise, webSearch: true, tools: [remember])))
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test-123456")
        #expect(r.request.value(forHTTPHeaderField: "anthropic-version") == AnthropicAdapter.apiVersion)
        let body = try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "medium")
        #expect(body["thinking"] == nil)
        #expect(body["system"] as? String == "SYS")
        let tools = body["tools"] as? [[String: Any]] ?? []
        #expect(tools.first?["type"] as? String == "web_search_20260209")
        #expect(tools.last?["name"] as? String == "remember")
        #expect(tools.last?["input_schema"] != nil)
    }

    @Test(arguments: ResponseSpeed.allCases)
    func everySpeedHasAModel(speed: ResponseSpeed) {
        #expect(AnthropicAdapter.model(for: speed).model.hasPrefix("claude-"))
    }

    @Test func refusalBecomesAFriendlyError() async {
        let body = Data(
            """
            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":3}}

            """.utf8)
        let a = adapter(host: uniqueHost(), body: body)
        await #expect(throws: FlitchError.other("Claude declined to answer this one.")) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }

    @Test func streamErrorEventIsMapped() async {
        let body = Data(
            """
            event: error
            data: {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}

            """.utf8)
        let a = adapter(host: uniqueHost(), body: body)
        await #expect(throws: FlitchError.rateLimited(provider: "Claude")) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }

    @Test func invalidKeyIsMapped() async {
        let a = adapter(
            host: uniqueHost(), status: 401,
            body: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8))
        await #expect(throws: FlitchError.invalidCredentials(provider: "Claude")) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }
}
