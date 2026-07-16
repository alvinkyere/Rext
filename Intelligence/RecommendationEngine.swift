import Foundation

// ---------------------------------------------------------------------------
// RecommendationEngine.swift  (Rext Roadmap Phase 2 — Priority 3)
//
// The deterministic ranking core. Given a set of candidate items (from any
// provider) and a TasteProfile, it scores each candidate by how well its
// canonical metadata overlaps the user's affinities, then returns an ordered,
// *explained* list. There is deliberately no AI here: every score is a
// transparent weighted sum, and every recommendation carries a human-readable
// reason. When the AI layer (Phase 6) arrives it can adopt the same
// `RecommendationRanking` contract, so the UI never changes.
// ---------------------------------------------------------------------------

/// A provider-tagged candidate to be ranked. The `extensionID` is preserved so a
/// recommendation can deep-link back into the extension that supplied it.
public nonisolated struct RecommendationCandidate: Sendable, Equatable {
    public let extensionID: String
    public let item: CatalogItem

    public init(extensionID: String, item: CatalogItem) {
        self.extensionID = extensionID
        self.item = item
    }
}

/// Why an item was recommended — kept structured so the UI can render it however
/// it likes, with `summary`/`headline` as ready-made presentations.
public nonisolated struct RecommendationReason: Sendable, Equatable {
    /// A title the user engaged with that shares metadata with the candidate.
    public let seedTitle: String?
    /// The user-affinity genres this candidate matched, strongest first.
    public let genres: [String]

    public init(seedTitle: String?, genres: [String]) {
        self.seedTitle = seedTitle
        self.genres = genres
    }

    /// Multi-line explanation, e.g.:
    ///     Recommended because:
    ///     You watched Interstellar
    ///     You like: Science Fiction, Space Exploration
    public var summary: String {
        var lines = ["Recommended because:"]
        if let seedTitle { lines.append("You watched \(seedTitle)") }
        if !genres.isEmpty { lines.append("You like: \(genres.prefix(3).joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    /// A compact one-liner for cards and rails.
    public var headline: String {
        if let seedTitle { return "Because you watched \(seedTitle)" }
        if let genre = genres.first { return "Because you like \(genre)" }
        return "Recommended for you"
    }
}

/// A ranked recommendation: the item, its provenance, its score, and its reason.
public nonisolated struct Recommendation: Sendable, Identifiable, Equatable {
    public let extensionID: String
    public let item: CatalogItem
    public let score: Double
    public let reason: RecommendationReason

    public var id: String { "\(extensionID)|\(item.id)" }

    public init(extensionID: String, item: CatalogItem, score: Double, reason: RecommendationReason) {
        self.extensionID = extensionID
        self.item = item
        self.score = score
        self.reason = reason
    }
}

/// The ranking contract. Implementations must be pure and deterministic so the
/// same inputs always yield the same ordering (v1 is rule-based; a future AI
/// ranker can conform to the same protocol).
public nonisolated protocol RecommendationRanking: Sendable {
    func rank(_ candidates: [RecommendationCandidate], against profile: TasteProfile, limit: Int) -> [Recommendation]
}

/// Rule-based Recommendation Engine v1. Scores each candidate as:
///
///     Σ genreAffinity(matched genre)  +  kindAffinity  +  Σ creatorAffinity
///
/// Candidates that overlap nothing in the profile score zero and are dropped, so
/// results are always justified. Ties break on title for stable output.
public nonisolated struct DeterministicRecommender: RecommendationRanking {
    /// How much a matching content kind (movie/podcast/…) contributes relative to
    /// genre matches. Genres dominate; kind is a gentle nudge.
    private let kindWeight = 0.25
    private let creatorWeight = 1.5

    public init() {}

    public func rank(_ candidates: [RecommendationCandidate], against profile: TasteProfile, limit: Int) -> [Recommendation] {
        guard !profile.isEmpty, limit > 0 else { return [] }

        var recommendations: [Recommendation] = []
        for candidate in candidates {
            guard let recommendation = score(candidate, against: profile) else { continue }
            recommendations.append(recommendation)
        }

        let ordered = recommendations.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.title < rhs.item.title
        }
        return Array(ordered.prefix(limit))
    }

    /// Score a single candidate; returns nil when nothing overlaps the profile.
    private func score(_ candidate: RecommendationCandidate, against profile: TasteProfile) -> Recommendation? {
        let metadata = candidate.item.resolvedMetadata

        // Genre overlap — the dominant signal, and the source of the explanation.
        var genreScore = 0.0
        var matchedGenres: [String] = []
        for genre in metadata.genres {
            guard let affinity = profile.genreScores[genre] else { continue }
            genreScore += affinity
            matchedGenres.append(genre)
        }

        // Creator overlap.
        var creatorScore = 0.0
        for creator in metadata.creators where profile.creatorScores[creator] != nil {
            creatorScore += (profile.creatorScores[creator] ?? 0) * creatorWeight
        }

        // Kind nudge.
        let kindScore = (profile.kindScores[candidate.item.kind.rawValue] ?? 0) * kindWeight

        let total = genreScore + creatorScore + kindScore
        // Require a genre or creator match; a bare kind match alone is too weak to
        // justify surfacing an item.
        guard total > 0, !(matchedGenres.isEmpty && creatorScore == 0) else { return nil }

        // Order matched genres by the user's affinity so the strongest reason leads.
        let orderedGenres = matchedGenres.sorted { lhs, rhs in
            let lhsScore = profile.genreScores[lhs] ?? 0
            let rhsScore = profile.genreScores[rhs] ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs < rhs
        }
        let seed = orderedGenres.first.flatMap { profile.genreExemplars[$0] }
        let reason = RecommendationReason(seedTitle: seed, genres: orderedGenres)

        return Recommendation(extensionID: candidate.extensionID, item: candidate.item, score: total, reason: reason)
    }
}
