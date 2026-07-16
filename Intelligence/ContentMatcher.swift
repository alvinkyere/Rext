import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// ContentMatcher.swift  (Rext Roadmap Phase 5 — duplicate detection +
// cross-provider matching)
//
// Two content nodes that describe the same media — whether ingested twice or
// surfaced by different providers — should collapse into one canonical node.
// `ContentMatcher` is the pure, deterministic clustering core (built on
// `SemanticIndex`); `ContentMatchingService` applies its results to the graph,
// merging provider availability and linking duplicates with `.sameAs`.
// ---------------------------------------------------------------------------

/// A cluster of content judged to be the same media. `primary` is the canonical
/// node the duplicates fold into (deterministically the smallest id).
public nonisolated struct ContentMatch: Sendable, Equatable, Identifiable {
    public let primary: ContentID
    public let duplicates: [ContentID]
    public let confidence: Double

    public var id: String { primary.rawValue }
    public var all: [ContentID] { [primary] + duplicates }

    public init(primary: ContentID, duplicates: [ContentID], confidence: Double) {
        self.primary = primary
        self.duplicates = duplicates
        self.confidence = confidence
    }
}

/// Pure clustering over content signatures. Deterministic: signatures are
/// processed in id order and each joins at most one cluster.
public nonisolated struct ContentMatcher: Sendable {
    public var index: SemanticIndex
    /// Minimum similarity to treat two nodes as the same media.
    public var threshold: Double

    public init(index: SemanticIndex = SemanticIndex(), threshold: Double = 0.72) {
        self.index = index
        self.threshold = threshold
    }

    public func clusters(_ signatures: [ContentSignature]) -> [ContentMatch] {
        let ordered = signatures
            .filter { !$0.isEmpty }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        var assigned = Set<String>()
        var matches: [ContentMatch] = []

        for seed in ordered where !assigned.contains(seed.id.rawValue) {
            var members: [(id: ContentID, score: Double)] = []
            for other in ordered where other.id != seed.id && !assigned.contains(other.id.rawValue) {
                // Only the same kind can be the same media.
                guard other.kind == seed.kind else { continue }
                let score = index.similarity(seed, other)
                if score >= threshold { members.append((other.id, score)) }
            }
            guard !members.isEmpty else { continue }

            assigned.insert(seed.id.rawValue)
            members.forEach { assigned.insert($0.id.rawValue) }

            let duplicates = members.map(\.id).sorted { $0.rawValue < $1.rawValue }
            let confidence = members.map(\.score).min() ?? threshold
            matches.append(ContentMatch(primary: seed.id, duplicates: duplicates, confidence: confidence))
        }
        return matches
    }
}

// ---------------------------------------------------------------------------
// Service — reads the graph, runs the matcher, applies merges. MainActor because
// it touches the ModelContext.
// ---------------------------------------------------------------------------

@MainActor
struct ContentMatchingService {
    let context: ModelContext
    var matcher = ContentMatcher()

    /// All duplicate/equivalence clusters currently present in the graph.
    func findMatches() -> [ContentMatch] {
        let signatures = ContentGraph(context: context).allContent().map(matcher.index.signature)
        return matcher.clusters(signatures)
    }

    /// Clusters whose members are served by more than one provider — the
    /// genuine cross-provider matches.
    func crossProviderMatches() -> [ContentMatch] {
        let providers = providerMap()
        return findMatches().filter { match in
            let extensionIDs = match.all.reduce(into: Set<String>()) { set, id in
                set.formUnion(providers[id.rawValue] ?? [])
            }
            return extensionIDs.count > 1
        }
    }

    /// Fold every detected duplicate into its primary; returns the number merged.
    @discardableResult
    func applyMerges() -> Int {
        let graph = ContentGraph(context: context)
        var merged = 0
        for match in findMatches() {
            for duplicate in match.duplicates {
                graph.merge(duplicate, into: match.primary)
                merged += 1
            }
        }
        return merged
    }

    /// contentID.rawValue → the providers that serve it.
    private func providerMap() -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for content in ContentGraph(context: context).allContent() {
            map[content.id.rawValue] = Set(content.availability.map(\.extensionID))
        }
        return map
    }
}
