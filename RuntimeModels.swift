import Foundation

// ---------------------------------------------------------------------------
// RuntimeModels.swift
//
// Swift Codable mirrors of the data contracts (doc 03 §5, doc 04). Decoding a
// connector's JS return value into these types IS the return-value validation
// (doc 03 §4.6): if the JSON doesn't fit, decoding throws and the host raises
// ConnectorError.invalidResponse before any component sees the value.
// ---------------------------------------------------------------------------

public nonisolated enum CatalogKind: String, Codable, Sendable {
    case series, movie, episode, video, podcast, music, track, stream, book, other

    /// Lenient: an unrecognized kind degrades to `.other` rather than failing the
    /// whole decode, so arbitrary providers never break parsing.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CatalogKind(rawValue: raw) ?? .other
    }
}

// ---------------------------------------------------------------------------
// Hybrid metadata model (Roadmap Phase 1, Feature 2).
//
// Rext separates a CANONICAL, normalized layer (`ContentMetadata`) from the raw
// PROVIDER layer (the item's `metadata` scalar bag). Providers keep sending
// whatever they like in `metadata`; Rext normalizes common concepts (genres,
// creators, cast, topics, themes, dates…) into `canonical` so filtering,
// grouping, search, and recommendations work consistently across every provider
// without losing provider-specific values.
// ---------------------------------------------------------------------------

public nonisolated struct ContentMetadata: Sendable, Codable, Hashable {
    public var genres: [String]
    public var topics: [String]
    public var creators: [String]
    public var cast: [String]
    public var themes: [String]
    /// A normalized release date/year string (kept as text for provider flexibility).
    public var releaseDate: String?
    public var language: String?
    public var durationSeconds: Double?
    /// Provider ids/names where this content is available (cross-provider linking).
    public var availability: [String]

    public init(
        genres: [String] = [],
        topics: [String] = [],
        creators: [String] = [],
        cast: [String] = [],
        themes: [String] = [],
        releaseDate: String? = nil,
        language: String? = nil,
        durationSeconds: Double? = nil,
        availability: [String] = []
    ) {
        self.genres = genres
        self.topics = topics
        self.creators = creators
        self.cast = cast
        self.themes = themes
        self.releaseDate = releaseDate
        self.language = language
        self.durationSeconds = durationSeconds
        self.availability = availability
    }

    public var isEmpty: Bool {
        genres.isEmpty && topics.isEmpty && creators.isEmpty && cast.isEmpty
            && themes.isEmpty && releaseDate == nil && language == nil
            && durationSeconds == nil && availability.isEmpty
    }
}

/// A JSON scalar for the open-ended `metadata` map (string | number | boolean).
public nonisolated enum JSONScalar: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported metadata scalar")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        }
    }
}

public nonisolated struct CatalogItem: Sendable, Identifiable, Codable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let artworkUrl: String?
    public let kind: CatalogKind
    /// Raw provider values, preserved as-is.
    public let metadata: [String: JSONScalar]?
    /// Normalized canonical metadata (derived by Rext, or supplied by the extension).
    public let canonical: ContentMetadata?

    public init(id: String, title: String, subtitle: String?, artworkUrl: String?, kind: CatalogKind, metadata: [String: JSONScalar]?, canonical: ContentMetadata? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.kind = kind
        self.metadata = metadata
        self.canonical = canonical
    }

    /// Canonical metadata, never nil (empty when none is available).
    public var resolvedMetadata: ContentMetadata { canonical ?? ContentMetadata() }
}

public nonisolated struct MediaDetails: Sendable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let artworkUrl: String?
    public let backdropUrl: String?
    public let kind: CatalogKind
    public let metadata: [String: JSONScalar]?
    public let episodes: [CatalogItem]?
    public let canonical: ContentMetadata?

    public init(id: String, title: String, subtitle: String?, artworkUrl: String?, backdropUrl: String?, kind: CatalogKind, metadata: [String: JSONScalar]?, episodes: [CatalogItem]?, canonical: ContentMetadata? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.backdropUrl = backdropUrl
        self.kind = kind
        self.metadata = metadata
        self.episodes = episodes
        self.canonical = canonical
    }

    public var resolvedMetadata: ContentMetadata { canonical ?? ContentMetadata() }
}

public nonisolated struct StreamSource: Sendable, Identifiable, Codable {
    public let id: String
    public let url: String
    public let quality: String?
    public let format: String?
    public let metadata: [String: JSONScalar]?
    
    public init(id: String, url: String, quality: String?, format: String?, metadata: [String: JSONScalar]?) {
        self.id = id
        self.url = url
        self.quality = quality
        self.format = format
        self.metadata = metadata
    }
}
