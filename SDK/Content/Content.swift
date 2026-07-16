import Foundation

// ---------------------------------------------------------------------------
// Content.swift  (Rext Roadmap Phase 3 — Universal Content Graph)
//
// The canonical, provider-agnostic representation of a piece of media. Every
// provider is normalized into this graph; the UI and Intelligence layers consume
// `Content` without knowing which provider(s) it came from.
//
//   Provider CatalogItem/MediaDetails ─► ContentGraph.ingest ─► Content (node)
//
// `ContentMetadata` (RuntimeModels) serves as the roadmap's "MediaMetadata": the
// normalized genres/creators/cast/topics/dates layer. A `Content` binds an
// identity to that metadata plus the set of providers that can serve it
// (`ProviderAvailability`) and its links to other content (`ContentRelationship`).
// ---------------------------------------------------------------------------

/// How to locate a piece of content within one provider. A single canonical
/// `Content` may be reachable through several providers (cross-provider linking).
public nonisolated struct ProviderAvailability: Codable, Hashable, Sendable {
    public let extensionID: String
    public let itemID: String
    public var firstSeen: Date

    public init(extensionID: String, itemID: String, firstSeen: Date = .now) {
        self.extensionID = extensionID
        self.itemID = itemID
        self.firstSeen = firstSeen
    }

    /// The id this locator maps to before any cross-provider merge.
    public var contentID: ContentID { .provider(extensionID: extensionID, itemID: itemID) }
}

/// The nature of a link between two pieces of content.
public nonisolated enum ContentRelationshipType: String, Codable, Sendable {
    /// Generic "related content" (e.g. a provider's related listing).
    case related
    /// The source is an episode / chapter / track of the target.
    case episodeOf
    /// The source and target are the same media on different providers (dedup).
    case sameAs
    /// The source continues / follows the target.
    case sequel
}

/// A directed link from one `Content` to another.
public nonisolated struct ContentRelationship: Codable, Hashable, Sendable {
    public let type: ContentRelationshipType
    public let target: String  // ContentID.rawValue

    public init(type: ContentRelationshipType, target: ContentID) {
        self.type = type
        self.target = target.rawValue
    }

    public var targetID: ContentID { ContentID(rawValue: target) }
}

/// The canonical content node the rest of the app consumes.
public nonisolated struct Content: Identifiable, Hashable, Sendable {
    public let id: ContentID
    public var title: String
    public var kind: CatalogKind
    public var artworkURL: String?
    /// Normalized metadata (the roadmap's "MediaMetadata").
    public var metadata: ContentMetadata
    /// Providers that can serve this content.
    public var availability: [ProviderAvailability]
    /// Links to other content nodes.
    public var relationships: [ContentRelationship]

    public init(
        id: ContentID,
        title: String,
        kind: CatalogKind,
        artworkURL: String? = nil,
        metadata: ContentMetadata = ContentMetadata(),
        availability: [ProviderAvailability] = [],
        relationships: [ContentRelationship] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.artworkURL = artworkURL
        self.metadata = metadata
        self.availability = availability
        self.relationships = relationships
    }

    /// Reconstruct a provider `CatalogItem` for playback / UI. Prefers the given
    /// provider's locator when available, else the first known provider.
    public func catalogItem(preferring extensionID: String? = nil) -> CatalogItem? {
        let locator = availability.first { $0.extensionID == extensionID } ?? availability.first
        guard let locator else { return nil }
        return CatalogItem(
            id: locator.itemID,
            title: title,
            subtitle: nil,
            artworkUrl: artworkURL,
            kind: kind,
            metadata: nil,
            canonical: metadata
        )
    }
}

// ---------------------------------------------------------------------------
// Metadata merging — when the same content is ingested again (or from another
// provider), keep the richer value per field and union the multi-valued lists,
// so the canonical node only ever grows more complete.
// ---------------------------------------------------------------------------

extension ContentMetadata {
    /// A copy of `self` enriched with any values `other` provides that `self` lacks.
    public func merged(with other: ContentMetadata) -> ContentMetadata {
        ContentMetadata(
            genres: Self.union(genres, other.genres),
            topics: Self.union(topics, other.topics),
            creators: Self.union(creators, other.creators),
            cast: Self.union(cast, other.cast),
            themes: Self.union(themes, other.themes),
            releaseDate: releaseDate ?? other.releaseDate,
            language: language ?? other.language,
            durationSeconds: durationSeconds ?? other.durationSeconds,
            availability: Self.union(availability, other.availability)
        )
    }

    /// Order-preserving union that keeps the first occurrence of each value.
    private static func union(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in lhs + rhs where seen.insert(value.lowercased()).inserted {
            result.append(value)
        }
        return result
    }
}
