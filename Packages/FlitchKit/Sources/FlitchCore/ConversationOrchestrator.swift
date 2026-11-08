import Foundation

/// Where the conversation is. The stage shows the otter in every phase except `.hidden`.
public enum ConversationPhase: Sendable, Hashable {
    case hidden
    case listening
    case transcribing
    case thinking
    case speaking
    case lingering
}

/// What the stage (otter + bubble) should show. Sent in order on the main actor.
public enum ConversationEvent: Sendable, Hashable {
    case listening
    case partialTranscript(String)
    case microphoneLevel(Float)
    case transcribing
    case transcribed(String)
    case thinking
    case citation(Citation)
    /// A sentence starts playing: show it in the bubble.
    case sentence(String)
    case speakingLevel(Float)
    case answerComplete(String)
    case lingering(remaining: Duration)
    case error(FlitchError)
    case dismissed
}

/// The heart of Flitch: hold the shortcut → listen → release → transcribe → think → speak → linger → hide.
///
/// Fully headless and deterministic: time only advances through `tick(_:)` (driven by the stage's
/// display timer in the app, by the test in tests), and every engine is injected.
@MainActor
public final class ConversationOrchestrator {
    public struct Configuration: Sendable {
        /// Presses shorter than this are ignored (accidental taps).
        public var minimumPress: Duration = .milliseconds(300)
        /// How long the otter stays after the answer.
        public var lingerDuration: Duration = .seconds(15)
        /// Safety cap on one recording.
        public var maximumListening: Duration = .seconds(60)
        public init() {}
    }

    /// Everything the orchestrator needs, resolved at the start of each turn so settings changes apply.
    public struct Dependencies: Sendable {
        public var recognizer: any SpeechRecognizing
        public var speech: any SpeechOutput
        public var provider: @MainActor @Sendable () -> (any LLMProvider)?
        public var promptInput: @MainActor @Sendable () -> PromptBuilder.Input
        public var speed: @MainActor @Sendable () -> ResponseSpeed
        public var webSearch: @MainActor @Sendable () -> Bool
        public var tools: @MainActor @Sendable () -> [ToolSpec]

        public init(
            recognizer: any SpeechRecognizing,
            speech: any SpeechOutput,
            provider: @escaping @MainActor @Sendable () -> (any LLMProvider)?,
            promptInput: @escaping @MainActor @Sendable () -> PromptBuilder.Input,
            speed: @escaping @MainActor @Sendable () -> ResponseSpeed = { .balanced },
            webSearch: @escaping @MainActor @Sendable () -> Bool = { false },
            tools: @escaping @MainActor @Sendable () -> [ToolSpec] = { [] }
        ) {
            self.recognizer = recognizer
            self.speech = speech
            self.provider = provider
            self.promptInput = promptInput
            self.speed = speed
            self.webSearch = webSearch
            self.tools = tools
        }
    }

    public private(set) var phase: ConversationPhase = .hidden
    public private(set) var conversation: [ChatMessage] = []
    public var onEvent: ((ConversationEvent) -> Void)?
    /// Called when the otter hides with a non-empty conversation (history, M4).
    public var onConversationClosed: (([ChatMessage]) -> Void)?
    /// Called for each tool call the model makes (e.g. `remember`, M4).
    public var onToolCall: ((ToolCall) -> Void)?

    private let config: Configuration
    private let deps: Dependencies
    private let prompts = PromptBuilder()

    private var generation = 0
    private var sessionTask: Task<(any RecognitionSession)?, Never>?
    private var pumpTasks: [Task<Void, Never>] = []
    private var turnTask: Task<Void, Never>?
    private var pressElapsed: Duration = .zero
    private var lingerRemaining: Duration = .zero
    private var bubbleHovered = false
    private var answerSoFar = ""
    private var language: AppLanguage = .english

    public init(dependencies: Dependencies, configuration: Configuration = .init()) {
        self.deps = dependencies
        self.config = configuration
    }

