import Foundation

// ---------------------------------------------------------------------------
// PlexLibraryMapper.swift  (Rext — Plex provider)
//
// Pure functions that normalize Plex metadata into Rext's canonical models. No
// networking, no side effects — fully unit-testable offline. Plex models never
// escape past this layer; the rest of Rext sees only CatalogItem/MediaDetails.
// ---------------------------------------------------------------------------

enum PlexLibraryMapper {

    static func kind(for plexType: String) -> CatalogKind {
        switch plexType {
        case "movie": return .movie
        case "show": return .series
        case "season": return .series
        case "episode": return .episode
        case "track": return .track
        case "album", "artist": return .music
        case "clip": return .video
        default: return .other
        }
    }

    static func catalogItem(_ m: PlexMetadata, base: URL, token: String) -> CatalogItem {
        CatalogItem(
            id: m.ratingKey,
            title: displayTitle(m),
            subtitle: subtitle(m),
            artworkUrl: PlexImageLoader.artworkURL(base: base, path: m.thumb, token: token),
            kind: kind(for: m.type),
            metadata: providerBag(m),
            canonical: canonical(m)
        )
    }

    static func details(_ m: PlexMetadata, base: URL, token: String) -> MediaDetails {
        MediaDetails(
            id: m.ratingKey,
            title: displayTitle(m),
            subtitle: subtitle(m),
            artworkUrl: PlexImageLoader.artworkURL(base: base, path: m.thumb, token: token),
            backdropUrl: PlexImageLoader.artworkURL(base: base, path: m.art ?? m.thumb, token: token),
            kind: kind(for: m.type),
            metadata: providerBag(m),
            episodes: nil,
            canonical: canonical(m)
        )
    }

    // MARK: - Field helpers

    static func displayTitle(_ m: PlexMetadata) -> String {
        if m.type == "episode", let show = m.grandparentTitle {
            return "\(show) — \(m.title)"
        }
        return m.title
    }

    static func subtitle(_ m: PlexMetadata) -> String? {
        switch m.type {
        case "episode":
            if let s = m.parentIndex, let e = m.index { return String(format: "S%d · E%d", s, e) }
            return m.parentTitle
        case "track":
            return m.grandparentTitle ?? m.parentTitle
        default:
            if let year = m.year { return String(year) }
            return nil
        }
    }

    static func canonical(_ m: PlexMetadata) -> ContentMetadata {
        ContentMetadata(
            genres: tags(m.genre),
            topics: [],
            creators: tags(m.director),
            cast: tags(m.role),
            themes: [],
            releaseDate: releaseDate(m),
            language: nil,
            durationSeconds: m.duration.map { Double($0) / 1000.0 }
        )
    }

    private static func providerBag(_ m: PlexMetadata) -> [String: JSONScalar]? {
        var bag: [String: JSONScalar] = [:]
        if let summary = m.summary, !summary.isEmpty { bag["overview"] = .string(summary) }
        if let rating = m.contentRating { bag["contentRating"] = .string(rating) }
        if let score = m.rating { bag["rating"] = .double(score) }
        if let s = m.parentIndex { bag["season"] = .int(s) }
        if let e = m.index { bag["episode"] = .int(e) }
        if let offset = m.viewOffset { bag["resumeSeconds"] = .int(offset / 1000) }
        return bag.isEmpty ? nil : bag
    }

    private static func tags(_ tags: [PlexTag]?) -> [String] {
        (tags ?? []).compactMap { $0.tag }
    }

    private static func releaseDate(_ m: PlexMetadata) -> String? {
        if let date = m.originallyAvailableAt, !date.isEmpty { return date }
        if let year = m.year { return String(year) }
        return nil
    }
}
