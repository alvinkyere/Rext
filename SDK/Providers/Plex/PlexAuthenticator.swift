import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// ---------------------------------------------------------------------------
// PlexAuthenticator.swift  (Rext — Plex provider)
//
// Plex OAuth PIN flow: create a PIN, present plex.tv's hosted sign-in in an
// ASWebAuthenticationSession (Rext never sees credentials), then poll the PIN
// until it carries an auth token. The token is handed back for Keychain storage
// and server discovery. Reuses the same web-auth pattern as GoogleOAuthService.
// ---------------------------------------------------------------------------

#if canImport(AuthenticationServices)
@MainActor
final class PlexAuthenticator: NSObject {
    private let api: PlexAPI
    private var webSession: ASWebAuthenticationSession?

    init(api: PlexAPI = PlexAPI()) {
        self.api = api
    }

    func signIn() async throws -> String {
        let pin = try await api.createPin()
        try await presentSignIn(code: pin.code)
        return try await pollForToken(pinID: pin.id)
    }

    private func presentSignIn(code: String) async throws {
        let url = Self.authURL(code: code)
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "rext") { callback, error in
                // Even if the user closes the sheet, they may have authorized — poll anyway.
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: callback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            session.start()
        }
    }

    private func pollForToken(pinID: Int) async throws -> String {
        for _ in 0..<60 {
            if let token = try? await api.checkPin(id: pinID).authToken, !token.isEmpty {
                return token
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw ConnectorError(.unknown, "Plex sign-in timed out")
    }

    /// Plex's hosted auth uses a `#?` fragment for its parameters.
    static func authURL(code: String) -> URL {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "clientID", value: PlexConfig.clientIdentifier),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "forwardUrl", value: "rext://plex-auth"),
            URLQueryItem(name: "context[device][product]", value: PlexConfig.product),
            URLQueryItem(name: "context[device][deviceName]", value: PlexConfig.device),
            URLQueryItem(name: "context[device][platform]", value: PlexConfig.platform),
        ]
        let query = components.percentEncodedQuery ?? ""
        return URL(string: "https://app.plex.tv/auth#?\(query)") ?? PlexConfig.accountAPI
    }
}

extension PlexAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = active?.keyWindow ?? active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
        return window ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
