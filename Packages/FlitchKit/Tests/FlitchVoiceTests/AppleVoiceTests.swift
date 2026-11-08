import Testing

@testable import FlitchVoice

struct AppleVoiceTests {
    typealias V = AppleVoice.VoiceInfo

    @Test func ranksPremiumThenEnhancedThenRegion() {
        let voices = [
            V(identifier: "a", name: "Amélie", language: "fr-CA", quality: 1),
            V(identifier: "b", name: "Thomas", language: "fr-FR", quality: 1),
            V(identifier: "c", name: "Audrey", language: "fr-FR", quality: 2),
            V(identifier: "d", name: "Marie", language: "fr-FR", quality: 3),
            V(identifier: "e", name: "Samantha", language: "en-US", quality: 3),
        ]
        #expect(AppleVoice.rank(voices, for: .french).map(\.identifier) == ["d", "c", "b", "a"])
        #expect(AppleVoice.rank(voices, for: .spanish).isEmpty)
    }

    /// Uses the real synthesizer when the Mac has a voice for the language.
    @Test func rendersASentence() async throws {
        guard !AppleVoice.voices(for: .english).isEmpty else { return }
        let clip = try await AppleVoice().synthesize("Hello there.", language: .english)
        #expect(clip.duration > 0.2)
    }
}
