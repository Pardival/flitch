import Foundation
import Testing

@testable import FlitchCore

// MARK: - Fakes

final class FakeSession: RecognitionSession, @unchecked Sendable {
    let final: String
    let partialResults: AsyncStream<String>
    let levels: AsyncStream<Float>
    private(set) var cancelled = false

    init(final: String, partials: [String] = []) {
        self.final = final
        partialResults = AsyncStream { c in
            partials.forEach { c.yield($0) }
            c.finish()
        }
        levels = AsyncStream { c in
            c.yield(0.5)
            c.finish()
        }
    }

    func finish() async throws -> String { final }
    func cancel() async { cancelled = true }
}

final class FakeRecognizer: SpeechRecognizing, @unchecked Sendable {
    var finals: [String]
    var error: (any Error)?
    private(set) var sessions: [FakeSession] = []

    init(_ finals: String..., error: (any Error)? = nil) {
        self.finals = finals
        self.error = error
    }

    func startSession(language: AppLanguage) async throws -> any RecognitionSession {
        if let error { throw error }
        let s = FakeSession(final: finals.isEmpty ? "" : finals.removeFirst(), partials: ["Hel", "Hello"])
        sessions.append(s)
        return s
    }
}

final class FakeLLM: LLMProvider, @unchecked Sendable {
    let id = "fake"
    let displayName = "Fake"
    var capabilities: ProviderCapabilities = [.webSearch]
    var replies: [[LLMEvent]]
    var error: (any Error)?
    private(set) var requests: [LLMRequest] = []

    init(replies: [[LLMEvent]], error: (any Error)? = nil) {
        self.replies = replies
        self.error = error
    }

    static func text(_ deltas: String...) -> [LLMEvent] { deltas.map { .textDelta($0) } + [.done(nil)] }

    func models() async throws -> [ModelInfo] { [] }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        requests.append(request)
        let events = replies.isEmpty ? [] : replies.removeFirst()
        let error = self.error
        return AsyncThrowingStream { c in
            events.forEach { c.yield($0) }
            if let error { c.finish(throwing: error) } else { c.finish() }
        }
    }
}

/// Plays sentences instantly, or blocks forever on sentence number `blockAt` (to test interrupts).
final class FakeSpeech: SpeechOutput, @unchecked Sendable {
    var blockAt: Int?
    private(set) var spoken: [String] = []

    init(blockAt: Int? = nil) { self.blockAt = blockAt }

