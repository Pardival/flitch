import FlitchCore
import FlitchVoice
import Foundation

/// A voice offered by a cloud provider.
public struct CloudVoice: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var language: String?
    public init(id: String, name: String, language: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
    }
}

/// How Flitch's voice should sound when a provider accepts a style description.
public enum FlitchVoiceStyle {
    public static let instructions = """
        Voice of Flitch, a cheerful little river otter: warm, bright, playful and expressive, smiling while \
        talking, slightly high-pitched, clear diction. Speak in the language of the text with a natural native accent.
        """
    public static let designDescription = """
        A cheerful, warm and playful young voice for a friendly river otter mascot. Bright, slightly high-pitched, \
        expressive and smiling, with clear diction and a gentle, curious energy.
        """
}

// MARK: - ElevenLabs

public struct ElevenLabsVoice: SentenceSynthesizer {
    public static let baseURL = URL(string: "https://api.elevenlabs.io/v1")!
    public enum Model: String, Sendable { case flash = "eleven_flash_v2_5", expressive = "eleven_v3" }

    let apiKey: String
    let voiceID: String
    let model: Model
    let speed: Double
    let baseURL: URL
    let http: HTTPTransport

    public init(
        apiKey: String, voiceID: String, model: Model = .flash, speed: Double = 1,
        baseURL: URL = ElevenLabsVoice.baseURL,
        http: HTTPTransport = .makeDefault()
    ) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.model = model
        self.speed = speed
        self.baseURL = baseURL
        self.http = http
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        var c = URLComponents(
            url: baseURL.appendingPathComponent("text-to-speech/\(voiceID)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "text": sentence, "model_id": model.rawValue,
            "voice_settings": ["speed": min(1.2, max(0.7, speed))],
        ]
        if model == .flash { body["language_code"] = language.rawValue }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req, http: http, provider: "ElevenLabs", secret: apiKey)
        return try AudioDecoding.pcm16(data, sampleRate: 24_000)
    }

    public static func voices(apiKey: String, http: HTTPTransport = .makeDefault()) async throws -> [CloudVoice] {
        var req = URLRequest(url: baseURL.appendingPathComponent("voices"))
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "ElevenLabs", secret: apiKey))
        return ((json as? [String: Any])?["voices"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["voice_id"] as? String else { return nil }
            return CloudVoice(id: id, name: $0["name"] as? String ?? id)
        }
    }
}

/// Creates Flitch's signature voice in the user's ElevenLabs account with Voice Design.
public struct ElevenLabsVoiceDesigner: Sendable {
    public struct Preview: Sendable { public var generatedVoiceID: String; public var audio: Data }

    let apiKey: String
    let baseURL: URL
    let http: HTTPTransport

    public init(apiKey: String, baseURL: URL = ElevenLabsVoice.baseURL, http: HTTPTransport = .makeDefault()) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.http = http
    }

    public func design(description: String = FlitchVoiceStyle.designDescription, sampleText: String) async throws
        -> [Preview]
    {
        var req = URLRequest(url: baseURL.appendingPathComponent("text-to-voice/design"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "voice_description": description, "text": sampleText, "model_id": "eleven_multilingual_ttv_v2",
        ])
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "ElevenLabs", secret: apiKey))
        return ((json as? [String: Any])?["previews"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["generated_voice_id"] as? String else { return nil }
            return Preview(
                generatedVoiceID: id, audio: Data(base64Encoded: $0["audio_base_64"] as? String ?? "") ?? Data())
        }
    }

    /// Saves a preview as a voice; returns its voice id.
    public func create(
        _ preview: Preview, name: String = "Flitch", description: String = FlitchVoiceStyle.designDescription
    )
        async throws -> String
    {
        var req = URLRequest(url: baseURL.appendingPathComponent("text-to-voice"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "voice_name": name, "voice_description": description, "generated_voice_id": preview.generatedVoiceID,
        ])
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "ElevenLabs", secret: apiKey))
        guard let id = (json as? [String: Any])?["voice_id"] as? String else {
            throw FlitchError.other("ElevenLabs didn't create the voice")
        }
        return id
    }
}

// MARK: - Cartesia

public struct CartesiaVoice: SentenceSynthesizer {
    public static let baseURL = URL(string: "https://api.cartesia.ai")!
    public static let apiVersion = "2026-08-14"

    let apiKey: String
    let voiceID: String
    let baseURL: URL
    let http: HTTPTransport

