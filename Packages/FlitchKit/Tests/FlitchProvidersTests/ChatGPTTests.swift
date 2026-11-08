import FlitchCore
import Foundation
import Testing

@testable import FlitchProviders

struct ChatGPTAuthTests {
    static let attempt = ChatGPTAuth.Attempt(
        pkce: PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), state: "st", nonce: "no",
        redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)

    static func items(_ url: URL) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            })
    }

    @Test func firstSignInUsesDynamicRegistration() {
        let q = Self.items(ChatGPTAuth.authorizationURL(attempt: Self.attempt, clientID: nil, hostID: "urn:uuid:x"))
        #expect(q["client_id"] == "dynamic_agent_client")
        #expect(q["agent_name_hint"] == "Flitch")
        #expect(q["ext_agent_host_id"] == "urn:uuid:x")
        #expect(q["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(q["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(q["resource"] == "https://api.openai.com/v1")
        #expect(q["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["state"] == "st" && q["nonce"] == "no" && q["response_type"] == "code")
    }

    @Test func reauthorizationReusesTheIssuedClient() {
        let q = Self.items(ChatGPTAuth.authorizationURL(attempt: Self.attempt, clientID: "oaiapp_1", hostID: "h"))
        #expect(q["client_id"] == "oaiapp_1")
        #expect(q["agent_name_hint"] == nil)
    }

    static func idToken(email: String) -> String {
        let payload = Data(#"{"email":"\#(email)"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "e30.\(payload).sig"
    }

    @Test func exchangeSendsAFormAndReadsTheToken() async throws {
        let host = uniqueHost()
        let body =
            #"{"access_token":"at1","refresh_token":"rt1","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct","id_token":"\#(Self.idToken(email: "me@example.com"))"}"#
        let session = StubURLProtocol.session(host: host) { _ in .init(body: Data(body.utf8)) }
        let auth = ChatGPTAuth(http: HTTPTransport(session: session), tokenURL: URL(string: "https://\(host)/token")!)
        let token = try await auth.exchange(code: "c0de", attempt: Self.attempt, clientID: "oaiapp_1")
        #expect(token.accessToken == "at1" && token.refreshToken == "rt1" && token.clientID == "oaiapp_1")
        #expect(token.accountName == "me@example.com")
        #expect(!token.isExpired())

        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let form = String(decoding: r.body ?? Data(), as: UTF8.self)
        #expect(form.contains("grant_type=authorization_code"))
        #expect(form.contains("code=c0de") && form.contains("client_id=oaiapp_1"))
        #expect(form.contains("code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        #expect(form.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"))
    }

    @Test func missingPlanScopeIsRefused() async {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { _ in
            .init(body: Data(#"{"access_token":"a","scope":"openid profile email"}"#.utf8))
        }
        let auth = ChatGPTAuth(http: HTTPTransport(session: session), tokenURL: URL(string: "https://\(host)/token")!)
        await #expect(throws: FlitchError.self) {
            _ = try await auth.exchange(code: "c", attempt: Self.attempt, clientID: "oaiapp_1")
        }
    }

    @Test func refreshRotatesTheRefreshToken() async throws {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { _ in
            .init(body: Data(#"{"access_token":"at2","refresh_token":"rt2","expires_in":3600}"#.utf8))
        }
        let auth = ChatGPTAuth(http: HTTPTransport(session: session), tokenURL: URL(string: "https://\(host)/token")!)
        let old = OAuthToken(
            accessToken: "at1", refreshToken: "rt1", clientID: "oaiapp_1", accountName: "me@example.com")
        let fresh = try await auth.refresh(old)
        #expect(fresh.accessToken == "at2" && fresh.refreshToken == "rt2" && fresh.accountName == "me@example.com")
        let form = String(decoding: StubURLProtocol.requests(host: host).first?.body ?? Data(), as: UTF8.self)
        #expect(form.contains("grant_type=refresh_token") && form.contains("refresh_token=rt1"))
    }
}

struct OpenAIResponsesAdapterTests {
    func adapter(host: String, auth: OpenAIResponsesAdapter.Auth, stream: Data) -> OpenAIResponsesAdapter {
        let session = StubURLProtocol.session(host: host) { req in
            req.url!.path.hasSuffix("/models")
                ? .init(
                    body: Data(
                        #"{"data":[{"id":"gpt-6.1-sol","visibility":"list"},{"id":"gpt-6.1-sol-mini","visibility":"list"},{"id":"hidden","visibility":"hidden"}]}"#
                            .utf8))
                : .init(body: stream)
        }
        return OpenAIResponsesAdapter(
            auth: auth, baseURL: URL(string: "https://\(host)/v1")!, http: HTTPTransport(session: session))
    }

    @Test func streamsTextCitationsToolsAndUsage() async throws {
        let a = adapter(
            host: uniqueHost(), auth: .chatgpt({ "plan-token" }), stream: try fixture("responses_stream.txt"))
        let events = try await collect(a.stream(LLMRequest(system: "S", messages: [.user("Napoléon ?")])))
        #expect(
            events == [
                .textDelta("Napoléon est né "),
                .citation(
                    Citation(
                        title: "Napoléon Ier", url: URL(string: "https://fr.wikipedia.org/wiki/Napol%C3%A9on_Ier")!)),
                .textDelta("en 1769."),
                .toolCall(ToolCall(id: "call_9", name: "remember", argumentsJSON: #"{"fact":"Loves history"}"#)),
                .done(TokenUsage(input: 150, output: 20)),
            ])
    }

    @Test func planRequestIsStatelessAndPicksAListedModel() async throws {
        let host = uniqueHost()
        let a = adapter(host: host, auth: .chatgpt({ "plan-token" }), stream: try fixture("responses_stream.txt"))
        _ = try await collect(
            a.stream(LLMRequest(system: "SYS", messages: [.user("Hi")], speed: .fast, webSearch: true)))
        let r = try #require(StubURLProtocol.requests(host: host).last)
        #expect(r.request.url?.path == "/v1/responses")
        #expect(r.request.value(forHTTPHeaderField: "Authorization") == "Bearer plan-token")
        let body = try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
        #expect(body["store"] as? Bool == false && body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "gpt-6.1-sol-mini")
        #expect(body["instructions"] as? String == "SYS")
        #expect(body["tools"] == nil)  // no web search on plan tokens
        #expect(!a.capabilities.contains(.webSearch))
    }

    @Test func apiKeyGetsWebSearch() throws {
        let a = OpenAIResponsesAdapter(auth: .apiKey("sk-x"))
        let req = try a.makeRequest(LLMRequest(system: "", messages: [], webSearch: true), model: "m", token: "sk-x")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any]
        #expect((body?["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search")
    }

    @Test(arguments: [
        ("subscription_sharing_usage_limit_exceeded", FlitchError.rateLimited(provider: "ChatGPT"))
    ])
    func usageLimitMidStream(code: String, expected: FlitchError) async {
        let stream = Data(
            """
            data: {"type":"response.output_text.delta","delta":"Hel"}

            data: {"type":"response.failed","response":{"error":{"code":"\(code)","message":"limit"}}}

            """.utf8)
        let a = adapter(host: uniqueHost(), auth: .chatgpt({ "t" }), stream: stream)
        await #expect(throws: expected) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }

    @Test func streamWithoutCompletionIsAnError() async {
        let a = adapter(
            host: uniqueHost(), auth: .chatgpt({ "t" }),
            stream: Data(#"data: {"type":"response.output_text.delta","delta":"Hel"}\#n\#n"#.utf8))
        await #expect(throws: FlitchError.other("the answer was cut off")) {
            _ = try await collect(a.stream(LLMRequest(system: "", messages: [.user("x")])))
        }
    }

    @Test(arguments: [
        (ResponseSpeed.fast, "gpt-6.1-sol-mini"), (.balanced, "gpt-6.1-sol"), (.precise, "gpt-6.1-sol-pro"),
    ])
    func modelPicking(speed: ResponseSpeed, expected: String) {
        let models = ["gpt-6.1-sol", "gpt-6.1-sol-mini", "gpt-6.1-sol-pro", "gpt-4o-mini-tts"].map { ModelInfo(id: $0) }
        #expect(OpenAIResponsesAdapter.pick(models, speed: speed) == expected)
    }

    @Test func neverPicksAModelThatCannotChat() {
        let models = [
            "omni-moderation-2024-09-26", "gpt-image-1", "gpt-4o-realtime-preview", "gpt-4o-transcribe",
            "text-embedding-3-large", "dall-e-3", "gpt-4o-search-preview", "gpt-6.1-sol-2026-05-01", "gpt-6.1-sol",
        ].map { ModelInfo(id: $0) }
        #expect(OpenAIResponsesAdapter.pick(models, speed: .balanced) == "gpt-6.1-sol")
        #expect(OpenAIResponsesAdapter.pick(models, speed: .fast) == "gpt-6.1-sol")
        #expect(OpenAIResponsesAdapter.pick(models.prefix(5).map { $0 }, speed: .balanced) == nil)
    }

    @Test func modelsComeNewestFirst() async throws {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { _ in
            .init(
                body: Data(
                    #"{"data":[{"id":"gpt-4o","created":1},{"id":"omni-moderation-latest","created":3},{"id":"gpt-6.1-sol","created":2}]}"#
                        .utf8))
        }
        let a = OpenAIResponsesAdapter(
            auth: .apiKey("k"), baseURL: URL(string: "https://\(host)/v1")!, http: HTTPTransport(session: session))
        #expect(try await a.models().map(\.id) == ["gpt-6.1-sol", "gpt-4o"])  // newest first, chat only
        #expect(OpenAIResponsesAdapter.pick(try await a.models(), speed: .balanced) == "gpt-6.1-sol")
    }
}

struct CostTierTests {
    @Test(arguments: [
        ("gpt-5-nano", CostTier.veryCheap), ("gpt-5.6-luna", .veryCheap), ("gpt-5.4-mini", .cheap),
        ("gpt-5.6-terra", .cheap), ("gpt-5.6-sol", .medium), ("gpt-5.5", .medium), ("gpt-5.5-pro", .expensive),
        ("gpt-6-astra", .expensive), ("claude-haiku-4-5", .cheap), ("claude-opus-4-8", .expensive),
    ])
    func guessesFromTheName(id: String, tier: CostTier) {
        #expect(ModelInfo(id: id).cost == tier)
    }

    @Test func aKnownPriceWinsOverTheName() {
        #expect(ModelInfo(id: "something-pro", inputPricePerMillion: 0.1).cost == .veryCheap)
        #expect(ModelInfo(id: "x", inputPricePerMillion: 1).cost == .cheap)
        #expect(ModelInfo(id: "x", inputPricePerMillion: 3).cost == .medium)
        #expect(ModelInfo(id: "x", inputPricePerMillion: 15).cost == .expensive)
    }
}
