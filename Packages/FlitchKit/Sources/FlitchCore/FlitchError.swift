import Foundation

/// Errors Flitch explains to the user, in character.
public enum FlitchError: Error, Sendable, Hashable {
    case noProvider
    case invalidCredentials(provider: String)
    case offline
    case rateLimited(provider: String)
    case microphoneDenied
    case nothingHeard
    case other(String)

    /// Friendly, localized message for the bubble.
    public var userMessage: String {
        switch self {
        case .noProvider: L10n.string("error.noProvider")
        case .invalidCredentials(let p): String(format: L10n.string("error.invalidKey"), p)
        case .offline: L10n.string("error.offline")
        case .rateLimited(let p): String(format: L10n.string("error.rateLimited"), p)
        case .microphoneDenied: L10n.string("error.micDenied")
        case .nothingHeard: L10n.string("error.nothingHeard")
        case .other(let detail): String(format: L10n.string("error.generic"), detail)
        }
    }

    /// Maps any error to a FlitchError. Returns nil for cancellation (not an error for the user).
    public init?(_ error: any Error) {
        if let e = error as? FlitchError {
            self = e
            return
        }
        if error is CancellationError { return nil }
        if let u = error as? URLError {
            switch u.code {
            case .cancelled: return nil
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                .timedOut, .dnsLookupFailed:
                self = .offline
            default: self = .other(u.localizedDescription)
            }
            return
        }
        self = .other(error.localizedDescription)
    }
}

extension FlitchError: LocalizedError {
    public var errorDescription: String? { userMessage }
}
