import FlitchCore
import Foundation

/// "Sign in with OpenRouter": OAuth PKCE that gives Flitch a key owned (and billed) by the user.
public struct OpenRouterAuth: Sendable {
    public static let authorizeURL = URL(string: "https://openrouter.ai/auth")!
    public static let exchangeURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!

    private let http: HTTPTransport
    private let exchangeURL: URL

    public init(http: HTTPTransport = .makeDefault(), exchangeURL: URL = OpenRouterAuth.exchangeURL) {
        self.http = http
        self.exchangeURL = exchangeURL
    }

    public static func authorizationURL(callback: URL, pkce: PKCE) -> URL {
        var c = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        return c.url!
    }

    /// Exchanges the one-time code for the user's key.
    public func exchange(code: String, pkce: PKCE) async throws -> String {
        var req = URLRequest(url: exchangeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "code_verifier": pkce.verifier, "code_challenge_method": pkce.method,
        ])
        do {
            let data = try await http.data(req)
            guard let key = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String,
                !key.isEmpty
            else { throw FlitchError.other("OpenRouter didn't return a key") }
            return key
        } catch {
            throw FlitchError.fromProvider(error, provider: "OpenRouter")
        }
    }

    /// Full flow: loopback listener → browser → callback → exchange. `openURL` opens the browser.
    public func signIn(
        server: OAuthLoopbackServer = OAuthLoopbackServer(path: "/openrouter/callback"),
        timeout: Duration = .seconds(600),
        openURL: @Sendable (URL) async -> Void
    ) async throws -> String {
        let pkce = PKCE.generate()
        let callback = try await server.start()  // listener ready before the browser opens
        await openURL(Self.authorizationURL(callback: callback, pkce: pkce))
        let result = try await server.waitForCallback(timeout: timeout)
        guard let code = result["code"], !code.isEmpty else {
            throw FlitchError.other("sign-in was cancelled")
        }
        return try await exchange(code: code, pkce: pkce)
    }
}
