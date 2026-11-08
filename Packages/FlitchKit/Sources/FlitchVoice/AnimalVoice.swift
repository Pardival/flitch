@preconcurrency import AVFoundation
import FlitchCore
import Foundation

/// How a character "talks" in animal language. Comes from the character pack (`pack.json`).
public struct AnimalVoiceProfile: Codable, Sendable, Hashable {
    public enum Timbre: String, Codable, Sendable, CaseIterable {
        /// Round and bright (sine + soft 2nd harmonic): the otter.
        case squeak
        /// Gentle and breathy (sine, slow attack).
        case soft
        /// Short and birdy (triangle, fast pitch glide).
        case chirp
        /// Low and warm (more harmonics).
        case hum
    }

    /// Base pitch in Hz.
    public var pitch: Double
    public var timbre: Timbre
    /// 1 = normal; higher is faster.
    public var speed: Double
    /// 0…0.5: how much pitch varies between syllables.
    public var randomness: Double

    public init(pitch: Double = 520, timbre: Timbre = .squeak, speed: Double = 1.1, randomness: Double = 0.18) {
        self.pitch = pitch
        self.timbre = timbre
        self.speed = speed
        self.randomness = randomness
    }

    public static let otter = AnimalVoiceProfile()
    public static let presets: [String: AnimalVoiceProfile] = [
        "otter": .otter,
        "mouse": .init(pitch: 820, timbre: .chirp, speed: 1.35, randomness: 0.22),
        "cat": .init(pitch: 600, timbre: .soft, speed: 1.0, randomness: 0.25),
        "bear": .init(pitch: 230, timbre: .hum, speed: 0.85, randomness: 0.12),
        "bird": .init(pitch: 1100, timbre: .chirp, speed: 1.5, randomness: 0.3),
    ]
}

/// Free, instant, offline voice: one pitched blip per syllable, following the text's rhythm.
/// Deterministic: the same word always "sounds" the same. Works in any language.
public struct AnimalVoice: SentenceSynthesizer {
    public var profile: AnimalVoiceProfile
    public var sampleRate: Double
    /// Peak amplitude: pleasant at low volume, never clipping.
    public var volume: Float

    public init(profile: AnimalVoiceProfile = .otter, sampleRate: Double = 44_100, volume: Float = 0.35) {
        self.profile = profile
        self.sampleRate = sampleRate
        self.volume = volume
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        guard let buffer = AVAudioPCMBuffer.mono(render(sentence), sampleRate: sampleRate) else {
            throw FlitchError.other("animal voice: cannot allocate audio")
        }
        return AudioClip(buffer)
    }

    // MARK: - Rendering (pure)

    /// Renders text to mono float samples.
    public func render(_ text: String) -> [Float] {
        var out: [Float] = []
        let tokens = Self.tokenize(text)
        let lastWord = tokens.lastIndex { if case .word = $0 { true } else { false } }
        let isQuestion = text.contains("?") || text.contains("¿")
        for (i, token) in tokens.enumerated() {
            switch token {
            case .word(let word):
                let seed = Self.hash(word.lowercased())
                let count = Self.syllables(word)
                for s in 0..<count {
                    let r = Self.unit(seed, s)  // 0…1, deterministic
                    var pitch = profile.pitch * (1 + (r - 0.5) * 2 * profile.randomness)
                    var glide = (Self.unit(seed, s + 97) - 0.5) * 0.15
                    if isQuestion && i == lastWord && s == count - 1 {
                        pitch *= 1.12
                        glide = 0.25
                    }
                    let duration = (0.075 + 0.035 * Self.unit(seed, s + 31)) / profile.speed
                    out += blip(pitch: pitch, glide: glide, duration: duration)
                    out += silence(0.018 / profile.speed)
                }
                out += silence(0.035 / profile.speed)
            case .pause(let seconds):
                out += silence(seconds / profile.speed)
            }
        }
        return out
    }

    private func blip(pitch: Double, glide: Double, duration: Double) -> [Float] {
        let n = max(1, Int(duration * sampleRate))
        let attack: Double = profile.timbre == .soft ? 0.25 : 0.08
        var phase = 0.0
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = pitch * (1 + glide * t) * (1 + 0.012 * sin(2 * .pi * 7 * Double(i) / sampleRate))
            phase += 2 * .pi * f / sampleRate
            let wave: Double =
                switch profile.timbre {
                case .squeak: sin(phase) + 0.25 * sin(2 * phase)
                case .soft: sin(phase)
                case .chirp: 2 / .pi * asin(sin(phase))  // triangle
                case .hum: sin(phase) + 0.4 * sin(2 * phase) + 0.2 * sin(3 * phase)
                }
            // attack then smooth decay
            let env = t < attack ? t / attack : pow(1 - (t - attack) / (1 - attack), 1.6)
            samples[i] = Float(wave * env) * volume / 1.25
        }
        return samples
    }

    private func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: max(0, Int(seconds * sampleRate)))
    }

    // MARK: - Text

    enum Token: Equatable {
        case word(String)
        case pause(Double)
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var word = ""
        func flush() {
            if !word.isEmpty { tokens.append(.word(word)) }
            word = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "’" {
                word.append(ch)
                continue
            }
            flush()
            switch ch {
            case ",", ";", ":", "—", "–": tokens.append(.pause(0.15))
            case ".", "!", "?", "…": tokens.append(.pause(0.25))
            default: break
            }
        }
        flush()
        return tokens
    }

    /// Rough syllable count: groups of vowels (any Latin script), 1…4 per word; numbers by digits.
    static func syllables(_ word: String) -> Int {
        if word.allSatisfy(\.isNumber) { return min(4, max(1, word.count)) }
        let vowels = Set("aeiouyàâäéèêëîïôöùûüÿáíóúœæ")
        var count = 0
        var inVowel = false
        for ch in word.lowercased() {
            let v = vowels.contains(ch)
            if v && !inVowel { count += 1 }
            inVowel = v
        }
        return min(4, max(1, count))
    }

    /// FNV-1a: stable across runs (unlike `hashValue`).
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    static func unit(_ seed: UInt64, _ n: Int) -> Double {
        var x = seed &+ UInt64(n) &* 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }
}
