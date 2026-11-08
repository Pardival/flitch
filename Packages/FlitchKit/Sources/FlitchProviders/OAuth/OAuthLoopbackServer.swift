import FlitchCore
import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that receives the OAuth redirect.
///
/// It binds to the loopback interface only, on a random free port (or a fixed one), answers the
/// first request to `path` with a small "you can go back to Flitch" page, then stops.
public final class OAuthLoopbackServer: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public var queryItems: [String: String]
        public subscript(_ name: String) -> String? { queryItems[name] }
    }

    public let path: String
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "app.flitch.oauth-loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private var pending: Result<Callback, Error>?
    private let lock = NSLock()

    public init(path: String = "/callback", port: UInt16 = 0) {
        self.path = path
        self.requestedPort = port
    }

    /// Starts listening and returns the redirect URL to give to the provider.
    public func start() async throws -> URL {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() { cont.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.fire() { cont.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    /// Waits for the redirect. Throws on timeout (default 10 minutes, the code lifetime).
    public func waitForCallback(timeout: Duration = .seconds(600)) async throws -> Callback {
        defer { stop() }
        return try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { cont in
                        self.lock.withLock {
                            if let pending = self.pending {
                                cont.resume(with: pending)
                            } else {
                                self.continuation = cont
                            }
                        }
                    }
                } onCancel: {
                    self.lock.withLock {
                        self.continuation?.resume(throwing: CancellationError())
                        self.continuation = nil
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw FlitchError.other("sign-in timed out")
            }
            defer { group.cancelAll() }
            let result = try await group.next()!
            return result
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.withLock {
            continuation?.resume(throwing: CancellationError())
            continuation = nil
        }
    }

    // MARK: - HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://127.0.0.1\(target)")
            guard components?.path == self.path else {
                self.respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            var items: [String: String] = [:]
            for item in components?.queryItems ?? [] { items[item.name] = item.value ?? "" }
            let failed = items["error"] != nil || items["code"] == nil
            self.respond(connection, status: "200 OK", body: Self.page(success: !failed))
            self.deliver(.success(Callback(queryItems: items)))
        }
    }

    private func deliver(_ result: Result<Callback, Error>) {
        lock.withLock {
            if let continuation {
                continuation.resume(with: result)
                self.continuation = nil
            } else if pending == nil {
                pending = result
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let head =
            "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\n"
            + "Connection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func page(success: Bool) -> String {
        let title = success ? "You're connected!" : "Sign-in didn't work"
        let text =
            success
            ? "You can close this tab and go back to Flitch."
            : "Go back to Flitch and try again."
        return """
            <!doctype html><html><head><meta charset="utf-8"><title>Flitch</title>
            <style>body{font:16px -apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f}
            main{text-align:center}h1{font-size:28px;margin:0 0 8px}p{color:#6e6e73}</style></head>
            <body><main><h1>\(title)</h1><p>\(text)</p></main></body></html>
            """
    }
}

/// Fires once (thread-safe).
final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    func fire() -> Bool {
        lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
    }
}
