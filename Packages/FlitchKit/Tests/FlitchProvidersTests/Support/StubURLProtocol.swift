import FlitchCore
import Foundation
import Synchronization
import Testing

/// Serves canned responses to URLSession, keyed by host, so tests never hit the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var body: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
    }

    struct Recorded: Sendable {
        var request: URLRequest
        var body: Data?
    }

    private static let routes = Mutex<[String: @Sendable (URLRequest) -> Response]>([:])
    private static let recorded = Mutex<[String: [Recorded]]>([:])

    /// A session whose requests to `host` are answered by `handler`.
    static func session(host: String, handler: @escaping @Sendable (URLRequest) -> Response) -> URLSession {
        routes.withLock { $0[host] = handler }
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: c)
    }

    static func requests(host: String) -> [Recorded] { recorded.withLock { $0[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.recorded.withLock { $0[host, default: []].append(Recorded(request: request, body: body)) }
        guard let handler = Self.routes.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let r = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: r.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func uniqueHost() -> String { "test-\(UUID().uuidString.lowercased()).invalid" }

func collect(_ stream: AsyncThrowingStream<LLMEvent, Error>) async throws -> [LLMEvent] {
    var out: [LLMEvent] = []
    for try await e in stream { out.append(e) }
    return out
}
