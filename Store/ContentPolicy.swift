import Foundation

// ---------------------------------------------------------------------------
// ContentPolicy.swift  (Rext Roadmap Phase 6 — parental controls enforcement)
//
// A pure, deterministic gate that decides whether a piece of content is allowed
// for the active profile. Consumed by search, recommendations, trending, and
// smart collections so a child profile never surfaces disallowed content.
// ---------------------------------------------------------------------------

public nonisolated struct ContentPolicy: Sendable {
    public let controls: ParentalControls

    public init(controls: ParentalControls) {
        self.controls = controls
    }

    /// A policy that allows everything (used when no controls are active).
    public static let unrestricted = ContentPolicy(controls: ParentalControls(isEnabled: false))

    public func allows(kind: CatalogKind, genres: [String]) -> Bool {
        guard controls.isEnabled else { return true }

        if let allowedKinds = controls.allowedKinds, !allowedKinds.contains(kind.rawValue) {
            return false
        }
        if !controls.blockedGenres.isEmpty {
            let blocked = Set(controls.blockedGenres.map { $0.lowercased() })
            if genres.contains(where: { blocked.contains($0.lowercased()) }) { return false }
        }
        return true
    }

    public func allows(_ item: CatalogItem) -> Bool {
        allows(kind: item.kind, genres: item.resolvedMetadata.genres)
    }
}
