import FlitchCore
import Foundation

/// "Continue with ChatGPT": OpenAI's open-source track lets Plus/Pro users use their plan in Flitch.
/// OIDC + PKCE with a loopback redirect on 127.0.0.1, dynamic client registration, rotating refresh tokens.
public struct ChatGPTAuth: Sendable {
    public static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    public static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    public static let resource = "https://api.openai.com/v1"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let requiredScope = "chatgpt.tokens.use.direct"
    public static let callbackPath = "/auth/callback"

    private let http: HTTPTransport
    private let tokenURL: URL

    public init(http: HTTPTransport = .makeDefault(), tokenURL: URL = ChatGPTAuth.tokenURL) {
        self.http = http
        self.tokenURL = tokenURL
    }

    /// A stable id for this Mac (`urn:uuid:…`), kept in user defaults.
    public static func hostID(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: "flitch.chatgpt.hostID") { return id }
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        defaults.set(id, forKey: "flitch.chatgpt.hostID")
        return id
    }

    public struct Attempt: Sendable {
        public let pkce: PKCE
        public let state: String
        public let nonce: String
        public let redirectURI: URL
    }

    public static func authorizationURL(attempt: Attempt, clientID: String?, hostID: String) -> URL {
        var c = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID ?? "dynamic_agent_client"),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: attempt.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: attempt.pkce.challenge),
        ]
        if clientID == nil { items.insert(URLQueryItem(name: "agent_name_hint", value: "Flitch"), at: 1) }
        c.queryItems = items
        return c.url!
    }

    /// Full sign-in. `previousClientID` reuses the issued client on reauthorization.
    public func signIn(
        previousClientID: String? = nil,
        hostID: String = ChatGPTAuth.hostID(),
        server: OAuthLoopbackServer = OAuthLoopbackServer(path: ChatGPTAuth.callbackPath),
        timeout: Duration = .seconds(600),
        openURL: @Sendable (URL) async -> Void
    ) async throws -> OAuthToken {
        let redirect = try await server.start()
        let attempt = Attempt(
            pkce: .generate(), state: PKCE.generate().verifier, nonce: PKCE.generate().verifier, redirectURI: redirect)
        await openURL(Self.authorizationURL(attempt: attempt, clientID: previousClientID, hostID: hostID))
        let callback = try await server.waitForCallback(timeout: timeout)
        guard callback["state"] == attempt.state else { throw FlitchError.other("sign-in failed (state mismatch)") }
        if let error = callback["error"] { throw FlitchError.other("ChatGPT sign-in: \(error)") }
        guard let code = callback["code"] else { throw FlitchError.other("sign-in was cancelled") }
        let clientID = callback["client_id"].flatMap { $0 == "dynamic_agent_client" ? nil : $0 } ?? previousClientID
        guard let clientID else { throw FlitchError.other("ChatGPT didn't register Flitch") }
        return try await exchange(code: code, attempt: attempt, clientID: clientID)
    }

    public func exchange(code: String, attempt: Attempt, clientID: String) async throws -> OAuthToken {
        try await tokenRequest(
            [
                "grant_type": "authorization_code", "client_id": clientID, "code": code,
                "code_verifier": attempt.pkce.verifier, "redirect_uri": attempt.redirectURI.absoluteString,
                "resource": Self.resource,
            ], clientID: clientID)
    }

    /// Refresh tokens rotate: the returned token replaces everything that was stored.
    public func refresh(_ token: OAuthToken) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken, let clientID = token.clientID else {
            throw FlitchError.invalidCredentials(provider: "ChatGPT")
        }
        var fresh = try await tokenRequest(
            [
                "grant_type": "refresh_token", "client_id": clientID, "refresh_token": refreshToken,
                "resource": Self.resource,
            ], clientID: clientID)
        if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
        fresh.accountName = fresh.accountName ?? token.accountName
        return fresh
    }

    private func tokenRequest(_ form: [String: String], clientID: String) async throws -> OAuthToken {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.formEncode(form).utf8)
        let data: Data
        do {
            data = try await http.data(req)
        } catch {
            throw FlitchError.fromProvider(error, provider: "ChatGPT", secrets: Array(form.values))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String
        else { throw FlitchError.other("ChatGPT returned no token") }
        let scopes = (json["scope"] as? String)?.split(separator: " ").map(String.init) ?? []
        guard scopes.isEmpty || scopes.contains(Self.requiredScope) else {
            throw FlitchError.other("ChatGPT plan usage wasn't allowed. Try again and accept every permission.")
        }
        let expires = (json["expires_in"] as? Double).map { Date().addingTimeInterval($0) }
        return OAuthToken(
            accessToken: access, refreshToken: json["refresh_token"] as? String, expiresAt: expires,
            scopes: scopes, clientID: clientID, accountName: Self.email(fromIDToken: json["id_token"] as? String))
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { k in
            "\(k)=\(form[k]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }

    /// Reads the e-mail claim for display. The signature isn't checked here: the token comes straight
    /// from OpenAI's token endpoint over TLS and is never used for authorization decisions.
    static func email(fromIDToken token: String?) -> String? {
        guard let token, token.split(separator: ".").count >= 2 else { return nil }
        var payload = String(token.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return claims["email"] as? String
    }
}
