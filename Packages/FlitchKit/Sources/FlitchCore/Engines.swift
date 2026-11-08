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
    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name ?? id
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
