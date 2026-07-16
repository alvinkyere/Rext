import Foundation

// ---------------------------------------------------------------------------
// MediaCatalog.swift  (Rext — unified provider facade)
//
// The single surface the UI talks to for content, unifying native providers
// (MediaProvider) with sandboxed JS extensions (RuntimeEngine) behind one API:
// searchAll / details / streams. Callers pass a provider id and never care which
// kind backs it. This is where the "runtime doesn't care how a provider works"
// promise is realized.
// ---------------------------------------------------------------------------

@MainActor
final class MediaCatalog {
    static let shared = MediaCatalog()

    private(set) var nativeProviders: [String: any MediaProvider] = [:]

    var nativeProviderIDs: Set<String> { Set(nativeProviders.keys) }

    func register(_ provider: any MediaProvider) {
        nativeProviders[provider.id] = provider
    }

    func unregister(_ id: String) {
        nativeProviders[id] = nil
    }

    func isNative(_ id: String) -> Bool { nativeProviders[id] != nil }

    func nativeProvider(_ id: String) -> (any MediaProvider)? { nativeProviders[id] }

    /// Unified search across native providers + every JS extension. Results are
    /// grouped by provider and sorted by display name; per-provider failures are
    /// captured, never fatal.
    func searchAll(query: String, page: Int? = nil) async -> [UnifiedSearchResult] {
        var results = await RuntimeEngine.shared.searchAll(query: query, page: page)
        for provider in nativeProviders.values {
            do {
                let items = try await provider.search(query: query)
                results.append(UnifiedSearchResult(extensionID: provider.id, displayName: provider.displayName,
                                                   items: items, errorMessage: nil))
            } catch {
                results.append(UnifiedSearchResult(extensionID: provider.id, displayName: provider.displayName,
                                                   items: [], errorMessage: message(for: error)))
            }
        }
        return results.sorted { $0.displayName < $1.displayName }
    }

    func details(_ id: String, itemId: String) async throws -> MediaDetails {
        if let provider = nativeProviders[id] { return try await provider.details(itemId: itemId) }
        return try await RuntimeEngine.shared.details(id, itemId: itemId)
    }

    func streams(_ id: String, itemId: String, episodeId: String?) async throws -> [StreamSource] {
        if let provider = nativeProviders[id] { return try await provider.streams(itemId: itemId, episodeId: episodeId) }
        return try await RuntimeEngine.shared.streams(id, itemId: itemId, episodeId: episodeId)
    }

    private func message(for error: Error) -> String {
        (error as? ConnectorError)?.message ?? error.localizedDescription
    }
}