    // MARK: - Inputs

    public func shortcutDown() {
        switch phase {
        case .listening:
            return
        case .hidden:
            conversation = []
        case .transcribing, .thinking, .speaking:
            interruptTurn()
        case .lingering:
            break  // follow-up: keep the conversation
        }
        cancelTurn()
        startListening()
    }

    public func shortcutUp() {
        guard phase == .listening else { return }
        let session = sessionTask
        stopPumps()
        if pressElapsed < config.minimumPress {
            Task { await session?.value?.cancel() }
            hide()
            return
        }
        setPhase(.transcribing)
        emit(.transcribing)
        let gen = generation
        turnTask = Task { [weak self] in await self?.runTurn(session: session, generation: gen) }
    }

    /// Advances time. Call it from a display timer (~60 Hz) in the app.
    public func tick(_ dt: Duration) {
        switch phase {
        case .listening:
            pressElapsed += dt
            if pressElapsed >= config.maximumListening { shortcutUp() }
        case .lingering where !bubbleHovered:
            lingerRemaining -= dt
            if lingerRemaining <= .zero {
                hide()
            } else {
                emit(.lingering(remaining: lingerRemaining))
            }
        default:
            break
        }
    }

    /// Hovering the bubble pauses the linger countdown.
    public func setBubbleHovered(_ hovered: Bool) { bubbleHovered = hovered }

    /// Hides the otter now (click on close, Escape…).
    public func dismiss() { hide() }

    /// Waits for the current turn to finish (tests, shutdown).
    public func waitForTurn() async {
        await turnTask?.value
    }

    // MARK: - Turn

    private func startListening() {
        lastFailedQuestion = nil
        generation += 1
        let gen = generation
        pressElapsed = .zero
        language = deps.promptInput().language
        setPhase(.listening)
        emit(.listening)
        let recognizer = deps.recognizer
        let lang = language
        let task = Task<(any RecognitionSession)?, Never> { [weak self] in
            do {
                let session = try await recognizer.startSession(language: lang)
                guard let self, self.generation == gen else {
                    await session.cancel()
                    return nil
                }
                self.startPumps(session, generation: gen)
                return session
            } catch {
                self?.fail(error, generation: gen)
                return nil
            }
        }
        sessionTask = task
    }

    private func startPumps(_ session: any RecognitionSession, generation gen: Int) {
        pumpTasks = [
            Task { [weak self] in
                for await text in session.partialResults {
                    guard let self, self.generation == gen, self.phase == .listening else { break }
                    self.emit(.partialTranscript(text))
                }
            },
            Task { [weak self] in
                for await level in session.levels {
                    guard let self, self.generation == gen, self.phase == .listening else { break }
                    self.emit(.microphoneLevel(level))
                }
            },
        ]
    }

    private func stopPumps() {
        pumpTasks.forEach { $0.cancel() }
        pumpTasks = []
    }

    private func runTurn(session sessionTask: Task<(any RecognitionSession)?, Never>?, generation gen: Int) async {
        guard let session = await sessionTask?.value else { return }  // failure already reported
        let heard: String
        do {
            heard = try await session.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            fail(error, generation: gen)
            return
        }
        guard generation == gen, !Task.isCancelled else { return }
        guard !heard.isEmpty else {
            hide()
            return
        }
        emit(.transcribed(heard))
        await respond(to: heard, generation: gen)
    }

    /// Asks the model again after a failure (bubble's "Try again").
    public func retry() {
        guard phase == .lingering, let question = lastFailedQuestion else { return }
        lastFailedQuestion = nil
        cancelTurn()
        let gen = generation
        turnTask = Task { [weak self] in await self?.respond(to: question, generation: gen) }
    }

    /// The question that failed and can be retried.
    public private(set) var lastFailedQuestion: String?

