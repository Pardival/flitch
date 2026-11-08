/// One Server-Sent Event.
public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
}

/// Incremental SSE parser: feed lines, get events when a blank line ends one.
///
/// `URLSession.AsyncBytes.lines` drops empty lines, so a new `event:` or `data:` line also closes
/// the pending event (the providers we talk to send one `data:` line per event).
public struct SSEParser: Sendable {
    private var event: String?
    private var data: [String] = []

    public init() {}

    public mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive
        let (field, value) = Self.split(line)
        var pending: SSEEvent?
        if (field == "event" || field == "data"), !data.isEmpty { pending = dispatch() }
        switch field {
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return pending
    }

    /// Flushes a last event if the stream ended without a blank line.
    public mutating func finish() -> SSEEvent? { dispatch() }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            event = nil
            data = []
        }
        guard !data.isEmpty else { return nil }
        return SSEEvent(event: event, data: data.joined(separator: "\n"))
    }

    private static func split(_ line: String) -> (String, String) {
        guard let i = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: i)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<i]), String(value))
    }
}

extension AsyncThrowingStream where Element == String {
    /// Turns streamed lines into SSE events.
    func sseEvents() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await line in self {
                        if let e = parser.feed(line) { continuation.yield(e) }
                    }
                    if let e = parser.finish() { continuation.yield(e) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
