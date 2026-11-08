@preconcurrency import AVFoundation
import FlitchCore
import Foundation
import Speech
import Synchronization

/// On-device speech-to-text with `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26).
/// Free and private: audio never leaves the Mac and is never stored.
public final class AppleSpeechRecognizer: SpeechRecognizing {
    public enum AssetState: Sendable, Equatable {
        case installed
        case downloading(Double)
        case unsupported
    }

    private let onAssetProgress: @Sendable (AssetState) -> Void

    /// `onAssetProgress` reports the one-time model download for a language.
    public init(onAssetProgress: @escaping @Sendable (AssetState) -> Void = { _ in }) {
        self.onAssetProgress = onAssetProgress
    }

    /// The transcriber locale for one of Flitch's languages, or nil if the Mac can't transcribe it.
    public static func supportedLocale(for language: AppLanguage) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: language.locale)
    }

    public func startSession(language: AppLanguage) async throws -> any RecognitionSession {
        try await AudioCapture.ensurePermission()
        // The microphone starts right away: what you say while the analyzer gets ready is kept
        // in memory and fed to it afterwards, so the first words are never lost.
        let capture = AudioCapture()
        try capture.start(format: nil)
        do {
            let transcriber = try await makeTranscriber(language: language)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let session = AppleRecognitionSession(analyzer: analyzer, transcriber: transcriber, capture: capture)
            try await session.start(format: format)
            return session
        } catch {
            capture.stop()
            throw error
        }
    }

    /// Checks the language and downloads its model ahead of time, so the first question is quick.
    public func prepare(language: AppLanguage) async {
        _ = try? await makeTranscriber(language: language)
    }

    /// Locales whose model is known to be installed (checking it again takes seconds).
    private let readyLocales = Mutex<Set<String>>([])

    private func makeTranscriber(language: AppLanguage) async throws -> SpeechTranscriber {
        guard let locale = await Self.supportedLocale(for: language) else {
            onAssetProgress(.unsupported)
            throw FlitchError.other("speech recognition isn't available in \(language.englishName) on this Mac")
        }
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        let id = locale.identifier
        if !readyLocales.withLock({ $0.contains(id) }) {
            try await installAssetsIfNeeded(for: transcriber)
            readyLocales.withLock { _ = $0.insert(id) }
        }
        return transcriber
    }

    private func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            onAssetProgress(.installed)
            return
        }
        let report = onAssetProgress
        let progress = request.progress
        let observer = progress.observe(\.fractionCompleted) { p, _ in report(.downloading(p.fractionCompleted)) }
        defer { observer.invalidate() }
        try await request.downloadAndInstall()
        report(.installed)
    }
}

/// Accumulates finalized and volatile results into the transcript shown while you talk.
struct TranscriptAccumulator: Sendable {
    private(set) var finalized = ""
    private(set) var volatile = ""

    var text: String {
        (finalized + volatile).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func add(_ text: String, isFinal: Bool) {
        if isFinal {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
    }
}

final class AppleRecognitionSession: RecognitionSession, @unchecked Sendable {
    let partialResults: AsyncStream<String>
    var levels: AsyncStream<Float> { capture.levels }

    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let capture: AudioCapture
    private let partialsContinuation: AsyncStream<String>.Continuation
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var resultsTask: Task<String, Error>?

    init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, capture: AudioCapture) {
        self.capture = capture
        self.analyzer = analyzer
        self.transcriber = transcriber
        (partialResults, partialsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start(format: AVAudioFormat?) async throws {
        let (input, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation
        let partials = partialsContinuation
        let transcriber = self.transcriber
        resultsTask = Task {
            var acc = TranscriptAccumulator()
            for try await result in transcriber.results {
                acc.add(String(result.text.characters), isFinal: result.isFinal)
                partials.yield(acc.text)
            }
            partials.finish()
            return acc.text
        }
        try await analyzer.start(inputSequence: input)
        // The capture is already running in the microphone's own format; convert to the analyzer's.
        let buffers = capture.buffers
        feedTask = Task {
            var converter: AudioFormatConverter?
            for await buffer in buffers {
                guard let format, buffer.format != format else {
                    inputContinuation.yield(AnalyzerInput(buffer: buffer))
                    continue
                }
                if converter == nil { converter = AudioFormatConverter(from: buffer.format, to: format) }
                if let converted = converter?.convert(buffer) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            inputContinuation.finish()
        }
    }

    func finish() async throws -> String {
        capture.stop()  // ends the buffer stream → feedTask finishes the analyzer input
        await feedTask?.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await resultsTask?.value ?? ""
    }

    func cancel() async {
        capture.stop()
        inputContinuation?.finish()
        feedTask?.cancel()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
        partialsContinuation.finish()
    }
}
