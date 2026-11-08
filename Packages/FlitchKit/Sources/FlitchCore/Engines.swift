import Foundation

// The engines the orchestrator talks to. Implementations live in FlitchProviders and FlitchVoice;
// tests use fakes. Keeping the protocols here keeps FlitchCore free of any SDK.

// MARK: - LLM

/// What can a provider do beyond plain text.
public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let webSearch = ProviderCapabilities(rawValue: 1 << 0)
    public static let tools = ProviderCapabilities(rawValue: 1 << 1)
    public static let reasoningEffort = ProviderCapabilities(rawValue: 1 << 2)
}

public struct ModelInfo: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    /// US dollars per million input tokens, when the provider says (OpenRouter does, OpenAI doesn't).
    public var inputPricePerMillion: Double?
    public init(id: String, name: String? = nil, inputPricePerMillion: Double? = nil) {
        self.id = id
        self.name = name ?? id
        self.inputPricePerMillion = inputPricePerMillion
    }

    /// How expensive the model is: from its price when known, otherwise guessed from its name.
    public var cost: CostTier {
        inputPricePerMillion.map(CostTier.init(inputPricePerMillion:)) ?? CostTier(guessingFrom: id)
    }
}

/// A rough price level, shown next to each model in Settings.
public enum CostTier: Int, Sendable, Comparable, CaseIterable {
    case veryCheap, cheap, medium, expensive

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public init(inputPricePerMillion p: Double) {
        self =
            switch p {
            case ..<0.3: .veryCheap
            case ..<1.5: .cheap
            case ..<6: .medium
            default: .expensive
            }
    }

    /// Model names follow size words across providers (nano, mini, pro, Luna, Terra, Sol, Astra…).
    public init(guessingFrom id: String) {
        let id = id.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { id.contains($0) } }
        self =
            if has(["nano", "luna", "lite", "tiny"]) {
                .veryCheap
            } else if has(["mini", "flash", "terra", "haiku", "small"]) {
                .cheap
            } else if has(["-pro", "astra", "opus", "-max", "ultra"]) {
                .expensive
            } else {
                .medium
            }
    }
}

/// A function the model may call (e.g. `remember` in M4). `parametersJSON` is a JSON Schema object.
public struct ToolSpec: Sendable, Hashable {
    public var name: String
    public var description: String
    public var parametersJSON: String
    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct ToolCall: Sendable, Hashable {
    public var id: String
    public var name: String
    public var argumentsJSON: String
    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct Citation: Sendable, Hashable {
    public var title: String
    public var url: URL
    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public struct TokenUsage: Sendable, Hashable {
    public var input: Int
    public var output: Int
    public init(input: Int, output: Int) {
        self.input = input
        self.output = output
    }
}

public struct LLMRequest: Sendable {
    public var system: String
    public var messages: [ChatMessage]
    public var speed: ResponseSpeed
    public var webSearch: Bool
    public var tools: [ToolSpec]
    /// Overrides the preset's model for this speed (settings › Brain › custom model).
    public var model: String?

    public init(
        system: String, messages: [ChatMessage], speed: ResponseSpeed = .balanced, webSearch: Bool = false,
        tools: [ToolSpec] = [], model: String? = nil
    ) {
        self.system = system
        self.messages = messages
        self.speed = speed
        self.webSearch = webSearch
        self.tools = tools
        self.model = model
    }
}

public enum LLMEvent: Sendable, Hashable {
    case textDelta(String)
    case toolCall(ToolCall)
    case citation(Citation)
    case done(TokenUsage?)
}

public protocol LLMProvider: Sendable {
    /// Stable identifier, e.g. "openrouter", "anthropic".
    var id: String { get }
    /// Human name for messages ("OpenRouter", "Claude").
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    func models() async throws -> [ModelInfo]
    /// Streams the answer. Cancelling the consuming task cancels the request.
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error>
}

// MARK: - Speech in

public protocol SpeechRecognizing: Sendable {
    /// Starts capturing and transcribing. Throws `FlitchError.microphoneDenied` etc.
    func startSession(language: AppLanguage) async throws -> any RecognitionSession
}

public protocol RecognitionSession: AnyObject, Sendable {
    /// Live partial transcript (full text so far, not a delta).
    var partialResults: AsyncStream<String> { get }
    /// Microphone level 0…1 for the listening animation.
    var levels: AsyncStream<Float> { get }
    /// Stops capturing and returns the final transcript.
    func finish() async throws -> String
    /// Stops capturing and discards everything.
    func cancel() async
}

// MARK: - Speech out

public protocol SpeechOutput: Sendable {
    /// Speaks sentences in order as they arrive, pipelining synthesis and playback.
    /// Returns when the last sentence has finished playing. Must stop promptly when the task is cancelled.
    func speak(
        _ sentences: AsyncThrowingStream<String, Error>,
        language: AppLanguage,
        onSentenceStart: @escaping @Sendable (String) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws
}
