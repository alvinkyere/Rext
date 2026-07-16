import Foundation

// ---------------------------------------------------------------------------
// SemanticIndex.swift  (Rext Roadmap Phase 5 — Intelligence: semantic indexing)
//
// A deterministic, ML-free "semantic" layer. Each content node is reduced to a
// `ContentSignature`: the normalized token sets of its title and canonical
// metadata. Two signatures are compared with weighted Jaccard overlap to yield a
// similarity in 0...1. This is the shared foundation for duplicate detection,
// cross-provider matching, and "more like this" — all without a model. When the
// AI layer (Phase 10) arrives it can replace the scorer behind the same shape.
// ---------------------------------------------------------------------------

/// The normalized fingerprint of a piece of content.
public nonisolated struct ContentSignature: Sendable, Equatable {
    public let id: ContentID
    public let kind: CatalogKind
    public let titleTokens: Set<String>
    public let genres: Set<String>
    public let creators: Set<String>
    public let topics: Set<String>

    public init(
        id: ContentID,
        kind: CatalogKind,
        titleTokens: Set<String>,
        genres: Set<String>,
        creators: Set<String>,
        topics: Set<String>
    ) {
        self.id = id
        self.kind = kind
        self.titleTokens = titleTokens
        self.genres = genres
        self.creators = creators
        self.topics = topics
    }

    /// No usable tokens at all — cannot be meaningfully compared.
    public var isEmpty: Bool { titleTokens.isEmpty && genres.isEmpty && creators.isEmpty }
}

public nonisolated struct SemanticIndex: Sendable {
    public init() {}

    /// Reduce a content node to its signature.
    public func signature(for content: Content) -> ContentSignature {
        ContentSignature(
            id: content.id,
            kind: content.kind,
            titleTokens: Self.tokenize(content.title),
            genres: Self.normalizeSet(content.metadata.genres),
            creators: Self.normalizeSet(content.metadata.creators),
            topics: Self.normalizeSet(content.metadata.topics)
        )
    }

    /// Weighted similarity in 0...1. Title dominates; creators and genres refine.
    /// Empty-vs-empty fields contribute nothing rather than a spurious match.
    public func similarity(_ a: ContentSignature, _ b: ContentSignature) -> Double {
        let title = Self.jaccard(a.titleTokens, b.titleTokens)
        let creators = Self.jaccard(a.creators, b.creators)
        let genres = Self.jaccard(a.genres, b.genres)
        let topics = Self.jaccard(a.topics, b.topics)
        return 0.60 * title + 0.20 * creators + 0.15 * genres + 0.05 * topics
    }

    /// Signatures most similar to `target`, strongest first, above `minimum`.
    /// Deterministic: ties break on the candidate id.
    public func mostSimilar(
        to target: ContentSignature,
        among candidates: [ContentSignature],
        minimum: Double,
        limit: Int
    ) -> [(signature: ContentSignature, score: Double)] {
        var scored: [(signature: ContentSignature, score: Double)] = []
        for candidate in candidates where candidate.id != target.id {
            let score = similarity(target, candidate)
            if score >= minimum {
                scored.append((signature: candidate, score: score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.signature.id.rawValue < rhs.signature.id.rawValue
        }
        return Array(scored.prefix(limit))
    }

    // MARK: - Tokenization

    /// Common words that carry no discriminating signal for titles.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with",
        "at", "by", "from", "part", "vol", "season", "episode", "ep",
    ]

    /// Lowercase, split on non-alphanumerics, drop stopwords and 1-char tokens.
    static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        var tokens = Set<String>()
        for part in parts {
            let token = String(part)
            if token.count > 1, !stopwords.contains(token) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    private static func normalizeSet(_ values: [String]) -> Set<String> {
        Set(values.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
