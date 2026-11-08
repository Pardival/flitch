import FlitchCore
import Foundation
import Testing

@testable import FlitchProviders

struct PKCETests {
    @Test func rfc7636Vector() {
        let p = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(p.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreRandomAndURLSafe() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(a.verifier != b.verifier)
        #expect(a.verifier.count == 43)
        #expect(a.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}

struct OAuthLoopbackServerTests {
    @Test func receivesTheCallbackOnLoopback() async throws {
        let server = OAuthLoopbackServer(path: "/cb")
        let url = try await server.start()
        #expect(url.host() == "127.0.0.1")
        #expect(url.port != nil && url.port != 0)

        async let callback = server.waitForCallback(timeout: .seconds(5))
        // a stray request first (browsers ask for /favicon.ico)
        let (_, r404) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(url.port!)/favicon.ico")!)
        #expect((r404 as? HTTPURLResponse)?.statusCode == 404)
        let (body, r200) = try await URLSession.shared.data(from: URL(string: url.absoluteString + "?code=abc123")!)
        #expect((r200 as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("Flitch"))
        #expect(try await callback["code"] == "abc123")
    }

    @Test func timesOut() async throws {
        let server = OAuthLoopbackServer()
        _ = try await server.start()
        await #expect(throws: FlitchError.other("sign-in timed out")) {
            _ = try await server.waitForCallback(timeout: .milliseconds(100))
        }
    }
}

struct OpenRouterAuthTests {
    @Test func authorizationURLCarriesCallbackAndChallenge() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = OpenRouterAuth.authorizationURL(callback: URL(string: "http://127.0.0.1:5555/cb")!, pkce: pkce)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host() == "openrouter.ai" && url.path() == "/auth")
        #expect(items.first { $0.name == "callback_url" }?.value == "http://127.0.0.1:5555/cb")
        #expect(items.first { $0.name == "code_challenge" }?.value == pkce.challenge)
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
    }

    @Test func fullSignInFlow() async throws {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { _ in .init(body: Data(#"{"key":"sk-or-v1-user"}"#.utf8)) }
        let auth = OpenRouterAuth(
            http: HTTPTransport(session: session), exchangeURL: URL(string: "https://\(host)/api/v1/auth/keys")!)

        // the "browser": follow callback_url with a code, like OpenRouter would after login
        let key = try await auth.signIn(timeout: .seconds(5)) { authURL in
            let items = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let callback = items.first { $0.name == "callback_url" }!.value!
            Task { _ = try? await URLSession.shared.data(from: URL(string: callback + "?code=one-time-code")!) }
        }
        #expect(key == "sk-or-v1-user")

        let exchange = try #require(StubURLProtocol.requests(host: host).first)
        let body = try JSONSerialization.jsonObject(with: exchange.body ?? Data()) as? [String: String]
        #expect(body?["code"] == "one-time-code")
        #expect(body?["code_challenge_method"] == "S256")
        #expect((body?["code_verifier"]?.count ?? 0) == 43)
    }

    @Test func badCodeIsReported() async {
        let host = uniqueHost()
        let session = StubURLProtocol.session(host: host) { _ in
            .init(status: 403, body: Data(#"{"error":{"message":"Invalid code"}}"#.utf8))
        }
        let auth = OpenRouterAuth(
            http: HTTPTransport(session: session), exchangeURL: URL(string: "https://\(host)/api/v1/auth/keys")!)
        await #expect(throws: FlitchError.invalidCredentials(provider: "OpenRouter")) {
            _ = try await auth.exchange(code: "x", pkce: .generate())
        }
    }
}
