import Foundation

// ---------------------------------------------------------------------------
// PlexProvider.swift  (Rext — Plex provider)
//
// The MediaProvider façade that plugs Plex into the Runtime. It wires the
// session (auth + server), the API (networking), the mapper (canonical models)
// and the resolver (playback), and exposes only the neutral provider contract.
// Registered in MediaCatalog once connected, so unified Search, MediaDetailView,
// the Content/Activity graphs, Continue Watching, Recommendations and AI all
// work automatically with zero provider-specific code above this layer.
// ---------------------------------------------------------------------------

struct PlexProvider: MediaProvider {
    static let providerID = "com.runtime.plex"

    let id = PlexProvider.providerID
    let displayName = "Plex"
    let kind: MediaProviderKind = .selfHosted

    let session: PlexSession
    private let api: PlexAPI
    private let logger = RuntimeLogger(extensionID: PlexProvider.providerID)

    init(session: PlexSession, api: PlexAPI = PlexAPI()) {
        self.session = session
        self.api = api
    }

    func search(query: String) async throws -> [CatalogItem] {
        let (base, token) = try await requireServer()
        do {
            let results = try await api.search(base: base, token: token, query: query)
            logger.network("search '\(query)' → \(results.count) result(s)")
            return results.map { PlexLibraryMapper.catalogItem($0, base: base, token: token) }
        } catch {
            logger.error("search '\(query)' failed: \(error.localizedDescription)")
            throw error
        }
    }

    func details(itemId: String) async throws -> MediaDetails {
        let (base, token) = try await requireServer()
        let container = try await api.metadata(base: base, token: token, ratingKey: itemId)
        guard let item = container.metadata?.first else {
            throw ConnectorError(.notFound, "Item not found on Plex")
        }
        return PlexLibraryMapper.details(item, base: base, token: token)
    }

    func streams(itemId: String, episodeId: String?) async throws -> [StreamSource] {
        let (base, token) = try await requireServer()
        let ratingKey = episodeId ?? itemId
        let container = try await api.metadata(base: base, token: token, ratingKey: ratingKey)
        guard let item = container.metadata?.first else {
            throw ConnectorError(.notFound, "No media found on Plex")
        }
        let sources = PlexPlaybackResolver.streams(from: item, base: base, token: token)
        guard !sources.isEmpty else {
            throw ConnectorError(.unknown, "No playable source for this item")
        }
        return sources
    }

    // MARK: - Provider management surface

    func libraries() async -> [PlexLibrary] { await session.librarySummaries() }
    func serverSummary() async -> (user: String?, serverName: String?, version: String?) { await session.summary() }

    private func requireServer() async throws -> (base: URL, token: String) {
        guard let access = await session.serverAccess() else {
            throw ConnectorError(.unknown, "Plex isn't connected")
        }
        return access
    }
}
