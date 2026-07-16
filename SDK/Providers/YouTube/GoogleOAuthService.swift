import Foundation
import CryptoKit

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// ---------------------------------------------------------------------------
// GoogleOAuthService.swift  (Rext — Sign in with Google for YouTube)
//
// Authorization Code + PKCE flow for the iOS OAuth client (no client secret).
// Uses ASWebAuthenticationSession so the redirect is captured via the reversed
// client-id callback scheme — no Info.plist URL-type registration required. The
// resulting tokens are handed back for secure storage in the Keychain; Rext never
// sees the user's Google password.
// ---------------------------------------------------------------------------

public struct GoogleTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiry: Date

    public var isValid: Bool { Date() < expiry.addingTimeInterval(-60) }
}

public enum GoogleOAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case noAuthorizationCode
    case tokenExchangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google sign-in isn't configured."
        case .cancelled: return "Sign-in was cancelled."
        case .noAuthorizationCode: return "No authorization code was returned."
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        }
    }
}

#if canImport(AuthenticationServices)
@MainActor
final class GoogleOAuthService: NSObject {
    private var session: ASWebAuthenticationSession?

    /// Run the interactive sign-in and return tokens.
    func signIn() async throws -> GoogleTokens {
        guard YouTubeConfig.isOAuthConfigured else { throw GoogleOAuthError.notConfigured }

        let verifier = Self.codeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let authURL = Self.authorizationURL(challenge: challenge)
        let scheme = YouTubeConfig.oauthReversedClientID

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleOAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleOAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        guard let code = Self.authorizationCode(from: callbackURL) else {
            throw GoogleOAuthError.noAuthorizationCode
        }
        return try await exchange(code: code, verifier: verifier)
    }

    /// The signed-in user's YouTube channel title (proof of a working connection).
    func channelTitle(accessToken: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [.init(name: "part", value: "snippet"), .init(name: "mine", value: "true")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try? JSONDecoder().decode(YTVideoListResponse.self, from: data) // reuses snippet decoding
        return response?.items.first?.snippet.title
    }

    // MARK: - Token exchange

    private func exchange(code: String, verifier: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": YouTubeConfig.oauthClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": YouTubeConfig.oauthRedirectURI,
        ]
        request.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleOAuthError.tokenExchangeFailed(body)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiry: Date().addingTimeInterval(token.expires_in)
        )
    }

    // MARK: - PKCE + URL helpers

    private static func authorizationURL(challenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: YouTubeConfig.oauthClientID),
            .init(name: "redirect_uri", value: YouTubeConfig.oauthRedirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: YouTubeConfig.oauthScope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    private static func authorizationCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
    }

    private static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
