import FlitchCore
import Foundation

/// Chat Completions with SSE streaming: OpenRouter, xAI, DeepSeek, Mistral, Qwen, Kimi,
/// Gemini (compatible endpoint), Ollama, LM Studio… configured by a `ProviderPreset`.
public struct OpenAICompatibleAdapter: LLMProvider {
    public let preset: ProviderPreset
    private let apiKey: String?
    private let http: HTTPTransport

    public var id: String { preset.id }
    public var displayName: String { preset.name }
    public var capabilities: ProviderCapabilities { preset.providerCapabilities }

    public init(preset: ProviderPreset, apiKey: String?, http: HTTPTransport = .makeDefault()) {
        self.preset = preset
        self.apiKey = apiKey
        self.http = http
    }

    public func models() async throws -> [ModelInfo] {
        var req = URLRequest(url: preset.baseURL.appendingPathComponent("models"))
        authorize(&req)
        do {
            let data = try await http.data(req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let items = json?["data"] as? [[String: Any]] ?? []
            return items.compactMap { item in
                (item["id"] as? String).map {
                    // OpenRouter gives the price per token as a string ("0.0000002")
                    let perToken = ((item["pricing"] as? [String: Any])?["prompt"] as? String).flatMap(Double.init)
                    return ModelInfo(
                        id: $0, name: item["name"] as? String, inputPricePerMillion: perToken.map { $0 * 1_000_000 })
                }
            }
        } catch {
            throw FlitchError.fromProvider(error, provider: displayName, secrets: [apiKey].compactMap { $0 })
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: FlitchError.fromProvider(
                            error, provider: displayName, secrets: [apiKey].compactMap { $0 }))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request

    func makeRequest(_ request: LLMRequest, model: String) throws -> URLRequest {
        var req = URLRequest(url: preset.baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        authorize(&req)
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        var tools: [[String: Any]] = []
        if request.webSearch, let type = preset.webSearchTool {
            tools.append(["type": type, "parameters": ["max_results": 5]])
        }
        if !request.tools.isEmpty {
            tools += try request.tools.map { tool -> [String: Any] in
                let params = try JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8))
                return [
                    "type": "function",
                    "function": ["name": tool.name, "description": tool.description, "parameters": params],
                ]
            }
        }
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func authorize(_ req: inout URLRequest) {
        if preset.auth == .bearer, let apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in preset.headers ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
    }

    private func resolveModel(_ request: LLMRequest) async throws -> String {
        if let m = request.model, !m.isEmpty { return m }
        let m = preset.models.model(for: request.speed)
        if !m.isEmpty { return m }
        // local servers: use whatever model is loaded
        guard let first = try await models().first else {
            throw FlitchError.other("\(displayName) has no model loaded")
        }
        return first.id
    }

    // MARK: - Streaming

    private func run(_ request: LLMRequest, _ out: AsyncThrowingStream<LLMEvent, Error>.Continuation) async throws {
        let model = try await resolveModel(request)
        let lines = try await http.lines(makeRequest(request, model: model))
        var decoder = ChatCompletionsStreamDecoder()
        for try await event in lines.sseEvents() {
            try Task.checkCancellation()
            for e in try decoder.decode(event.data) { out.yield(e) }
        }
        for e in decoder.finish() { out.yield(e) }
    }
}

/// Decodes Chat Completions stream chunks into `LLMEvent`s (pure, tested with fixtures).
struct ChatCompletionsStreamDecoder {
    private struct PendingTool {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var tools: [Int: PendingTool] = [:]
    private var seenCitations: Set<URL> = []

    /// `{"type":"url_citation","url_citation":{"url":…,"title":…}}`
    static func citation(_ a: [String: Any]) -> Citation? {
        guard a["type"] as? String == "url_citation" else { return nil }
        let c = a["url_citation"] as? [String: Any] ?? a
        guard let s = c["url"] as? String, let url = URL(string: s) else { return nil }
        return Citation(title: c["title"] as? String ?? url.host() ?? s, url: url)
    }
    private var usage: TokenUsage?
    private var finished = false

    mutating func decode(_ data: String) throws -> [LLMEvent] {
        if data == "[DONE]" { return finish() }
        guard let json = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { return [] }
        if let error = json["error"] as? [String: Any] {
            throw ProviderHTTPError(status: (error["code"] as? Int) ?? 500, message: error["message"] as? String ?? "")
        }
        if let u = json["usage"] as? [String: Any] {
            usage = TokenUsage(input: u["prompt_tokens"] as? Int ?? 0, output: u["completion_tokens"] as? Int ?? 0)
        }
        var events: [LLMEvent] = []
        for choice in json["choices"] as? [[String: Any]] ?? [] {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let text = delta["content"] as? String, !text.isEmpty { events.append(.textDelta(text)) }
            let message = choice["message"] as? [String: Any] ?? [:]
            for a in (delta["annotations"] as? [[String: Any]] ?? [])
                + (message["annotations"] as? [[String: Any]] ?? [])
            {
                if let c = Self.citation(a), !seenCitations.contains(c.url) {
                    seenCitations.insert(c.url)
                    events.append(.citation(c))
                }
            }
            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let index = call["index"] as? Int ?? 0
                var t = tools[index] ?? PendingTool()
                if let id = call["id"] as? String { t.id = id }
                let fn = call["function"] as? [String: Any] ?? [:]
                if let name = fn["name"] as? String { t.name += name }
                if let args = fn["arguments"] as? String { t.arguments += args }
                tools[index] = t
            }
            if let reason = choice["finish_reason"] as? String, reason == "tool_calls" {
                events += flushTools()
            }
        }
        return events
    }

    mutating func finish() -> [LLMEvent] {
        guard !finished else { return [] }
        finished = true
        return flushTools() + [.done(usage)]
    }

    private mutating func flushTools() -> [LLMEvent] {
        defer { tools = [:] }
        return tools.keys.sorted().compactMap { i in
            let t = tools[i]!
            return t.name.isEmpty ? nil : .toolCall(ToolCall(id: t.id, name: t.name, argumentsJSON: t.arguments))
        }
    }
}
