import Foundation

/// Languages Flitch speaks and is localized in.
public enum AppLanguage: String, Sendable, Codable, CaseIterable {
    case english = "en"
    case french = "fr"
    case spanish = "es"

    public var locale: Locale { Locale(identifier: rawValue) }

    /// English name, used inside prompts.
    public var englishName: String {
        switch self {
        case .english: "English"
        case .french: "French"
        case .spanish: "Spanish"
        }
    }

    /// Best match for a locale; English by default.
    public init(locale: Locale) {
        let code = locale.language.languageCode?.identifier ?? "en"
        self = AppLanguage(rawValue: code) ?? .english
    }
}

/// One message of a conversation.
public struct ChatMessage: Sendable, Codable, Equatable, Hashable {
    public enum Role: String, Sendable, Codable { case user, assistant }
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }

    public static func user(_ text: String) -> ChatMessage { .init(role: .user, text: text) }
    public static func assistant(_ text: String) -> ChatMessage { .init(role: .assistant, text: text) }
}

/// Fast / Balanced / Precise: each provider preset maps it to a model and a reasoning effort.
public enum ResponseSpeed: String, Sendable, Codable, CaseIterable {
    case fast, balanced, precise
}

/// Personality presets (settings › Personality).
public enum TonePreset: String, Sendable, Codable, CaseIterable {
    case enthusiastic, calm, professional, funny, teasing

    /// Style instruction injected in the system prompt.
    public var instruction: String {
        switch self {
        case .enthusiastic:
            "Be warm, upbeat and enthusiastic. Show genuine curiosity and encourage the user."
        case .calm:
            "Be calm, gentle and reassuring. Keep a soft, steady pace and avoid exclamation marks."
        case .professional:
            "Be clear, precise and efficient. Get to the point and structure the answer like a brief summary."
        case .funny:
            "Be playful and funny. Add a light joke or an otter pun when it fits, without hurting accuracy."
        case .teasing:
            "Be cheeky and teasing in a friendly way, like a mischievous friend. Never mean, always helpful."
        }
    }
}
