@preconcurrency import AVFoundation
import FlitchCore
import FlitchVoice
import Foundation

/// Optional cloud speech-to-text (OpenAI or Mistral), for people who find on-device accuracy too low.
///
/// The audio stays in memory while you talk, then is sent once, as a WAV file, when you release the key.
/// Nothing is written to disk. There are no live partial results: the bubble shows "…" while you talk.
public struct CloudSpeechRecognizer: SpeechRecognizing {
    public enum Service: String, Sendable, CaseIterable {
        case openAI, mistral

        public var displayName: String {
            switch self {
            case .openAI: "OpenAI"
            case .mistral: "Mistral"
            }
        }

        public var defaultBaseURL: URL {
            switch self {
            case .openAI: URL(string: "https://api.openai.com/v1")!
            case .mistral: URL(string: "https://api.mistral.ai/v1")!
            }
        }

        public var model: String {
            switch self {
            case .openAI: "gpt-4o-mini-transcribe"
            case .mistral: "voxtral-mini-latest"
            }
        }
    }

    /// 16 kHz mono is what both services expect; it also keeps uploads small (~32 KB per second).
    public static let sampleRate: Double = 16_000

    let service: Service
    let apiKey: String
    let baseURL: URL
    let http: HTTPTransport

    public init(service: Service, apiKey: String, baseURL: URL? = nil, http: HTTPTransport = .makeDefault()) {
        self.service = service
        self.apiKey = apiKey
        self.baseURL = baseURL ?? service.defaultBaseURL
        self.http = http
    }

    public func startSession(language: AppLanguage) async throws -> any RecognitionSession {
        try await AudioCapture.ensurePermission()
        let session = CloudRecognitionSession(recognizer: self, language: language)
        try session.start()
        return session
    }

    /// Sends the recorded samples and returns the transcript.
    public func transcribe(samples: [Float], language: AppLanguage) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let wav = WAVEncoder.encode(samples, sampleRate: Self.sampleRate)
        var form = MultipartForm()
        form.add(name: "model", value: service.model)
        form.add(name: "language", value: language.rawValue)
        form.add(name: "response_format", value: "json")
        form.add(name: "file", filename: "speech.wav", contentType: "audio/wav", data: wav)

        var req = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = form.finished()
        req.timeoutInterval = 30
        let data = try await send(req, http: http, provider: service.displayName, secret: apiKey)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class CloudRecognitionSession: RecognitionSession, @unchecked Sendable {
    let partialResults: AsyncStream<String>
    var levels: AsyncStream<Float> { capture.levels }

    private let recognizer: CloudSpeechRecognizer
    private let language: AppLanguage
    private let capture = AudioCapture()
    private let partials: AsyncStream<String>.Continuation
    private var collectTask: Task<[Float], Never>?

    init(recognizer: CloudSpeechRecognizer, language: AppLanguage) {
        self.recognizer = recognizer
        self.language = language
        (partialResults, partials) = AsyncStream.makeStream()
    }

    func start() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: CloudSpeechRecognizer.sampleRate, channels: 1,
            interleaved: false)
        try capture.start(format: format)
        let buffers = capture.buffers
        collectTask = Task {
            var samples: [Float] = []
            for await buffer in buffers {
                guard let data = buffer.floatChannelData?[0] else { continue }
                samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
            }
            return samples
        }
    }

    func finish() async throws -> String {
        capture.stop()
        partials.finish()
        let samples = await collectTask?.value ?? []
        return try await recognizer.transcribe(samples: samples, language: language)
    }

    func cancel() async {
        capture.stop()
        partials.finish()
        collectTask?.cancel()
    }
}

/// 16-bit PCM WAV in memory.
public enum WAVEncoder {
    public static func encode(_ samples: [Float], sampleRate: Double) -> Data {
        let rate = UInt32(sampleRate)
        let dataSize = UInt32(samples.count * 2)
        var d = Data(capacity: 44 + Int(dataSize))
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8))
        u32(36 + dataSize)
        d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16)
        u16(1)  // PCM
        u16(1)  // mono
        u32(rate)
        u32(rate * 2)  // byte rate
        u16(2)  // block align
        u16(16)  // bits per sample
        d.append(contentsOf: Array("data".utf8))
        u32(dataSize)
        for s in samples {
            let v = Int16(max(-1, min(1, s)) * Float(Int16.max))
            u16(UInt16(bitPattern: v))
        }
        return d
    }
}

/// `multipart/form-data` body.
struct MultipartForm {
    let boundary = "flitch-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(name: String, value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func add(name: String, filename: String, contentType: String, data: Data) {
        body.append(
            Data(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n"
                    .utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    /// Call once, after the last field.
    func finished() -> Data { body + Data("--\(boundary)--\r\n".utf8) }
}
