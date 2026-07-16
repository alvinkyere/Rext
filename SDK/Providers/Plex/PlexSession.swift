import Foundation

// ---------------------------------------------------------------------------
// PlexSession.swift  (Rext — Plex provider)
//
// An actor that holds the authenticated Plex state: the account auth token, the
// chosen server connection (base URL + per-server access token), and the
// discovered libraries. `connect` runs account lookup + resource discovery +
// server selection; `restore` rebuilds the same state from a persisted token on
// launch. Server selection is multi-server aware and prefers local connections.
// ---------------------------------------------------------------------------

nonisolated struct PlexServerConnection: Sendable, Equatable {
    let name: String
    let baseURL: URL
    let accessToken: String
    let version: String?
}

nonisolated struct PlexLibrary: Sendable, Identifiable, Equatable {
    let id: String       // Plex section key
    let title: String
    let type: String
}

actor PlexSession {
    private let api: PlexAPI
    private let logger = RuntimeLogger(extensionID: PlexProvider.providerID)

    private(set) var authToken: String?
    private(set) var account: PlexAccount?
    private(set) var server: PlexServerConnection?
    private(set) var libraries: [PlexLibrary] = []

    init(api: PlexAPI = PlexAPI()) {
        self.api = api
    }

    func connect(authToken: String) async throws {
        self.authToken = authToken
        account = try? await api.account(token: authToken)

        let resources = try await api.resources(token: authToken)
        let candidates = Self.candidates(resources)
        logger.network("Discovered \(candidates.count) server connection(s)")

        // Pick the first connection that actually responds (local → remote → relay).
        var chosen: PlexServerConnection?
        for candidate in candidates {
            if await api.isReachable(base: candidate.baseURL, token: candidate.accessToken) {
                chosen = candidate
                break
            }
            logger.network("Unreachable: \(candidate.baseURL.absoluteString)")
        }
        guard let connection = chosen else {
            throw ConnectorError(.unknown, "No reachable Plex server found (check the app is on the same network, or enable Remote Access / Relay in Plex).")
        }
        server = connection
        logger.network("Connected to \(connection.name) @ \(connection.baseURL.absoluteString)")

        libraries = ((try? await api.sections(base: connection.baseURL, token: connection.accessToken)) ?? [])
            .map { PlexLibrary(id: $0.key, title: $0.title, type: $0.type) }
        logger.network("Loaded \(libraries.count) librar\(libraries.count == 1 ? "y" : "ies")")
    }

    func restore(authToken: String) async throws {
        try await connect(authToken: authToken)
    }

    /// The base URL + access token for the active server, if connected.
    func serverAccess() -> (base: URL, token: String)? {
        guard let server else { return nil }
        return (server.baseURL, server.accessToken)
    }

    func summary() -> (user: String?, serverName: String?, version: String?) {
        (account?.username ?? account?.title, server?.name, server?.version)
    }

    func librarySummaries() -> [PlexLibrary] { libraries }

    // MARK: - Server selection

    /// All candidate server connections across the account, ordered best-first
    /// (local HTTPS → remote HTTPS → other → relay). `connect` probes these in
    /// order and uses the first that responds.
    static func candidates(_ resources: [PlexResource]) -> [PlexServerConnection] {
        let servers = resources.filter { ($0.provides ?? "").contains("server") }
        var result: [(connection: PlexServerConnection, rank: Int)] = []
        for resource in servers {
            guard let token = resource.accessToken, let connections = resource.connections else { continue }
            for connection in connections {
                guard let url = URL(string: connection.uri) else { continue }
                result.append((PlexServerConnection(name: resource.name, baseURL: url,
                                                    accessToken: token, version: resource.productVersion),
                               rank(connection)))
            }
        }
        return result.sorted { $0.rank < $1.rank }.map(\.connection)
    }

    /// The single best connection (no probing) — used by tests.
    static func pickServer(_ resources: [PlexResource]) -> PlexServerConnection? {
        candidates(resources).first
    }

    private static func rank(_ connection: PlexConnection) -> Int {
        let isHTTPS = connection.protocol == "https" || connection.uri.hasPrefix("https")
        if connection.relay == true { return 3 }
        if connection.local == true && isHTTPS { return 0 }
        if isHTTPS { return 1 }
        return 2
    }
}
