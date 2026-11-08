import Foundation
import Observation

/// User settings, persisted in `UserDefaults` (no secrets here: those live in the Keychain).
@MainActor
@Observable
public final class FlitchSettings {
    public enum Mode: String, Codable, Sendable, CaseIterable { case discreet, dock }

    public enum Corner: String, Codable, Sendable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        public var isTop: Bool { self == .topLeft || self == .topRight }
        public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    }

    public enum VoiceEngine: String, Codable, Sendable, CaseIterable {
        case animal, apple, elevenLabs, openAI, cartesia, mistral, gemini
        /// Engines that need an account with the voice provider.
        public var needsKey: Bool { self != .animal && self != .apple }
        /// Keychain id of the voice provider's key.
        public var credentialID: String? {
            switch self {
            case .animal, .apple: nil
            case .elevenLabs: "elevenlabs"
            case .openAI: "openai"
            case .cartesia: "cartesia"
            case .mistral: "mistral"
            case .gemini: "gemini"
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var mode: Mode { didSet { save("mode", mode.rawValue) } }
    public var corner: Corner { didSet { save("corner", corner.rawValue) } }
    public var language: AppLanguage { didSet { save("language", language.rawValue) } }
    public var launchAtLogin: Bool { didSet { save("launchAtLogin", launchAtLogin) } }
    /// "openrouter", "anthropic", "chatgpt", a preset id… nil until onboarding.
    public var providerID: String? { didSet { save("providerID", providerID) } }
    public var speed: ResponseSpeed { didSet { save("speed", speed.rawValue) } }
    /// Overrides the preset's model (empty = preset).
    public var customModel: String { didSet { save("customModel", customModel) } }
    public var webSearch: Bool { didSet { save("webSearch", webSearch) } }
    public var voiceEngine: VoiceEngine { didSet { save("voiceEngine", voiceEngine.rawValue) } }
    /// Selected voice per engine (voice id / name).
    public var voiceIDs: [String: String] { didSet { save("voiceIDs", voiceIDs) } }
    /// 0.5…2
    public var voiceSpeed: Double { didSet { save("voiceSpeed", voiceSpeed) } }
    public var tone: TonePreset { didSet { save("tone", tone.rawValue) } }
    /// Hold right ⌥ (needs Input Monitoring) or use the fallback combo.
    public var useRightOption: Bool { didSet { save("useRightOption", useRightOption) } }
    public var fallbackKeyCode: Int { didSet { save("fallbackKeyCode", fallbackKeyCode) } }
    public var fallbackModifiers: Int { didSet { save("fallbackModifiers", fallbackModifiers) } }
    public var onboardingDone: Bool { didSet { save("onboardingDone", onboardingDone) } }
    /// Shows turn timings in the bubble (latency work).
    public var showTimings: Bool { didSet { save("showTimings", showTimings) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func s(_ k: String) -> String? { defaults.string(forKey: "flitch.\(k)") }
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: "flitch.\(k)") as? Bool ?? d }
        func i(_ k: String, _ d: Int) -> Int { defaults.object(forKey: "flitch.\(k)") as? Int ?? d }
        mode = s("mode").flatMap(Mode.init) ?? .discreet
        corner = s("corner").flatMap(Corner.init) ?? .topLeft
        language = s("language").flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage(locale: .current)
        launchAtLogin = b("launchAtLogin", false)
        providerID = s("providerID")
        speed = s("speed").flatMap(ResponseSpeed.init) ?? .balanced
        customModel = s("customModel") ?? ""
        webSearch = b("webSearch", true)
        voiceEngine = s("voiceEngine").flatMap(VoiceEngine.init) ?? .animal
        voiceIDs = defaults.dictionary(forKey: "flitch.voiceIDs") as? [String: String] ?? [:]
        voiceSpeed = defaults.object(forKey: "flitch.voiceSpeed") as? Double ?? 1
        tone = s("tone").flatMap(TonePreset.init) ?? .enthusiastic
        useRightOption = b("useRightOption", true)
        fallbackKeyCode = i("fallbackKeyCode", 49)  // Space
        fallbackModifiers = i("fallbackModifiers", 0x1000 | 0x0800)  // controlKey | optionKey
        onboardingDone = b("onboardingDone", false)
        showTimings = b("showTimings", false)
    }

    public func voiceID(for engine: VoiceEngine) -> String? { voiceIDs[engine.rawValue] }
    public func setVoiceID(_ id: String?, for engine: VoiceEngine) { voiceIDs[engine.rawValue] = id }

    private func save(_ key: String, _ value: Any?) {
        if let value {
            defaults.set(value, forKey: "flitch.\(key)")
        } else {
            defaults.removeObject(forKey: "flitch.\(key)")
        }
    }
}
