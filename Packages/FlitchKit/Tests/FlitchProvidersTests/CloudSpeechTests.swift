import FlitchCore
import Foundation
import Testing

@testable import FlitchProviders

struct CloudSpeechTests {
    @Test func wavHeaderIsValid() {
        let wav = WAVEncoder.encode([0, 0.5, -0.5, 1, -1], sampleRate: 16_000)
        #expect(wav.count == 44 + 10)
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 16_000)
        let last = wav[52..<54].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        #expect(Int16(littleEndian: last) == -Int16.max)
    }

    @Test(arguments: CloudSpeechRecognizer.Service.allCases)
    func sendsMultipartAndReadsText(service: CloudSpeechRecognizer.Service) async throws {
        let host = uniqueHost()
        let http = HTTPTransport(
            session: StubURLProtocol.session(host: host) { _ in
                .init(status: 200, body: Data(#"{"text":" Bonjour Flitch "}"#.utf8))
            })
        let r = CloudSpeechRecognizer(
            service: service, apiKey: "sk-test-123", baseURL: URL(string: "https://\(host)/v1")!, http: http)
        let text = try await r.transcribe(samples: Array(repeating: 0.1, count: 1600), language: .french)
        #expect(text == "Bonjour Flitch")

        let rec = try #require(StubURLProtocol.requests(host: host).first)
        #expect(rec.request.url?.path == "/v1/audio/transcriptions")
        #expect(rec.request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123")
        #expect(rec.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
        let body = String(decoding: rec.body ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"model\"\r\n\r\n\(service.model)\r\n"))
        #expect(body.contains("name=\"language\"\r\n\r\nfr\r\n"))
        #expect(body.contains("filename=\"speech.wav\""))
        #expect(body.hasSuffix("--\r\n"))
    }

    @Test func emptyRecordingSendsNothing() async throws {
        let host = uniqueHost()
        let http = HTTPTransport(session: StubURLProtocol.session(host: host) { _ in .init(status: 500, body: Data()) })
        let r = CloudSpeechRecognizer(
            service: .openAI, apiKey: "k", baseURL: URL(string: "https://\(host)/v1")!, http: http)
        #expect(try await r.transcribe(samples: [], language: .english) == "")
        #expect(StubURLProtocol.requests(host: host).isEmpty)
    }

    @Test func invalidKey() async {
        let host = uniqueHost()
        let http = HTTPTransport(
            session: StubURLProtocol.session(host: host) { _ in .init(status: 401, body: Data(#"{"error":"bad"}"#.utf8))
            })
        let r = CloudSpeechRecognizer(
            service: .mistral, apiKey: "bad-key-1", baseURL: URL(string: "https://\(host)/v1")!, http: http)
        await #expect(throws: FlitchError.invalidCredentials(provider: "Mistral")) {
            _ = try await r.transcribe(samples: [0.2], language: .english)
        }
    }
}
