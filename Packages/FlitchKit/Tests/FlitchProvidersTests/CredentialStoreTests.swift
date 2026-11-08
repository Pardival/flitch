import Foundation
import Synchronization
import Testing

@testable import FlitchProviders

struct CredentialStoreTests {
    @Test func savesReadsAndRemoves() async throws {
        let store = CredentialStore(storage: InMemoryStorage())
        #expect(try await store.credential(for: "openrouter") == nil)
        try await store.save(.apiKey("sk-or-1"), for: "openrouter")
        #expect(try await store.credential(for: "openrouter") == .apiKey("sk-or-1"))
        try await store.remove("openrouter")
        #expect(try await store.credential(for: "openrouter") == nil)
    }

    @Test func descriptionsNeverLeakSecrets() {
        let key = Credential.apiKey("sk-SECRET-123456")
        let token = Credential.oauth(
            OAuthToken(accessToken: "at-SECRET", refreshToken: "rt-SECRET", scopes: ["openid"]))
        for c in [key, token] {
            for text in ["\(c)", String(describing: c), String(reflecting: c), "\([c])"] {
                #expect(!text.contains("SECRET"), "leaked in \(text)")
            }
        }
        #expect(Redactor.scrub("error for sk-SECRET-123456", secrets: key.allSecrets) == "error for ••••")
    }

    @Test func refreshesExpiredTokenOnceForConcurrentCallers() async throws {
        let store = CredentialStore(storage: InMemoryStorage())
        let expired = OAuthToken(accessToken: "old", refreshToken: "r1", expiresAt: Date().addingTimeInterval(-10))
        try await store.save(.oauth(expired), for: "chatgpt")
        let calls = Mutex(0)
        let refresh: CredentialStore.Refresher = { old in
            calls.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
            return OAuthToken(accessToken: "new", refreshToken: "r2", expiresAt: Date().addingTimeInterval(3600))
        }
        async let a = store.validCredential(for: "chatgpt", refresh: refresh)
        async let b = store.validCredential(for: "chatgpt", refresh: refresh)
        let (ra, rb) = try await (a, b)
        #expect(ra?.secret == "new" && rb?.secret == "new")
        #expect(calls.withLock { $0 } == 1)
        // rotated refresh token stored together with the access token
        if case .oauth(let saved) = try await store.credential(for: "chatgpt") {
            #expect(saved.refreshToken == "r2")
        } else {
            Issue.record("expected an OAuth token")
        }
    }

    @Test func validTokenIsNotRefreshed() async throws {
        let store = CredentialStore(storage: InMemoryStorage())
        try await store.save(
            .oauth(OAuthToken(accessToken: "ok", expiresAt: Date().addingTimeInterval(3600))), for: "p")
        let c = try await store.validCredential(for: "p") { _ in
            Issue.record("should not refresh")
            return OAuthToken(accessToken: "x")
        }
        #expect(c?.secret == "ok")
    }

    /// Real Keychain round trip on a throwaway service name.
    @Test func keychainRoundTrip() throws {
        let storage = KeychainStorage(servicePrefix: "app.flitch.tests.\(UUID().uuidString)")
        defer { try? storage.delete("k") }
        do {
            try storage.write("k", Data("v1".utf8))
        } catch let e as KeychainError where e.status == errSecInteractionNotAllowed || e.status == errSecNotAvailable {
            return  // no unlocked login keychain (some CI runners)
        }
        try storage.write("k", Data("v2".utf8))
        #expect(try storage.read("k") == Data("v2".utf8))
        try storage.delete("k")
        #expect(try storage.read("k") == nil)
    }
}
