@preconcurrency import AVFoundation
import FlitchCore

/// Rendered audio for one sentence. `AVAudioPCMBuffer` isn't Sendable; clips are never mutated after creation.
public struct AudioClip: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer
    public init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    public var duration: Double { Double(buffer.frameLength) / buffer.format.sampleRate }
}

/// Turns one sentence into audio. Implemented by every voice (animal, Apple, cloud voices…).
public protocol SentenceSynthesizer: Sendable {
    func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip
}

/// Plays one buffer to the end, reporting a 0…1 level for the mouth animation.
public protocol AudioPlaying: Sendable {
    func play(_ clip: AudioClip, onLevel: @escaping @Sendable (Float) -> Void) async throws
    func stop()
}

/// The speech output used by the orchestrator: synthesizes sentence N+1 while sentence N plays,
/// plays them in order, and stops at once when the task is cancelled.
public struct VoicePipeline: SpeechOutput {
    public let synthesizer: any SentenceSynthesizer
    public let player: any AudioPlaying

    public init(synthesizer: any SentenceSynthesizer, player: any AudioPlaying = EngineAudioPlayer()) {
        self.synthesizer = synthesizer
        self.player = player
    }

    public func speak(
        _ sentences: AsyncThrowingStream<String, Error>,
        language: AppLanguage,
        onSentenceStart: @escaping @Sendable (String) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        typealias Job = (sentence: String, audio: Task<AudioClip, Error>)
        let (jobs, jobsIn) = AsyncThrowingStream<Job, Error>.makeStream()
        let synthesizer = self.synthesizer
        let player = self.player

        // Start synthesizing each sentence as soon as it arrives.
        let feeder = Task {
            var started: [Task<AudioClip, Error>] = []
            do {
                for try await sentence in sentences {
                    let spoken = SpokenText.clean(sentence)
                    guard !spoken.isEmpty else { continue }
                    let audio = Task { try await synthesizer.synthesize(spoken, language: language) }
                    started.append(audio)
                    jobsIn.yield((sentence, audio))
                }
                jobsIn.finish()
            } catch {
                jobsIn.finish(throwing: error)
            }
            return started
        }

        try await withTaskCancellationHandler {
            do {
                for try await job in jobs {
                    try Task.checkCancellation()
                    let clip = try await job.audio.value
                    try Task.checkCancellation()
                    onSentenceStart(job.sentence)
                    try await player.play(clip, onLevel: onLevel)
                }
                onLevel(0)
            } catch {
                feeder.cancel()
                for t in await feeder.value { t.cancel() }
                throw error
            }
        } onCancel: {
            player.stop()
            feeder.cancel()
        }
    }
}

/// AVAudioEngine player with a level tap. One buffer at a time; `stop()` interrupts immediately.
public final class EngineAudioPlayer: AudioPlaying, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let lock = NSLock()
    private var format: AVAudioFormat?
    private var finish: CheckedContinuation<Void, Error>?
    private var levelHandler: (@Sendable (Float) -> Void)?

    public init() {
        engine.attach(node)
    }

    public func play(_ clip: AudioClip, onLevel: @escaping @Sendable (Float) -> Void) async throws {
        let buffer = clip.buffer
        try configure(for: buffer.format)
        lock.withLock { levelHandler = onLevel }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { finish = cont }
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.complete(with: nil)
            }
            if !node.isPlaying { node.play() }
        }
    }

    public func stop() {
        node.stop()
        complete(with: CancellationError())
    }

    private func complete(with error: Error?) {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { finish = nil }
            return finish
        }
        if let error { cont?.resume(throwing: error) } else { cont?.resume() }
    }

    private func configure(for newFormat: AVAudioFormat) throws {
        if let format, format == newFormat, engine.isRunning { return }
        engine.stop()
        node.removeTap(onBus: 0)
        engine.connect(node, to: engine.mainMixerNode, format: newFormat)
        node.installTap(onBus: 0, bufferSize: 1024, format: newFormat) { [weak self] buf, _ in
            let level = AudioLevel.normalizedRMS(buf)
            let handler = self?.lock.withLock { self?.levelHandler }
            handler?(level)
        }
        format = newFormat
        engine.prepare()
        try engine.start()
    }
}

extension AVAudioPCMBuffer {
    /// Float32 mono buffer from samples.
    public static func mono(_ samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