    private func respond(to heard: String, generation gen: Int) async {
        conversation.append(.user(heard))
        setPhase(.thinking)
        emit(.thinking)

        guard let provider = deps.provider() else {
            fail(FlitchError.noProvider, generation: gen)
            return
        }
        let request = LLMRequest(
            system: prompts.systemPrompt(deps.promptInput()),
            messages: conversation,
            speed: deps.speed(),
            webSearch: deps.webSearch() && provider.capabilities.contains(.webSearch),
            tools: provider.capabilities.contains(.tools) ? deps.tools() : []
        )
        answerSoFar = ""
        let (sentences, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let producer = Task { [weak self] in
            var chunker = SentenceChunker()
            do {
                for try await event in provider.stream(request) {
                    try Task.checkCancellation()
                    guard let self, self.generation == gen else { break }
                    switch event {
                    case .textDelta(let delta):
                        self.answerSoFar += delta
                        for s in chunker.feed(delta) { continuation.yield(s) }
                    case .citation(let c):
                        self.emit(.citation(c))
                    case .toolCall(let call):
                        self.onToolCall?(call)
                    case .done:
                        break
                    }
                }
                for s in chunker.flush() { continuation.yield(s) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        do {
            try await deps.speech.speak(
                sentences, language: language,
                onSentenceStart: { [weak self] sentence in
                    Task { @MainActor in self?.sentenceStarted(sentence, generation: gen) }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        guard let self, self.generation == gen, self.phase == .speaking else { return }
                        self.emit(.speakingLevel(level))
                    }
                })
        } catch {
            producer.cancel()
            fail(error, generation: gen)
            return
        }
        await producer.value
        // let queued sentence callbacks land before we close the turn
        await Task.yield()
        guard generation == gen, !Task.isCancelled else { return }

        let answer = answerSoFar.trimmingCharacters(in: .whitespacesAndNewlines)
        answerSoFar = ""
        guard !answer.isEmpty else {
            fail(FlitchError.other("empty answer"), generation: gen)
            return
        }
        conversation.append(.assistant(answer))
        emit(.answerComplete(answer))
        startLingering()
    }

    private func sentenceStarted(_ sentence: String, generation gen: Int) {
        guard generation == gen else { return }
        if phase == .thinking { setPhase(.speaking) }
        guard phase == .speaking else { return }
        emit(.sentence(sentence))
    }

    // MARK: - Ending

    private func startLingering() {
        lingerRemaining = config.lingerDuration
        setPhase(.lingering)
        emit(.lingering(remaining: lingerRemaining))
    }

    private func fail(_ error: any Error, generation gen: Int) {
        guard generation == gen, let flitchError = FlitchError(error) else { return }
        FlitchLog.error(flitchError)
        stopPumps()
        if conversation.last?.role == .user {
            lastFailedQuestion = conversation.removeLast().text
        }
        emit(.error(flitchError))
        startLingering()
    }

    /// Keeps what was already said so a follow-up makes sense.
    private func interruptTurn() {
        let partial = answerSoFar.trimmingCharacters(in: .whitespacesAndNewlines)
        if phase == .speaking, !partial.isEmpty, conversation.last?.role == .user {
            conversation.append(.assistant(partial + " …"))
        } else if conversation.last?.role == .user {
            conversation.removeLast()  // the question was never answered
        }
        answerSoFar = ""
    }

    private func cancelTurn() {
        generation += 1
        turnTask?.cancel()
        turnTask = nil
        stopPumps()
        if let session = sessionTask {
            sessionTask = nil
            Task { await session.value?.cancel() }
        }
    }

    private func hide() {
        cancelTurn()
        bubbleHovered = false
        if phase != .hidden {
            setPhase(.hidden)
            emit(.dismissed)
        }
        if !conversation.isEmpty {
            let closed = conversation
            conversation = []
            onConversationClosed?(closed)
        }
    }

    private func setPhase(_ p: ConversationPhase) { phase = p }
    private func emit(_ e: ConversationEvent) { onEvent?(e) }
}
