import FlitchCore
import Foundation

/// OpenAI Responses API with streaming: "Continue with ChatGPT" (plan usage) and OpenAI API keys.
public struct OpenAIResponsesAdapter: LLMProvider {
    public enum Auth: Sendable {
        /// ChatGPT plan: OAuth access token, refreshed on demand.
        case chatgpt(@Sendable () async throws -> String)
        case apiKey(String)
    }

    public let id: String
    public let displayName: String
    public var capabilities: ProviderCapabilities {
        // web search isn't documented for plan-usage tokens: only offer it with an API key
        if case .apiKey = auth { return [.webSearch, .tools, .reasoningEffort] }
        return [.tools, .reasoningEffort]
    }

    private let auth: Auth
    private let baseURL: URL
    private let http: HTTPTransport
    private let modelCache = ModelCache()

    public init(
        auth: Auth, baseURL: URL = URL(string: "https://api.openai.com/v1")!, http: HTTPTransport = .makeDefault()
    ) {
        self.auth = auth
        self.baseURL = baseURL
        self.http = http
        if case .chatgpt = auth {
            id = ProviderFactory.chatgpt
            displayName = "ChatGPT"
        } else {
            id = "openai"
            displayName = "OpenAI"
        }
    }

    private func token() async throws -> String {
        switch auth {
        case .apiKey(let k): k
        case .chatgpt(let get): try await get()
        }
    }

    public func models() async throws -> [ModelInfo] {
        if let cached = await modelCache.models { return cached }
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        let token = try await token()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let json = try JSONSerialization.jsonObject(with: try await http.data(req)) as? [String: Any]
            let models = (json?["data"] as? [[String: Any]] ?? [])
                .filter { ($0["visibility"] as? String).map { $0 == "list" } ?? true }
                .compactMap { ($0["id"] as? String).map { ModelInfo(id: $0) } }
            await modelCache.set(models)
            return models
        } catch {
            throw FlitchError.fromProvider(error, provider: displayName, secrets: [token])
        }
    }

    /// Picks a model for the speed among the account's models (names change often, so no fixed ids).
    static func pick(_ models: [ModelInfo], speed: ResponseSpeed) -> String? {
        let ids = models.map(\.id).filter { !$0.contains("audio") && !$0.contains("tts") && !$0.contains("embedding") }
        let prefer: [String] =
            switch speed {
            case .fast: ["mini", "nano", "flash", "lite"]
            case .balanced: []
            case .precise: ["pro", "max"]
            }
        if let m = ids.first(where: { id in prefer.contains { id.contains($0) } }) { return m }
        return ids.first { id in !["mini", "nano", "pro"].contains { id.contains($0) } } ?? ids.first
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var secrets: [String] = []
                do {
                    let token = try await token()
                    secrets = [token]
                    let model: String
                    if let m = request.model, !m.isEmpty {
                        model = m
                    } else if let m = Self.pick(try await models(), speed: request.speed) {
                        model = m
                    } else {
                        throw FlitchError.other("\(displayName) has no model available")
                    }
                    let lines = try await http.lines(try makeRequest(request, model: model, token: token))
                    var decoder = ResponsesStreamDecoder()
                    for try await event in lines.sseEvents() {
                        try Task.checkCancellation()
                        for e in try decoder.decode(event.data) { continuation.yield(e) }
                    }
                    try decoder.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: FlitchError.fromProvider(error, provider: displayName, secrets: secrets))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(_ request: LLMRequest, model: String, token: String) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("responses"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var tools: [[String: Any]] = []
        if request.webSearch, capabilities.contains(.webSearch) { tools.append(["type": "web_search"]) }
        for tool in request.tools {
            let params = try JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8))
            tools.append(["type": "function", "name": tool.name, "description": tool.description, "parameters": params])
        }
        var body: [String: Any] = [
            "model": model,
            "instructions": request.system,
            "input": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            "stream": true,
            "store": false,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        if request.speed != .balanced {
            body["reasoning"] = ["effort": request.speed == .fast ? "low" : "high"]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}

private actor ModelCache {
    var models: [ModelInfo]?
    func set(_ m: [ModelInfo]) { models = m }
}

/// Decodes Responses API stream events (pure, tested with fixtures).
struct ResponsesStreamDecoder {
    private(set) var completed = false

    mutating func decode(_ data: String) throws -> [LLMEvent] {
        guard let json = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
            let type = json["type"] as? String
        else { return [] }
        switch type {
        case "response.output_text.delta":
            if let d = json["delta"] as? String, !d.isEmpty { return [.textDelta(d)] }
        case "response.output_text.annotation.added":
            let a = json["annotation"] as? [String: Any] ?? [:]
            if a["type"] as? String == "url_citation", let s = a["url"] as? String, let url = URL(string: s) {
                return [.citation(Citation(title: a["title"] as? String ?? url.host() ?? s, url: url))]
            }
        case "response.output_item.done":
            let item = json["item"] as? [String: Any] ?? [:]
            if item["type"] as? String == "function_call", let name = item["name"] as? String {
                return [
                    .toolCall(
                        ToolCall(
                            id: item["call_id"] as? String ?? "", name: name,
                            argumentsJSON: item["arguments"] as? String ?? "{}"))
                ]
            }
        case "response.completed":
            completed = true
            let usage = (json["response"] as? [String: Any])?["usage"] as? [String: Any]
            return [
                .done(
                    TokenUsage(input: usage?["input_tokens"] as? Int ?? 0, output: usage?["output_tokens"] as? Int ?? 0)
                )
            ]
        case "response.failed", "error":
            let err =
                ((json["response"] as? [String: Any])?["error"] as? [String: Any]) ?? json["error"] as? [String: Any]
                ?? json
            let code = err["code"] as? String ?? ""
            switch code {
            case "subscription_sharing_usage_limit_exceeded":
                throw FlitchError.rateLimited(provider: "ChatGPT")
            case "subscription_sharing_usage_unavailable":
                throw FlitchError.other(
                    "Your ChatGPT plan can't be used here right now. Try another brain in Settings.")
            case "invalid_api_key", "unauthorized":
                throw FlitchError.invalidCredentials(provider: "ChatGPT")
            default:
                throw FlitchError.other(err["message"] as? String ?? code)
            }
        case "response.incomplete":
            completed = true  // keep what was said (e.g. max tokens)
            return [.done(nil)]
        default:
            break
        }
        return []
    }

    func finish() throws {
        guard completed else { throw FlitchError.other("the answer was cut off") }
    }
}
