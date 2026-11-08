import FlitchCore
import Foundation
import Security

/// A secret Flitch uses to reach a provider. Its description never shows the secret.
public enum Credential: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case apiKey(String)
    case oauth(OAuthToken)

    public var description: String {
        switch self {
        case .apiKey: "Credential.apiKey(<redacted>)"
        case .oauth(let t): "Credential.oauth(<redacted>, scopes: \(t.scopes))"
        }
    }

    public var debugDescription: String { description }

    /// The value to send to the provider.
    public var secret: String {
        switch self {
        case .apiKey(let k): k
        case .oauth(let t): t.accessToken
        }
    }

    /// Every secret string in it, for `Redactor`.
    public var allSecrets: [String] {
        switch self {
        case .apiKey(let k): [k]
        case .oauth(let t): [t.accessToken, t.refreshToken].compactMap { $0 }
        }
    }
}

/// Access token, refresh token, expiry and scopes are always stored together.
public struct OAuthToken: Codable, Sendable, Equatable, CustomStringConvertible {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scopes: [String]
    /// OAuth client the token was issued to (needed to refresh it).
    public var clientID: String?
    /// Account e-mail, for display only.
    public var accountName: String?

    public init(
        accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil, scopes: [String] = [],
        clientID: String? = nil, accountName: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.clientID = clientID
        self.accountName = accountName
    }

    public var description: String { "OAuthToken(<redacted>, scopes: \(scopes))" }

    /// Refresh a minute early to avoid racing the expiry.
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Where credentials are persisted. The app uses `KeychainStorage`; tests use `InMemoryStorage`.
public protocol SecureStorage: Sendable {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, _ data: Data) throws
    func delete(_ key: String) throws
}

/// Generic-password items in the login Keychain, service `app.flitch.<provider>`, only for this device.
public struct KeychainStorage: SecureStorage {
    public let servicePrefix: String

    public init(servicePrefix: String = "app.flitch") { self.servicePrefix = servicePrefix }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(servicePrefix).\(key)",
            kSecAttrAccount as String: "credential",
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    public func read(_ key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return out as? Data
    }

    public func write(_ key: String, _ data: Data) throws {
        let q = query(key)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecAttrLabel as String] = "Flitch (\(key))"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Sendable, Equatable {
    public var status: OSStatus
}

public final class InMemoryStorage: SecureStorage, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func read(_ key: String) throws -> Data? { lock.withLock { items[key] } }
    public func write(_ key: String, _ data: Data) throws { lock.withLock { items[key] = data } }
    public func delete(_ key: String) throws { lock.withLock { _ = items.removeValue(forKey: key) } }
}

/// The only way Flitch reads or writes secrets.
public actor CredentialStore {
    public typealias Refresher = @Sendable (OAuthToken) async throws -> OAuthToken

    private let storage: any SecureStorage
    private var refreshing: [String: Task<Credential, Error>] = [:]

    public init(storage: any SecureStorage = KeychainStorage()) { self.storage = storage }

    public func credential(for provider: String) throws -> Credential? {
        guard let data = try storage.read(provider) else { return nil }
        return try JSONDecoder().decode(Credential.self, from: data)
    }

    public func save(_ credential: Credential, for provider: String) throws {
        try storage.write(provider, JSONEncoder().encode(credential))
    }

    public func remove(_ provider: String) throws { try storage.delete(provider) }

    /// A credential ready to use: OAuth tokens close to expiry are refreshed first.
    /// Concurrent callers share a single refresh per provider (refresh tokens rotate).
    public func validCredential(for provider: String, refresh: @escaping Refresher) async throws -> Credential? {
        if let inFlight = refreshing[provider] { return try await inFlight.value }
        guard let current = try credential(for: provider) else { return nil }
        guard case .oauth(let token) = current, token.isExpired() else { return current }
        let task = Task<Credential, Error> {
            let fresh = Credential.oauth(try await refresh(token))
            try self.save(fresh, for: provider)
            return fresh
        }
        refreshing[provider] = task
        defer { refreshing[provider] = nil }
        return try await task.value
    }
}
