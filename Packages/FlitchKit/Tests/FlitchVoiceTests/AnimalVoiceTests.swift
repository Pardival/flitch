import AVFoundation
import Foundation
import Testing

@testable import FlitchVoice

struct AnimalVoiceTests {
    let voice = AnimalVoice(sampleRate: 16_000)

    @Test func isDeterministic() {
        #expect(voice.render("Bonjour Kevin !") == voice.render("Bonjour Kevin !"))
        #expect(voice.render("Bonjour") != voice.render("Bonsoir"))
    }

    @Test func longerTextIsLonger() {
        #expect(voice.render("Napoléon est né en 1769 à Ajaccio.").count > voice.render("Oui.").count)
    }

    @Test func punctuationAddsPauses() {
        let plain = voice.render("un deux trois").count
        let commas = voice.render("un, deux, trois").count
        #expect(commas - plain >= Int(0.25 * 16_000))
    }

    @Test func neverClipsAndIsNotSilent() {
        let s = voice.render("Hola, ¿qué tal? ¡Muy bien!")
        #expect(s.allSatisfy { abs($0) <= 1 })
        #expect((s.map(abs).max() ?? 0) > 0.1)
    }

    @Test func faster_profiles_are_shorter() {
        let slow = AnimalVoice(profile: .init(speed: 0.8), sampleRate: 16_000).render("Bonjour tout le monde")
        let fast = AnimalVoice(profile: .init(speed: 1.6), sampleRate: 16_000).render("Bonjour tout le monde")
        #expect(fast.count < slow.count)
    }

    @Test(arguments: [("chat", 1), ("Napoléon", 3), ("aujourd'hui", 3), ("rhythm", 1), ("1769", 4), ("x", 1)])
    func syllables(word: String, expected: Int) {
        #expect(AnimalVoice.syllables(word) == expected)
    }

    @Test func everyPresetRenders() {
        for (_, p) in AnimalVoiceProfile.presets {
            #expect(!AnimalVoice(profile: p, sampleRate: 16_000).render("Salut !").isEmpty)
        }
    }

    @Test func synthesizesAPlayableClip() async throws {
        let clip = try await voice.synthesize("Coucou !", language: .french)
        #expect(clip.buffer.format.channelCount == 1)
        #expect(clip.duration > 0.1 && clip.duration < 2)
    }

    /// `FLITCH_WRITE_AUDIO=1 swift test --filter AnimalVoice` writes WAV files to audition the presets.
    @Test func writeAuditionFiles() throws {
        guard ProcessInfo.processInfo.environment["FLITCH_WRITE_AUDIO"] == "1" else { return }
        for (name, p) in AnimalVoiceProfile.presets {
            let v = AnimalVoice(profile: p)
            let buffer = AVAudioPCMBuffer.mono(
                v.render("Salut ! Je suis Flitch. Tu veux savoir quoi ?"), sampleRate: 44_100)!
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("flitch-animal-\(name).wav")
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
            print("wrote", url.path)
        }
    }
}
