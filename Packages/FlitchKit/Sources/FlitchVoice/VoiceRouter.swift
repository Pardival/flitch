import FlitchCore
import Synchronization

/// The orchestrator's speech output; the app swaps the voice when settings change.
public final class VoiceRouter: SpeechOutput {
    private let current: Mutex<any SentenceSynthesizer>
    private let player: any AudioPlaying

    public init(synthesizer: any SentenceSynthesizer = AnimalVoice(), player: any AudioPlaying = EngineAudioPlayer()) {
        current = Mutex(synthesizer)
        self.player = player
    }

    public var synthesizer: any SentenceSynthesizer {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    public func speak(
        _ sentences: AsyncThrowingStream<String, Error>, language: AppLanguage,
        onSentenceStart: @escaping @Sendable (String) -> Void, onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        try await VoicePipeline(synthesizer: synthesizer, player: player)
            .speak(sentences, language: language, onSentenceStart: onSentenceStart, onLevel: onLevel)
    }

    /// Speaks one text outside a conversation (replay, voice preview).
    public func say(_ text: String, language: AppLanguage, with synth: (any SentenceSynthesizer)? = nil) async throws {
        var chunker = SentenceChunker()
        let parts = chunker.feed(text) + chunker.flush()
        let stream = AsyncThrowingStream<String, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        try await VoicePipeline(synthesizer: synth ?? synthesizer, player: player)
            .speak(stream, language: language, onSentenceStart: { _ in }, onLevel: { _ in })
    }

    public func stop() { player.stop() }
}

/// The orchestrator's speech-to-text; the app swaps the engine when settings change.
public final class RecognizerRouter: SpeechRecognizing {
    private let current: Mutex<any SpeechRecognizing>

    public init(_ recognizer: any SpeechRecognizing) { current = Mutex(recognizer) }

    public var recognizer: any SpeechRecognizing {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    public func startSession(language: AppLanguage) async throws -> any RecognitionSession {
        try await recognizer.startSession(language: language)
    }
}
