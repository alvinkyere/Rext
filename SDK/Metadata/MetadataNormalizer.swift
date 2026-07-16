import Foundation

// ---------------------------------------------------------------------------
// MetadataNormalizer.swift  (Roadmap Phase 1, Feature 2 — hybrid metadata)
//
// Bridges the provider layer to the canonical layer. An extension may supply a
// typed `canonical` object directly; otherwise Rext derives one from the raw
// provider `metadata` bag (reading a range of common key aliases and splitting
// delimited lists). Genres are always run through `GenreVocabulary` so grouping,
// filtering, and recommendations see a consistent internal representation — while
// the original provider values remain untouched in `metadata`.
// ---------------------------------------------------------------------------

public nonisolated struct MetadataNormalizer: Sendable {
    public init() {}

    public func normalize(_ item: CatalogItem) -> CatalogItem {
        CatalogItem(
            id: item.id, title: item.title, subtitle: item.subtitle,
            artworkUrl: item.artworkUrl, kind: item.kind, metadata: item.metadata,
            canonical: canonicalMetadata(existing: item.canonical, provider: item.metadata)
        )
    }

    public func normalize(_ details: MediaDetails) -> MediaDetails {
        MediaDetails(
            id: details.id, title: details.title, subtitle: details.subtitle,
            artworkUrl: details.artworkUrl, backdropUrl: details.backdropUrl,
            kind: details.kind, metadata: details.metadata,
            episodes: details.episodes?.map(normalize),
            canonical: canonicalMetadata(existing: details.canonical, provider: details.metadata)
        )
    }

    /// Merge extension-supplied canonical metadata with values derived from the
    /// provider bag, then normalize the genre vocabulary.
    private func canonicalMetadata(existing: ContentMetadata?, provider: [String: JSONScalar]?) -> ContentMetadata {
        var meta = existing ?? ContentMetadata()
        let bag = provider ?? [:]

        if meta.genres.isEmpty { meta.genres = strings(bag, Self.genreKeys) }
        if meta.creators.isEmpty { meta.creators = strings(bag, Self.creatorKeys) }
        if meta.cast.isEmpty { meta.cast = strings(bag, Self.castKeys) }
        if meta.topics.isEmpty { meta.topics = strings(bag, Self.topicKeys) }
        if meta.themes.isEmpty { meta.themes = strings(bag, Self.themeKeys) }
        if meta.releaseDate == nil { meta.releaseDate = firstString(bag, Self.dateKeys) }
        if meta.language == nil { meta.language = firstString(bag, Self.languageKeys) }
        if meta.durationSeconds == nil { meta.durationSeconds = firstDouble(bag, Self.durationKeys) }

        meta.genres = normalizeGenres(meta.genres)
        return meta
    }

    /// Canonicalize + de-duplicate a list of genre strings.
    public func normalizeGenres(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            let canonical = GenreVocabulary.canonical(for: value)
            if seen.insert(canonical.lowercased()).inserted {
                result.append(canonical)
            }
        }
        return result
    }

    // MARK: - Provider key aliases

    private static let genreKeys = ["genres", "genre", "categories", "category"]
    private static let creatorKeys = ["creators", "creator", "author", "authors", "studio", "artist"]
    private static let castKeys = ["cast", "actors", "stars", "starring"]
    private static let topicKeys = ["topics", "topic", "tags"]
    private static let themeKeys = ["themes", "theme"]
    private static let dateKeys = ["releaseDate", "firstAired", "aired", "date", "year", "published"]
    private static let languageKeys = ["language", "lang"]
    private static let durationKeys = ["durationSeconds", "durationSec", "duration", "runtime", "length"]

    // MARK: - Extraction helpers

    private func strings(_ bag: [String: JSONScalar], _ keys: [String]) -> [String] {
        for key in keys {
            guard let value = bag[key] else { continue }
            switch value {
            case .string(let text): return splitList(text)
            case .int(let number): return [String(number)]
            case .double(let number): return [trimNumber(number)]
            case .bool: continue
            }
        }
        return []
    }

    private func firstString(_ bag: [String: JSONScalar], _ keys: [String]) -> String? {
        for key in keys {
            guard let value = bag[key] else { continue }
            switch value {
            case .string(let text): return text.trimmingCharacters(in: .whitespaces)
            case .int(let number): return String(number)
            case .double(let number): return trimNumber(number)
            case .bool: continue
            }
        }
        return nil
    }

    private func firstDouble(_ bag: [String: JSONScalar], _ keys: [String]) -> Double? {
        for key in keys {
            guard let value = bag[key] else { continue }
            switch value {
            case .int(let number): return Double(number)
            case .double(let number): return number
            case .string(let text): return Double(text)
            case .bool: continue
            }
        }
        return nil
    }

    private func splitList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func trimNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Maps arbitrary provider genre strings onto a consistent internal vocabulary.
/// Unknown genres are title-cased rather than dropped, so nothing is lost.
public nonisolated enum GenreVocabulary {
    private static let synonyms: [String: String] = [
        "sci-fi": "Science Fiction", "scifi": "Science Fiction",
        "science-fiction": "Science Fiction", "science fiction": "Science Fiction",
        "doc": "Documentary", "docs": "Documentary", "documentaries": "Documentary",
        "rom-com": "Romance", "romcom": "Romance",
        "children": "Kids", "kids": "Kids",
        "educational": "Education", "education": "Education",
        "tech": "Technology", "technology": "Technology",
        "sport": "Sports", "sports": "Sports",
        "news": "News", "music": "Music", "anime": "Anime", "history": "History",
        "comedy": "Comedy", "drama": "Drama", "action": "Action", "adventure": "Adventure",
        "thriller": "Thriller", "horror": "Horror", "fantasy": "Fantasy",
        "mystery": "Mystery", "crime": "Crime", "romance": "Romance", "animation": "Animation",
    ]

    public static func canonical(for raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let mapped = synonyms[key] { return mapped }
        return titleCased(raw)
    }

    /// The set of canonical genre names this vocabulary knows about.
    public static var allCanonical: Set<String> { Set(synonyms.values) }

    /// Canonical genres mentioned anywhere in free text (phrase-matched against
    /// both synonyms and canonical names). Deterministic: results are sorted.
    public static func detected(in text: String) -> [String] {
        let lower = text.lowercased()
        var found = Set<String>()
        for (synonym, canonical) in synonyms where lower.contains(synonym) { found.insert(canonical) }
        for canonical in allCanonical where lower.contains(canonical.lowercased()) { found.insert(canonical) }
        return found.sorted()
    }

    private static func titleCased(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
