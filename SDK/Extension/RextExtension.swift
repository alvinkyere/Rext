import Foundation

// ---------------------------------------------------------------------------
// RextExtension.swift  (Rext Extension SDK — the extension contract)
//
// The host-side protocol the engine programs against. Every installed extension
// is presented to the engine as a `RextExtension`, regardless of how it is
// implemented. Today the only implementation is `JSExtension` (a sandboxed
// JavaScript package) — the only way to ship third-party, install-without-an-
// app-update extensions on iOS. The protocol is the seam that keeps the engine
// independent of that fact: a future first-party native source could conform to
// the same contract.
//
// Extensions provide data only. They never create UI, navigation, or state —
// those belong to the host.
// ---------------------------------------------------------------------------

public protocol RextExtension: Sendable {
    /// The extension's manifest id.
    nonisolated var id: String { get }

    /// Called once before first use so the extension can prepare itself with the
    /// host-granted context. For JS extensions the context is already live at
    /// runtime creation, so this is typically a lightweight hook.
    func initialize(context: RextExtensionContext) async

    /// Find content (capability `search`).
    func search(query: String, page: Int?) async throws -> [CatalogItem]

    /// Full details for an item (capability `details`).
    func getDetails(id: String) async throws -> MediaDetails

    /// Child episodes / chapters for an item (capability `episodes`).
    func getEpisodes(id: String) async throws -> [CatalogItem]

    /// Resolve playable sources (capability `streams`).
    func getStreams(itemId: String, episodeId: String?) async throws -> [StreamSource]

    /// Open-ended, source-specific action. The `action` names a method the
    /// extension implements; `payload` is passed through. Still fully sandboxed —
    /// network/storage remain gated by the manifest's permissions.
    func execute(action: String, payload: [String: JSONScalar]) async throws -> RextResponse
}
