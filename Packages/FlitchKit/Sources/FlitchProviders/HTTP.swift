import FlitchCore
import Foundation

/// A non-2xx answer from a provider. Its message is scrubbed of the credential before being shown.
public struct ProviderHTTPError: Error, Sendable, Equatable {
    public var status: Int
    public var message: String
}

/// Thin wrapper over URLSession so tests can inject a `URLProtocol` stub.
public struct HTTPTransport: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    /// Default session for providers: generous timeout for slow reasoning models.
    public static func makeDefault() -> HTTPTransport {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 120
        c.httpCookieStorage = nil
        c.urlCache = nil
        return HTTPTransport(session: URLSession(configuration: c))
    }

    public func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Self.check(response, body: data)
        return data
    }

    /// Lines of a streaming (SSE) response. Throws `ProviderHTTPError` on a non-2xx status.
    public func lines(_ request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await b in bytes {
                body.append(b)
                if body.count > 64_000 { break }
            }
            try Self.check(response, body: body)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        throw ProviderHTTPError(status: http.statusCode, message: errorMessage(from: body))
    }

    /// `{"error":{"message":…}}` (OpenAI, OpenRouter, Anthropic), `{"error":"…"}` (Ollama), or raw text.
    static func errorMessage(from body: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let e = json["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = json["error"] as? String { return m }
            if let m = json["message"] as? String { return m }
        }
        return String(decoding: body.prefix(300), as: UTF8.self)
    }
}

extension FlitchError {
    /// Maps provider failures to messages Flitch can say.
    public static func fromProvider(_ error: any Error, provider: String, secrets: [String] = []) -> any Error {
        guard let http = error as? ProviderHTTPError else { return error }
        switch http.status {
        case 401, 403: return FlitchError.invalidCredentials(provider: provider)
        case 429: return FlitchError.rateLimited(provider: provider)
        default:
            let msg = Redactor.scrub(http.message, secrets: secrets)
            return FlitchError.other("\(provider) \(http.status): \(msg.prefix(160))")
        }
    }
}

/// Removes secrets from any text that may be shown or logged.
public enum Redactor {
    public static func scrub(_ text: String, secrets: [String]) -> String {
        var out = text
        for s in secrets where s.count >= 6 {
            out = out.replacingOccurrences(of: s, with: "••••")
        }
        return out
    }
}
