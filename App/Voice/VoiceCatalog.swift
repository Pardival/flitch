import FlitchCore
import Foundation
import SwiftUI

/// What the Voice settings show for each engine.
@MainActor
enum VoiceCatalog {
    struct EngineInfo {
        let engine: FlitchSettings.VoiceEngine
        let name: String
        let detail: LocalizedStringKey
        let keyURL: URL?
    }

    struct Voice: Hashable {
        let id: String
        let name: String
    }

    static let engines: [EngineInfo] = [
        .init(
            engine: .animal, name: String(localized: "Animal language"), detail: "Little otter chirps · free, offline",
            keyURL: nil),
        .init(
            engine: .apple, name: String(localized: "Apple voice"), detail: "The Mac's voices · free, offline",
            keyURL: nil),
        .init(
            engine: .elevenLabs, name: "ElevenLabs", detail: "The most expressive · Flitch's signature voice",
            keyURL: URL(string: "https://elevenlabs.io/app/settings/api-keys")),
        .init(
            engine: .openAI, name: "OpenAI", detail: "Voice styled by a description",
            keyURL: URL(string: "https://platform.openai.com/api-keys")),
        .init(
            engine: .cartesia, name: "Cartesia", detail: "The fastest",
            keyURL: URL(string: "https://play.cartesia.ai/keys")),
        .init(
            engine: .mistral, name: "Mistral Voxtral", detail: "Natural voices, made in France",
            keyURL: URL(string: "https://console.mistral.ai/api-keys")),
        .init(
            engine: .gemini, name: "Gemini", detail: "Expressive voices from Google",
            keyURL: URL(string: "https://aistudio.google.com/apikey")),
    ]

    static func info(_ engine: FlitchSettings.VoiceEngine) -> EngineInfo {
        engines.first { $0.engine == engine }!
    }

    /// Built-in voice lists (others are fetched from the provider).
    static let voices: [FlitchSettings.VoiceEngine: [Voice]] = [
        .openAI: [
            "coral", "nova", "shimmer", "sage", "ballad", "verse", "alloy", "ash", "echo", "fable", "onyx", "marin",
            "cedar",
        ]
        .map { Voice(id: $0, name: $0.capitalized) },
        .gemini: ["Kore", "Puck", "Zephyr", "Leda", "Aoede", "Callirrhoe", "Charon", "Fenrir", "Orus"]
            .map { Voice(id: $0, name: $0) },
    ]

    static func sample(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Hi! I'm Flitch, your little otter. Ask me anything!"
        case .french: "Salut ! Moi c'est Flitch, ta petite loutre. Pose-moi une question !"
        case .spanish: "¡Hola! Soy Flitch, tu pequeña nutria. ¡Pregúntame lo que quieras!"
        }
    }
}
