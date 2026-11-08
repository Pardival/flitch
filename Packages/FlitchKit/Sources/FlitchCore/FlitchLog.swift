import Foundation
import os

/// Logging with secrets kept out: only FlitchError messages (already scrubbed) are logged publicly.
/// Read with `log stream --predicate 'subsystem == "app.flitch"'`.
public enum FlitchLog {
    static let logger = Logger(subsystem: "app.flitch", category: "flitch")

    public static func error(_ error: FlitchError) {
        logger.error("\(String(describing: error), privacy: .public)")
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
