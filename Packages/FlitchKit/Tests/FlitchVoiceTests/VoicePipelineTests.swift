import AVFoundation
import FlitchCore
import Foundation
import Synchronization
import Testing

@testable import FlitchVoice

/// Records what is played; `blockOn` makes one clip "play" until stopped.
final class FakePlayer: AudioPlaying, @unchecked Sendable {
    let played = Mutex<[Double]>([])
    let stops = Mutex(0)
    var blockOn: Int?

    func play(_ clip: AudioClip, onLevel: @escaping @Sendable (Float) -> Void) async throws {
        let n = played.withLock {
            $0.append(clip.duration)
            return $0.count
        }
        onLevel(0.6)
        if n == blockOn { try await Task.sleep(for: .seconds(3600)) }
    }

    func stop() { stops.withLock { $0 += 1 } }
}

/// Clip length encodes the sentence length, so we can check the order.
struct FakeSynth: SentenceSynthesizer {
    var delay: Duration = .zero
    func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        if delay > .zero { try await Task.sleep(for: delay) }
        return AudioClip(AVAudioPCMBuffer.mono([Float](repeating: 0.1, count: sentence.count * 100), sampleRate: 1000)!)
    }
}

struct VoicePipelineTests {
    static func stream(_ items: [String], error: (any Error)? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in
            items.forEach { c.yield($0) }
            if let error { c.finish(throwing: error) } else { c.finish() }
        }
    }

    @Test func playsSentencesInOrderAndAnnouncesEach() async throws {
        let player = FakePlayer()
        let started = Mutex<[String]>([])
        let levels = Mutex<[Float]>([])
        try await VoicePipeline(synthesizer: FakeSynth(delay: .milliseconds(5)), player: player).speak(
            Self.stream(["A.", "Bbbb.", "Cc."]), language: .english,
            onSentenceStart: { s in started.withLock { $0.append(s) } },
            onLevel: { l in levels.withLock { $0.append(l) } })
        #expect(started.withLock { $0 } == ["A.", "Bbbb.", "Cc."])
        #expect(player.played.withLock { $0 } == [0.2, 0.5, 0.3])
        #expect(levels.withLock { $0.last } == 0)  // mouth closes at the end
    }

    @Test func cancellingStopsPlaybackImmediately() async throws {
        let player = FakePlayer()
        player.blockOn = 1
        let task = Task {
            try await VoicePipeline(synthesizer: FakeSynth(), player: player).speak(
                Self.stream(["One.", "Two."]), language: .english, onSentenceStart: { _ in }, onLevel: { _ in })
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(player.stops.withLock { $0 } >= 1)
        #expect(player.played.withLock { $0.count } == 1)
    }

    @Test func upstreamErrorIsRethrownAfterWhatWasReady() async {
        let player = FakePlayer()
        await #expect(throws: URLError.self) {
            try await VoicePipeline(synthesizer: FakeSynth(), player: player).speak(
                Self.stream(["Ok."], error: URLError(.timedOut)), language: .english,
                onSentenceStart: { _ in }, onLevel: { _ in })
        }
    }
}
