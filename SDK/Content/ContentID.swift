import Foundation

// ---------------------------------------------------------------------------
// ContentID.swift  (Rext Roadmap Phase 3 — Universal Content Graph)
//
// A stable, provider-agnostic identifier for a piece of content. The Content
// Graph is the single source of truth: the Library, History, and Intelligence
// layers reference content by `ContentID` rather than duplicating provider
// metadata.
//
// In V1 each provider item deterministically maps to its own id. When
// cross-provider matching (Phase 5) discovers that two providers expose the
// *same* media, the duplicate nodes are merged and simply accumulate more
// `ProviderAvailability` — callers keep using whichever id they already hold via
// the graph's `.sameAs` relationships, so no reference is invalidated.
// ---------------------------------------------------------------------------

public nonisolated struct ContentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Derive a deterministic id from a single provider's locator.
    public static func provider(extensionID: String, itemID: String) -> ContentID {
        ContentID(rawValue: "\(extensionID)|\(itemID)")
    }

    public var description: String { rawValue }
}
