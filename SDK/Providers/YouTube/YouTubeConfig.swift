import Foundation

// ---------------------------------------------------------------------------
// YouTubeConfig.swift  (Rext — YouTube provider configuration)
//
// ⚠️ SECURITY: This file holds the YouTube Data API key and is git-ignored
// (see .gitignore → **/YouTubeConfig.swift). Do NOT commit real keys.
//
// Before shipping, in Google Cloud Console:
//   • Restrict this key to the "YouTube Data API v3" only.
//   • Add an application restriction (iOS bundle id).
//   • Rotate the key if it has ever been shared in plaintext.
// ---------------------------------------------------------------------------

enum YouTubeConfig {
    /// YouTube Data API v3 key. Replace with your own; keep it out of source control.
    static let apiKey = "AIzaSyCEcusxUXI7SB8B9eicWRH0kr8HWgij0Bk"

    /// Whether a usable key is present (the provider stays unregistered otherwise).
    static var isConfigured: Bool {
        !apiKey.isEmpty && !apiKey.hasPrefix("YOUR_")
    }

    // MARK: - OAuth (Sign in with Google → connect YouTube account)

    /// iOS OAuth client id.
    static let oauthClientID = "887971551401-ru2l4bap4p396fmist4pqo5blsp7qnje.apps.googleusercontent.com"
    /// The reversed client id doubles as the ASWebAuthenticationSession callback scheme.
    static let oauthReversedClientID = "com.googleusercontent.apps.887971551401-ru2l4bap4p396fmist4pqo5blsp7qnje"
    /// Redirect URI registered for the iOS client.
    static var oauthRedirectURI: String { "\(oauthReversedClientID):/oauth2redirect" }
    /// Read-only access to the signed-in user's YouTube account.
    static let oauthScope = "https://www.googleapis.com/auth/youtube.readonly"

    static var isOAuthConfigured: Bool { !oauthClientID.hasPrefix("YOUR_") }
}
