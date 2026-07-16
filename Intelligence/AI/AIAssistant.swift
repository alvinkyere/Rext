import Foundation

// ---------------------------------------------------------------------------
// AIAssistant.swift  (Rext Roadmap Phase 10 — AI Platform)
//
// The AI seam. Rext's AI layer *consumes* existing platform services rather than
// bypassing them: it turns a natural-language request into a structured
// `SearchIntent` that drives the same unified search + Content Graph everything
// else uses. Two implementations back the protocol — a deterministic parser that
// works on every device (and is fully testable offline), and a FoundationModels
// (Apple Intelligence) implementation that slots in when the on-device model is
// available. The UI never knows which is active.
// ---------------------------------------------------------------------------

/// A structured interpretation of a natural-language search request.
public struct SearchIntent: Sendable, Equatable {
    public var keywords: [String]
    public var genres: [String]
    public var kinds: [CatalogKind]

    public init(keywords: [String] = [], genres: [String] = [], kinds: [CatalogKind] = []) {
        self.keywords = keywords
        self.genres = genres
        self.kinds = kinds
    }

    /// The query string to hand to the unified search engine.
    public func query(fallback: String) -> String {
        let terms = keywords + genres
        let joined = terms.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? fallback : joined
    }

    /// A human phrasing of how the request was understood, for a UI banner.
    public var summary: String {
        var parts: [String] = []
        if !kinds.isEmpty { parts.append(kinds.map(\.displayName).joined(separator: " / ")) }
        if !genres.isEmpty { parts.append("in \(genres.joined(separator: ", "))") }
        if !keywords.isEmpty { parts.append("about \(keywords.joined(separator: ", "))") }
        return parts.isEmpty ? "Searching everything" : "Showing \(parts.joined(separator: " "))"
    }

    /// Does an item satisfy the genre/kind constraints of this intent?
    public func matches(_ item: CatalogItem) -> Bool {
        if !kinds.isEmpty, !kinds.contains(item.kind) { return false }
        if !genres.isEmpty {
            let itemGenres = Set(item.resolvedMetadata.genres.map { $0.lowercased() })
            let wanted = Set(genres.map { $0.lowercased() })
            if itemGenres.isDisjoint(with: wanted) { return false }
        }
        return true
    }
}

public protocol AIAssistant: Sendable {
    /// True when a real on-device model backs this assistant.
    var isModelBacked: Bool { get }
    /// Parse a natural-language request into a structured search intent.
    func interpretSearch(_ prompt: String) async -> SearchIntent
}

// ---------------------------------------------------------------------------
// Deterministic assistant — the always-available default.
// ---------------------------------------------------------------------------

public struct DeterministicAIAssistant: AIAssistant {
    public let isModelBacked = false
    public init() {}

    /// Words that carry intent phrasing but not search signal.
    private static let filler: Set<String> = [
        "show", "me", "find", "search", "for", "something", "some", "a", "an", "the",
        "want", "to", "watch", "listen", "read", "with", "and", "or", "of", "please",
        "i", "im", "about", "like", "give", "get", "any", "all",
    ]

    private static let kindWords: [String: CatalogKind] = [
        "movie": .movie, "movies": .movie, "film": .movie, "films": .movie,
        "show": .series, "shows": .series, "series": .series, "tv": .series,
        "episode": .episode, "episodes": .episode,
        "video": .video, "videos": .video,
        "podcast": .podcast, "podcasts": .podcast,
        "song": .track, "songs": .track, "track": .track, "music": .music,
        "book": .book, "books": .book, "stream": .stream, "streams": .stream,
    ]

    public func interpretSearch(_ prompt: String) async -> SearchIntent {
        let genres = GenreVocabulary.detected(in: prompt)
        let lower = prompt.lowercased()

        var kinds: [CatalogKind] = []
        var keywords: [String] = []
        let tokens = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let genreWords = Set(genres.flatMap { $0.lowercased().split(separator: " ").map(String.init) })

        for token in tokens where token.count > 1 {
            if let kind = Self.kindWords[token] {
                if !kinds.contains(kind) { kinds.append(kind) }
            } else if !Self.filler.contains(token) && !genreWords.contains(token) {
                if !keywords.contains(token) { keywords.append(token) }
            }
        }
        return SearchIntent(keywords: keywords, genres: genres, kinds: kinds)
    }
}

// ---------------------------------------------------------------------------
// Factory — picks the FoundationModels assistant when it's compiled in and the
// OS is new enough; otherwise the deterministic one. Runtime model availability
// is handled inside the FoundationModels assistant (it falls back gracefully).
// ---------------------------------------------------------------------------

public enum AIAssistantFactory {
    public static func make() -> AIAssistant {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return FoundationModelsAssistant()
        }
        #endif
        return DeterministicAIAssistant()
    }

    /// A short label describing which AI path is active, for the UI.
    public static var availabilityLabel: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return FoundationModelsAssistant.availabilityLabel
        }
        #endif
        return "Built-in understanding"
    }
}

extension CatalogKind {
    /// A display name for AI/search summaries.
    var displayName: String {
        switch self {
        case .series: return "series"
        case .movie: return "movies"
        case .episode: return "episodes"
        case .video: return "videos"
        case .podcast: return "podcasts"
        case .music: return "music"
        case .track: return "tracks"
        case .stream: return "streams"
        case .book: return "books"
        case .other: return "titles"
        }
    }
}
