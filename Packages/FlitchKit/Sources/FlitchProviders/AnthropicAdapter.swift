import FlitchCore
import Foundation

/// Claude through the Messages API (raw HTTP + SSE; there is no official Swift SDK).
public struct AnthropicAdapter: LLMProvider {
    public static let apiVersion = "2026-10-21"
    public static let baseURL = URL(string: "https://api.anthropic.com/v1")!

    /// Fast / Balanced / Precise → model + effort. Thinking is left to each model's default
    /// (adaptive); depth is controlled with `output_config.effort`.
    public static func model(for speed: ResponseSpeed) -> (model: String, effort: String) {
        switch speed {
        case .fast: ("claude-haiku-5-5", "low")
        case .balanced: ("claude-sonnet-5-5", "low")
        case .precise: ("claude-opus-5-5", "medium")
        }
    }

    public let id = "anthropic"
    public let displayName = "Claude"
    public let capabilities: ProviderCapabilities = [.webSearch, .tools, .reasoningEffort]

    private let apiKey: String
    private let baseURL: URL
    private let http: HTTPTransport

    public init(apiKey: String, baseURL: URL = AnthropicAdapter.baseURL, http: HTTPTransport = .makeDefault()) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.http = http
    }

    public func models() async throws -> [ModelInfo] {
        ResponseSpeed.allCases.map { ModelInfo(id: Self.model(for: $0).model) }
    }

    /// Checks the key with a free call (lists models).
    public func verifyKey() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        do {
            _ = try await http.data(req)
        } catch {
            throw FlitchError.fromProvider(error, provider: displayName, secrets: [apiKey])
        }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let lines = try await http.lines(try makeRequest(request))
                    var decoder = AnthropicStreamDecoder()
                    for try await event in lines.sseEvents() {
                        try Task.checkCancellation()
                        for e in try decoder.decode(event.data) { continuation.yield(e) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: FlitchError.fromProvider(error, provider: displayName, secrets: [apiKey]))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(_ request: LLMRequest) throws -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("messages"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let (model, effort) = Self.model(for: request.speed)
        var tools: [[String: Any]] = []
        if request.webSearch {
            tools.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 3])
        }
        for tool in request.tools {
            let schema = try JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8))
            tools.append(["name": tool.name, "description": tool.description, "input_schema": schema])
        }
        var body: [String: Any] = [
            "model": request.model ?? model,
            "max_tokens": 4096,
            "stream": true,
            "system": request.system,
            "output_config": ["effort": effort],
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}

/// Decodes Messages API stream events into `LLMEvent`s (pure, tested with fixtures).
struct AnthropicStreamDecoder {
    private var toolBlocks: [Int: (id: String, name: String, json: String)] = [:]
    private var inputTokens = 0
    private var outputTokens = 0

    mutating func decode(_ data: String) throws -> [LLMEvent] {
        guard let json = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
            let type = json["type"] as? String
        else { return [] }

        switch type {
        case "message_start":
            let usage = (json["message"] as? [String: Any])?["usage"] as? [String: Any]
            inputTokens = usage?["input_tokens"] as? Int ?? 0
        case "content_block_start":
            let index = json["index"] as? Int ?? 0
            let block = json["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "tool_use" {
                toolBlocks[index] = (block["id"] as? String ?? "", block["name"] as? String ?? "", "")
            }
        case "content_block_delta":
            let index = json["index"] as? Int ?? 0
            let delta = json["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta":
                if let t = delta["text"] as? String, !t.isEmpty { return [.textDelta(t)] }
            case "input_json_delta":
                toolBlocks[index]?.json += delta["partial_json"] as? String ?? ""
            case "citations_delta":
                let c = delta["citation"] as? [String: Any] ?? [:]
                if let s = c["url"] as? String, let url = URL(string: s) {
                    return [.citation(Citation(title: c["title"] as? String ?? url.host() ?? s, url: url))]
                }
            default:
                break  // thinking_delta, signature_delta…
            }
        case "content_block_stop":
            let index = json["index"] as? Int ?? 0
            if let t = toolBlocks.removeValue(forKey: index) {
                return [.toolCall(ToolCall(id: t.id, name: t.name, argumentsJSON: t.json.isEmpty ? "{}" : t.json))]
            }
        case "message_delta":
            let usage = json["usage"] as? [String: Any]
            outputTokens = usage?["output_tokens"] as? Int ?? outputTokens
            if (json["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                throw FlitchError.other("Claude declined to answer this one.")
            }
        case "message_stop":
            return [.done(TokenUsage(input: inputTokens, output: outputTokens))]
        case "error":
            let e = json["error"] as? [String: Any] ?? [:]
            let kind = e["type"] as? String ?? ""
            let status =
                switch kind {
                case "authentication_error", "permission_error": 401
                case "rate_limit_error": 429
                case "overloaded_error": 529
                default: 500
                }
            throw ProviderHTTPError(status: status, message: e["message"] as? String ?? kind)
        default:
            break  // ping
        }
        return []
    }
}