    public init(
        apiKey: String, voiceID: String, baseURL: URL = CartesiaVoice.baseURL, http: HTTPTransport = .makeDefault()
    ) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.baseURL = baseURL
        self.http = http
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        var req = URLRequest(url: baseURL.appendingPathComponent("tts/bytes"))
        req.httpMethod = "POST"
        Self.headers(&req, apiKey)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model_id": "sonic-3.6", "transcript": sentence, "voice": ["id": voiceID], "language": language.rawValue,
            "output_format": ["container": "raw", "encoding": "pcm_f32le", "sample_rate": 24_000],
        ])
        let data = try await send(req, http: http, provider: "Cartesia", secret: apiKey)
        return try AudioDecoding.pcmFloat32(data, sampleRate: 24_000)
    }

    public static func voices(apiKey: String, http: HTTPTransport = .makeDefault()) async throws -> [CloudVoice] {
        var req = URLRequest(url: baseURL.appendingPathComponent("voices"))
        headers(&req, apiKey)
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "Cartesia", secret: apiKey))
        let items = (json as? [String: Any])?["data"] as? [[String: Any]] ?? (json as? [[String: Any]]) ?? []
        return items.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return CloudVoice(id: id, name: $0["name"] as? String ?? id, language: $0["language"] as? String)
        }
    }

    static func headers(_ req: inout URLRequest, _ key: String) {
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Cartesia-Version")
    }
}

// MARK: - OpenAI

public struct OpenAIVoice: SentenceSynthesizer {
    let apiKey: String
    let voice: String
    let instructions: String
    let speed: Double
    let baseURL: URL
    let http: HTTPTransport

    public init(
        apiKey: String, voice: String = "coral", instructions: String = FlitchVoiceStyle.instructions,
        speed: Double = 1,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!, http: HTTPTransport = .makeDefault()
    ) {
        self.apiKey = apiKey
        self.voice = voice
        self.instructions = instructions
        self.speed = speed
        self.baseURL = baseURL
        self.http = http
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        var req = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts", "voice": voice, "input": sentence, "instructions": instructions,
            "response_format": "pcm", "speed": min(1.5, max(0.6, speed)),
        ])
        let data = try await send(req, http: http, provider: "OpenAI", secret: apiKey)
        return try AudioDecoding.pcm16(data, sampleRate: 24_000)
    }
}

// MARK: - Mistral Voxtral

public struct MistralVoice: SentenceSynthesizer {
    public static let model = "voxtral-mini-tts-3-0"
    let apiKey: String
    let voiceID: String
    let baseURL: URL
    let http: HTTPTransport

    public init(
        apiKey: String, voiceID: String = "gb_jane_neutral", baseURL: URL = URL(string: "https://api.mistral.ai/v1")!,
        http: HTTPTransport = .makeDefault()
    ) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.baseURL = baseURL
        self.http = http
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        var req = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model, "input": sentence, "voice_id": voiceID, "response_format": "wav",
        ])
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "Mistral", secret: apiKey))
        guard let b64 = (json as? [String: Any])?["audio_data"] as? String, let audio = Data(base64Encoded: b64) else {
            throw FlitchError.other("Mistral returned no audio")
        }
        return try AudioDecoding.container(audio, fileExtension: "wav")
    }
}

// MARK: - Gemini

public struct GeminiVoice: SentenceSynthesizer {
    public static let model = "gemini-3.8-flash-tts"
    let apiKey: String
    let voice: String
    let baseURL: URL
    let http: HTTPTransport

    public init(
        apiKey: String, voice: String = "Kore",
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        http: HTTPTransport = .makeDefault()
    ) {
        self.apiKey = apiKey
        self.voice = voice
        self.baseURL = baseURL
        self.http = http
    }

    public func synthesize(_ sentence: String, language: AppLanguage) async throws -> AudioClip {
        var req = URLRequest(url: baseURL.appendingPathComponent("interactions"))
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": Self.model,
            "input": [["type": "user_input", "content": [["type": "text", "text": sentence]]]],
            "response_format": ["type": "audio"],
            "generation_config": ["speech_config": [["voice": voice]]],
        ])
        let json = try JSONSerialization.jsonObject(
            with: try await send(req, http: http, provider: "Gemini", secret: apiKey))
        let steps = (json as? [String: Any])?["steps"] as? [[String: Any]] ?? []
        let audio =
            steps.filter { $0["type"] as? String == "model_output" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .last { $0["type"] as? String == "audio" }?["data"] as? String
        guard let audio, let data = Data(base64Encoded: audio) else {
            throw FlitchError.other("Gemini returned no audio")
        }
        return try AudioDecoding.container(data, fileExtension: "wav")
    }
}

func send(_ req: URLRequest, http: HTTPTransport, provider: String, secret: String) async throws -> Data {
    do {
        return try await http.data(req)
    } catch {
        throw FlitchError.fromProvider(error, provider: provider, secrets: [secret])
    }
}