    func speak(
        _ sentences: AsyncThrowingStream<String, Error>, language: AppLanguage,
        onSentenceStart: @escaping @Sendable (String) -> Void, onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        for try await s in sentences {
            onSentenceStart(s)
            onLevel(0.7)
            spoken.append(s)
            if let blockAt, spoken.count == blockAt {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

// MARK: - Tests

@MainActor
struct ConversationOrchestratorTests {
    let recognizer: FakeRecognizer
    let llm: FakeLLM?
    let speech: FakeSpeech
    let orchestrator: ConversationOrchestrator
    let log: EventLog

    final class EventLog {
        var events: [ConversationEvent] = []
        var closed: [[ChatMessage]] = []
    }

    init(
        recognizer: FakeRecognizer = FakeRecognizer("Hello"),
        llm: FakeLLM? = FakeLLM(replies: [FakeLLM.text("Bonjour. ", "Ça ", "va ?")]),
        speech: FakeSpeech = FakeSpeech()
    ) {
        self.recognizer = recognizer
        self.llm = llm
        self.speech = speech
        let deps = ConversationOrchestrator.Dependencies(
            recognizer: recognizer, speech: speech, provider: { llm },
            promptInput: { PromptBuilder.Input(persona: "You are Flitch.", language: .french) },
            webSearch: { true })
        orchestrator = ConversationOrchestrator(dependencies: deps)
        let log = EventLog()
        self.log = log
        orchestrator.onEvent = { log.events.append($0) }
        orchestrator.onConversationClosed = { log.closed.append($0) }
    }

    /// Hold the shortcut for `seconds`, release, and wait for the whole turn.
    func ask(holding seconds: Double = 1) async {
        orchestrator.shortcutDown()
        await settle()
        orchestrator.tick(.milliseconds(Int(seconds * 1000)))
        orchestrator.shortcutUp()
        await orchestrator.waitForTurn()
        await settle()
    }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func fullTurnSpeaksSentencesThenLingers() async {
        await ask()
        #expect(orchestrator.phase == .lingering)
        #expect(speech.spoken == ["Bonjour.", "Ça va ?"])
        #expect(orchestrator.conversation == [.user("Hello"), .assistant("Bonjour. Ça va ?")])
        let e = log.events
        #expect(e.first == .listening)
        #expect(e.contains(.partialTranscript("Hello")))
        #expect(e.contains(.transcribed("Hello")))
        #expect(e.contains(.thinking))
        #expect(e.contains(.sentence("Bonjour.")))
        #expect(e.contains(.sentence("Ça va ?")))
        #expect(e.contains(.answerComplete("Bonjour. Ça va ?")))
        #expect(e.last == .lingering(remaining: .seconds(15)))
        let order = [
            ConversationEvent.listening, .transcribing, .thinking, .sentence("Bonjour."),
            .answerComplete("Bonjour. Ça va ?"),
        ]
        .compactMap { e.firstIndex(of: $0) }
        #expect(order == order.sorted() && order.count == 5)
    }

    @Test func requestCarriesSystemPromptConversationAndWebSearch() async throws {
        await ask()
        let r = try #require(llm?.requests.first)
        #expect(r.system.hasPrefix("You are Flitch."))
        #expect(r.messages == [.user("Hello")])
        #expect(r.webSearch)
    }

    @Test func shortPressIsIgnored() async {
        await ask(holding: 0.1)
        #expect(orchestrator.phase == .hidden)
        #expect(llm?.requests.isEmpty == true)
        #expect(log.events.last == .dismissed)
    }

    @Test func silenceSaysNothingWasHeardWithoutCallingTheModel() async {
        let t = ConversationOrchestratorTests(recognizer: FakeRecognizer("   "))
        await t.ask()
        #expect(t.log.events.contains(.error(.nothingHeard)))
        #expect(t.orchestrator.phase == .lingering)
        #expect(t.llm?.requests.isEmpty == true)
    }

    @Test func lingersFifteenSecondsThenHidesAndClosesConversation() async {
        await ask()
        orchestrator.tick(.seconds(14))
        #expect(orchestrator.phase == .lingering)
        orchestrator.tick(.seconds(1))
        #expect(orchestrator.phase == .hidden)
        #expect(log.events.last == .dismissed)
        #expect(log.closed == [[.user("Hello"), .assistant("Bonjour. Ça va ?")]])
        #expect(orchestrator.conversation.isEmpty)
    }

    @Test func hoveringTheBubblePausesTheCountdown() async {
        await ask()
        orchestrator.setBubbleHovered(true)
        orchestrator.tick(.seconds(60))
        #expect(orchestrator.phase == .lingering)
        orchestrator.setBubbleHovered(false)
        orchestrator.tick(.seconds(15))
        #expect(orchestrator.phase == .hidden)
    }

    @Test func followUpWhileLingeringKeepsTheContext() async throws {
        let llm = FakeLLM(replies: [FakeLLM.text("Né en 1769."), FakeLLM.text("À Ajaccio.")])
        let t = ConversationOrchestratorTests(recognizer: FakeRecognizer("Napoléon ?", "Où ?"), llm: llm)
        await t.ask()
        await t.ask()
        let second = try #require(llm.requests.last)
        #expect(second.messages == [.user("Napoléon ?"), .assistant("Né en 1769."), .user("Où ?")])
        #expect(t.orchestrator.conversation.count == 4)
    }

    @Test func pressingWhileSpeakingInterruptsAndListensAgain() async {
        let t = ConversationOrchestratorTests(
            llm: FakeLLM(replies: [FakeLLM.text("One. ", "Two. ", "Three.")]), speech: FakeSpeech(blockAt: 1))
        t.orchestrator.shortcutDown()
        await t.settle()
        t.orchestrator.tick(.seconds(1))
        t.orchestrator.shortcutUp()
        await t.settle()
        #expect(t.orchestrator.phase == .speaking)
        t.orchestrator.shortcutDown()
        #expect(t.orchestrator.phase == .listening)
        await t.settle()
        #expect(t.speech.spoken == ["One."])
        #expect(t.orchestrator.conversation.first == .user("Hello"))
        #expect(t.orchestrator.conversation.last?.role == .assistant)
    }

    @Test func noProviderShowsAFriendlyError() async {
        let t = ConversationOrchestratorTests(llm: nil)
        await t.ask()
        #expect(t.log.events.contains(.error(.noProvider)))
        #expect(t.orchestrator.phase == .lingering)
        #expect(t.orchestrator.conversation.isEmpty)
    }

    @Test func providerErrorsAreMapped() async {
        let t = ConversationOrchestratorTests(llm: FakeLLM(replies: [[]], error: URLError(.notConnectedToInternet)))
        await t.ask()
        #expect(t.log.events.contains(.error(.offline)))
    }

    @Test func microphoneErrorIsReported() async {
        let t = ConversationOrchestratorTests(recognizer: FakeRecognizer(error: FlitchError.microphoneDenied))
        t.orchestrator.shortcutDown()
        await t.settle()
        #expect(t.log.events.contains(.error(.microphoneDenied)))
        #expect(t.orchestrator.phase == .lingering)
    }

    @Test func maximumListeningReleasesAutomatically() async {
        orchestrator.shortcutDown()
        await settle()
        orchestrator.tick(.seconds(61))
        #expect(orchestrator.phase == .transcribing)
        await orchestrator.waitForTurn()
    }

    @Test func dismissHidesImmediately() async {
        await ask()
        orchestrator.dismiss()
        #expect(orchestrator.phase == .hidden)
        #expect(log.closed.count == 1)
    }
}

@MainActor
struct OrchestratorRetryTests {
    @Test func retryAsksTheFailedQuestionAgain() async throws {
        let llm = FakeLLM(replies: [[], FakeLLM.text("Né en 1769.")], error: URLError(.timedOut))
        let t = ConversationOrchestratorTests(recognizer: FakeRecognizer("Napoléon ?"), llm: llm)
        await t.ask()
        #expect(t.log.events.contains(.error(.offline)))
        #expect(t.orchestrator.lastFailedQuestion == "Napoléon ?")
        #expect(t.orchestrator.conversation.isEmpty)
        llm.error = nil
        t.orchestrator.retry()
        await t.orchestrator.waitForTurn()
        await t.settle()
        #expect(t.orchestrator.conversation == [.user("Napoléon ?"), .assistant("Né en 1769.")])
        #expect(t.orchestrator.phase == .lingering)
    }
}

@MainActor
struct OrchestratorTimingTests {
    @Test func timingsAreReportedWithTheAnswer() async throws {
        let t = ConversationOrchestratorTests()
        await t.ask()
        let timings = t.log.events.compactMap { if case .timings(let x) = $0 { x } else { nil } }
        let first = try #require(timings.first)
        #expect(
            first.transcript != nil && first.firstToken != nil && first.firstSentence != nil && first.firstAudio != nil)
        #expect(first.summary.count == 4)
    }
}

@MainActor
struct RememberToolTests {
    static let call = ToolCall(id: "1", name: "remember", argumentsJSON: #"{"fact":" Supports FC Barcelona "}"#)

    @Test func parsesTheFact() {
        #expect(RememberTool.fact(from: Self.call) == "Supports FC Barcelona")
        #expect(RememberTool.fact(from: .init(id: "2", name: "other", argumentsJSON: #"{"fact":"x"}"#)) == nil)
        #expect(RememberTool.fact(from: .init(id: "3", name: "remember", argumentsJSON: "{oops")) == nil)
        #expect(RememberTool.fact(from: .init(id: "4", name: "remember", argumentsJSON: #"{"fact":"  "}"#)) == nil)
    }

    @Test func specIsValidJSONSchema() throws {
        let schema = try JSONSerialization.jsonObject(with: Data(RememberTool.spec.parametersJSON.utf8))
        #expect((schema as? [String: Any])?["required"] as? [String] == ["fact"])
    }

    @Test func toolCallsReachTheAppAndAToolOnlyAnswerIsNotAnError() async {
        let llm = FakeLLM(replies: [[.toolCall(Self.call), .done(nil)]])
        llm.capabilities = [.tools]
        let t = ConversationOrchestratorTests(recognizer: FakeRecognizer("Je supporte le Barça"), llm: llm)
        var calls: [ToolCall] = []
        t.orchestrator.onToolCall = { calls.append($0) }
        await t.ask()
        #expect(calls == [Self.call])
        #expect(t.orchestrator.phase == .lingering)
        #expect(!t.log.events.contains { if case .error = $0 { true } else { false } })
    }

    @Test func promptOffersRememberOnlyWhenEnabled() {
        let on = PromptBuilder().systemPrompt(.init(persona: "P", canRemember: true))
        let off = PromptBuilder().systemPrompt(.init(persona: "P"))
        #expect(on.contains("remember tool") && !off.contains("remember tool"))
    }
}
