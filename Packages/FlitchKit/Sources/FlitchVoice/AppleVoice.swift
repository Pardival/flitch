@preconcurrency import AVFoundation
import FlitchCore
import Foundation

/// The Mac's own voices (`AVSpeechSynthesizer`): free and offline.
/// Sentences are rendered to buffers so they go through the same playback queue and level meter.
public struct AppleVoice: SentenceSynthesizer {
    /// Where users download better (Enhanced / Premium) voices.
    public static let downloadVoicesURL = URL(
        string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent")!

    /// A specific voice identifier, or nil to pick the best one for the language.
    public var voiceIdentifier: String?
    public var rate: Float

    public init(voiceIdentifier: String? = nil, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
    }

    public struct VoiceInfo: Sendable, Hashable {
        public var identifier: String
        public var name: String
        public var language: String
        public var quality: Int  // 1 default, 2 enhanced, 3 premium
    }

    /// Installed voices for a language, best first (Premium, then Enhanced, then default).
    public static func voices(for language: AppLanguage) -> [VoiceInfo] {
        let all = AVSpeechSynthesisVoice.speechVoices().map {
            VoiceInfo(identifier: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue)
        }
        return rank(all, for: language)
    }

    /// Pure ranking used by `voices(for:)` (tested): language match, quality, then preferred regions.
    static func rank(_ voices: [VoiceInfo], for language: AppLanguage) -> [VoiceInfo] {
        let preferredRegion = ["en": "en-US", "fr": "fr-FR", "es": "es-ES"][language.rawValue] ?? ""
        return
            voices
            .filter { $0.language.hasPrefix(language.rawValue) }
            .sorted {
                if $0.quality != $1.quality { return $0.quality > $1.quality }
                let a = $0.language == preferredRegion
                let b = $1.language == preferredRegion
                if a != b { return a }
                return $0.name < $1.name
            }
    }

    /// True when only default-quality voices are installed for the language (suggest downloading).
    public static func shouldSuggestBetterVoices(for language: AppLanguage) -> Bool {
        (voices(for: language).first?.quality ?? 1) < 2
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.rate = rate
        let id = voiceIdentifier ?? Self.voices(for: language).first?.identifier
        utterance.voice =
            id.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: language.rawValue)
        return AudioClip(try await AppleVoiceRenderer().render(utterance))
    }
}

/// Collects `AVSpeechSynthesizer.write` buffers into one float buffer.
private final class AppleVoiceRenderer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var samples: [Float] = []
    private var sampleRate: Double = 22_050

    func render(_ utterance: AVSpeechUtterance) async throws -> AVAudioPCMBuffer {
        let renderer = self
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {  // end of utterance
                    if once.fire() { cont.resume() }
                    return
                }
                renderer.append(pcm)
            }
        }
        guard let out = AVAudioPCMBuffer.mono(samples, sampleRate: sampleRate) else {
            throw FlitchError.other("Apple voice: no audio")
        }
        return out
    }

    private func append(_ pcm: AVAudioPCMBuffer) {
        sampleRate = pcm.format.sampleRate
        let n = Int(pcm.frameLength)
        if let f = pcm.floatChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: f, count: n))
        } else if let i = pcm.int16ChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: i, count: n).map { Float($0) / 32_768 })
        }
    }

    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func fire() -> Bool {
            lock.withLock {
                defer { done = true }
                return !done
            }
        }
    }
}
