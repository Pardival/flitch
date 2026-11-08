import FlitchCore
import Foundation
import Testing

@testable import FlitchVoice

/// `FLITCH_MEASURE=1 swift test --filter LatencyMeasurements` prints the numbers in docs/perf.md.
struct LatencyMeasurements {
    static var enabled: Bool { ProcessInfo.processInfo.environment["FLITCH_MEASURE"] == "1" }

    @Test func localVoices() async throws {
        guard Self.enabled else { return }
        let sentence = "Napoléon Bonaparte est né en 1769 à Ajaccio, en Corse."
        let clock = ContinuousClock()
        for (name, synth) in [("animal", AnimalVoice() as any SentenceSynthesizer), ("apple", AppleVoice())] {
            _ = try await synth.synthesize("Bonjour.", language: .french)  // warm up
            var total = Duration.zero
            for _ in 0..<5 {
                let start = clock.now
                _ = try await synth.synthesize(sentence, language: .french)
                total += clock.now - start
            }
            print("MEASURE \(name) synth: \(total / 5)")
        }
    }

    /// Time to the first speakable chunk for a model streaming ~60 tokens/s (≈ 4 characters per token).
    @Test func firstChunk() async throws {
        guard Self.enabled else { return }
        let answer =
            "Napoléon Bonaparte, né en 1769 à Ajaccio, devient empereur des Français en 1804, puis réforme la France."
        for early in [nil, 60] as [Int?] {
            var c = SentenceChunker(firstChunkMinLength: early)
            var chars = 0
            var t = 0.0
            var i = answer.startIndex
            while i < answer.endIndex {
                let j = answer.index(i, offsetBy: 4, limitedBy: answer.endIndex) ?? answer.endIndex
                t += 1.0 / 60
                chars += answer.distance(from: i, to: j)
                if !c.feed(String(answer[i..<j])).isEmpty { break }
                i = j
            }
            print(
                "MEASURE first chunk (early clause \(early.map(String.init) ?? "off")): \(Int(t * 1000)) ms after the first token"
            )
        }
    }
}
