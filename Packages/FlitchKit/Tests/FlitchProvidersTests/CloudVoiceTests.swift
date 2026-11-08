import AVFoundation
import FlitchCore
import FlitchVoice
import Foundation
import Testing

@testable import FlitchProviders

struct CloudVoiceTests {
    static func pcm16(seconds: Double, rate: Double = 24_000) -> Data {
        var d = Data()
        for i in 0..<Int(seconds * rate) {
            var v = Int16(sin(Double(i) / 10) * 8000).littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        return d
    }

    static func pcmF32(seconds: Double, rate: Double = 24_000) -> Data {
        var d = Data()
        for i in 0..<Int(seconds * rate) {
            var v = Float(sin(Double(i) / 10) * 0.3).bitPattern.littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        return d
    }

    static func wav(seconds: Double) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).wav")
        let buffer = AVAudioPCMBuffer.mono(
            (0..<Int(seconds * 24_000)).map { Float(sin(Double($0) / 9)) * 0.2 }, sampleRate: 24_000)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }

    static func session(_ host: String, status: Int = 200, body: Data) -> HTTPTransport {
        HTTPTransport(session: StubURLProtocol.session(host: host) { _ in .init(status: status, body: body) })
    }

    static func json(_ r: StubURLProtocol.Recorded) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: r.body ?? Data()) as? [String: Any])
    }

    @Test func elevenLabs() async throws {
        let host = uniqueHost()
        let v = ElevenLabsVoice(
            apiKey: "xi-key-123", voiceID: "VOICE", baseURL: URL(string: "https://\(host)/v1")!,
            http: Self.session(host, body: Self.pcm16(seconds: 0.5)))
        let clip = try await v.synthesize("Salut !", language: .french)
        #expect(abs(clip.duration - 0.5) < 0.01)
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.url?.path == "/v1/text-to-speech/VOICE")
        #expect(r.request.url?.query == "output_format=pcm_24000")
        #expect(r.request.value(forHTTPHeaderField: "xi-api-key") == "xi-key-123")
        let body = try Self.json(r)
        #expect(body["model_id"] as? String == "eleven_flash_v2_5" && body["language_code"] as? String == "fr")
    }

    @Test func elevenLabsInvalidKey() async {
        let host = uniqueHost()
        let v = ElevenLabsVoice(
            apiKey: "bad-key-123", voiceID: "V", baseURL: URL(string: "https://\(host)/v1")!,
            http: Self.session(host, status: 401, body: Data(#"{"detail":{"message":"invalid"}}"#.utf8)))
        await #expect(throws: FlitchError.invalidCredentials(provider: "ElevenLabs")) {
            _ = try await v.synthesize("x", language: .english)
        }
    }

    @Test func signatureVoiceDesign() async throws {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { req in
            req.url!.path.hasSuffix("/design")
                ? .init(
                    body: Data(#"{"previews":[{"generated_voice_id":"gen1","audio_base_64":"AAAA"}],"text":"t"}"#.utf8))
                : .init(body: Data(#"{"voice_id":"flitch-voice"}"#.utf8))
        }
        let d = ElevenLabsVoiceDesigner(
            apiKey: "k-123456", baseURL: URL(string: "https://\(host)/v1")!, http: HTTPTransport(session: session))
        let previews = try await d.design(sampleText: String(repeating: "Salut, je suis Flitch. ", count: 6))
        #expect(previews.first?.generatedVoiceID == "gen1")
        #expect(try await d.create(previews[0]) == "flitch-voice")
        let create = try Self.json(try #require(StubURLProtocol.requests(host: host).last))
        #expect(create["voice_name"] as? String == "Flitch" && create["generated_voice_id"] as? String == "gen1")
    }

    @Test func cartesia() async throws {
        let host = uniqueHost()
        let v = CartesiaVoice(
            apiKey: "sk_car_1", voiceID: "v1", baseURL: URL(string: "https://\(host)")!,
            http: Self.session(host, body: Self.pcmF32(seconds: 0.25)))
        let clip = try await v.synthesize("Hola", language: .spanish)
        #expect(abs(clip.duration - 0.25) < 0.01)
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.url?.path == "/tts/bytes")
        #expect(r.request.value(forHTTPHeaderField: "Cartesia-Version") == CartesiaVoice.apiVersion)
        #expect(r.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk_car_1")
        let body = try Self.json(r)
        #expect((body["output_format"] as? [String: Any])?["encoding"] as? String == "pcm_f32le")
        #expect((body["voice"] as? [String: Any])?["id"] as? String == "v1" && body["language"] as? String == "es")
    }

    @Test func openAI() async throws {
        let host = uniqueHost()
        let v = OpenAIVoice(
            apiKey: "sk-1", voice: "coral", baseURL: URL(string: "https://\(host)/v1")!,
            http: Self.session(host, body: Self.pcm16(seconds: 0.3)))
        _ = try await v.synthesize("Hi", language: .english)
        let body = try Self.json(try #require(StubURLProtocol.requests(host: host).first))
        #expect(body["model"] as? String == "gpt-4o-mini-tts" && body["response_format"] as? String == "pcm")
        #expect((body["instructions"] as? String)?.contains("otter") == true)
    }

    @Test func mistral() async throws {
        let host = uniqueHost()
        let payload = try JSONSerialization.data(withJSONObject: [
            "audio_data": try Self.wav(seconds: 0.4).base64EncodedString()
        ])
        let v = MistralVoice(
            apiKey: "m-1", baseURL: URL(string: "https://\(host)/v1")!, http: Self.session(host, body: payload))
        let clip = try await v.synthesize("Bonjour", language: .french)
        #expect(abs(clip.duration - 0.4) < 0.02)
        let body = try Self.json(try #require(StubURLProtocol.requests(host: host).first))
        #expect(body["model"] as? String == MistralVoice.model && body["voice_id"] as? String == "gb_jane_neutral")
    }

    @Test func gemini() async throws {
        let host = uniqueHost()
        let wav = try Self.wav(seconds: 0.3).base64EncodedString()
        let payload = try JSONSerialization.data(withJSONObject: [
            "steps": [["type": "model_output", "content": [["type": "audio", "data": wav]]]]
        ])
        let v = GeminiVoice(
            apiKey: "g-1", baseURL: URL(string: "https://\(host)/v1beta")!, http: Self.session(host, body: payload))
        let clip = try await v.synthesize("Hi", language: .english)
        #expect(abs(clip.duration - 0.3) < 0.02)
        let r = try #require(StubURLProtocol.requests(host: host).first)
        #expect(r.request.url?.path == "/v1beta/interactions")
        #expect(r.request.value(forHTTPHeaderField: "x-goog-api-key") == "g-1")
        let body = try Self.json(r)
        #expect(body["model"] as? String == GeminiVoice.model)
    }
}
