import FlitchCore
import FlitchProviders
import FlitchVoice
import Foundation
import Observation

/// "Test" buttons: plays a sample sentence with an engine before it is activated.
/// Cloud samples are kept in memory so trying a voice twice costs nothing.
@MainActor
@Observable
final class VoicePreview {
    var playing: FlitchSettings.VoiceEngine?
    private(set) var keys: Set<String> = []
    @ObservationIgnored private var cache: [String: AudioClip] = [:]
    @ObservationIgnored private weak var app: AppController?
    @ObservationIgnored private let player = EngineAudioPlayer()

    init(app: AppController) {
        self.app = app
        Task { await reloadKeys() }
    }

    func hasKey(_ engine: FlitchSettings.VoiceEngine) -> Bool {
        guard let id = engine.credentialID else { return true }
        return keys.contains(id)
    }

    func reloadKeys() async {
        guard let app else { return }
        var found: Set<String> = []
        for engine in FlitchSettings.VoiceEngine.allCases {
            if let id = engine.credentialID, (try? await app.credentials.credential(for: id)) != nil {
                found.insert(id)
            }
        }
        keys = found
    }

    /// Saves a voice provider key; returns an error message or nil.
    func saveKey(_ key: String, for engine: FlitchSettings.VoiceEngine) async -> String? {
        guard let app, let id = engine.credentialID else { return nil }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await app.credentials.save(.apiKey(key), for: id)
            await reloadKeys()
            return nil
        } catch {
            return FlitchError(error)?.userMessage
        }
    }

    func play(_ engine: FlitchSettings.VoiceEngine) {
        guard let app else { return }
        player.stop()
        playing = engine
        let language = app.settings.language
        let voiceID = app.settings.voiceID(for: engine) ?? ""
        let key = "\(engine.rawValue)|\(voiceID)|\(language.rawValue)|\(app.settings.voiceSpeed)"
        let text = VoiceCatalog.sample(language)
        Task {
            defer { if playing == engine { playing = nil } }
            do {
                let clip: AudioClip
                if let cached = cache[key] {
                    clip = cached
                } else {
                    let synth = await VoiceFactory.make(
                        engine: engine, settings: app.settings, character: app.character, credentials: app.credentials)
                    clip = try await synth.synthesize(text, language: language)
                    if engine.needsKey { cache[key] = clip }
                }
                try await player.play(clip, onLevel: { _ in })
            } catch {
                if let e = FlitchError(error) { app.model.apply(.error(e)) }
            }
        }
    }
}
