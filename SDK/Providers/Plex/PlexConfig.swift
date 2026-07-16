import Foundation

// ---------------------------------------------------------------------------
// PlexConfig.swift  (Rext — Plex provider)
//
// Client identity + product headers every Plex request carries. Plex identifies
// a client by a stable `X-Plex-Client-Identifier`; we generate one once and
// persist it. No secret is required for the PIN OAuth flow.
// ---------------------------------------------------------------------------

enum PlexConfig {
    static let product = "Rext"
    static let version = "1.0"
    static let platform = "iOS"
    static let device = "Rext"

    /// plex.tv account API base.
    static let accountAPI = URL(string: "https://plex.tv/api/v2")!

    /// A stable per-install client identifier (persisted).
    static var clientIdentifier: String {
        let key = "com.rext.plex.clientIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// Standard Plex headers (JSON responses + client identity).
    static var headers: [String: String] {
        [
            "Accept": "application/json",
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Platform": platform,
            "X-Plex-Device": device,
            "X-Plex-Device-Name": device,
        ]
    }
}
