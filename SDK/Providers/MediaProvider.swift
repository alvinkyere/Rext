import Foundation

// ---------------------------------------------------------------------------
// MediaProvider.swift  (Rext — provider-type system)
//
// A provider is any source of content, regardless of *how* it's implemented. The
// runtime doesn't care whether a provider is a sandboxed JS extension, a native
// API client, a web experience, or a local library — it only asks for search,
// details, and streams against the same canonical models. This protocol is the
// contract for native (in-app, Swift) providers; JS extensions are surfaced
// through the same unified pipeline by `MediaCatalog`.
// ---------------------------------------------------------------------------

public enum MediaProviderKind: String, Sendable {
    case native        // in-app Swift implementation
    case api           // official REST/GraphQL API + sanctioned player
    case web           // user-driven web experience (WKWebView)
    case local         // on-device media
    case selfHosted    // user's own server (Plex/Jellyfin)
}

public protocol MediaProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var kind: MediaProviderKind { get }

    func search(query: String) async throws -> [CatalogItem]
    func details(itemId: String) async throws -> MediaDetails
    func streams(itemId: String, episodeId: String?) async throws -> [StreamSource]
}
