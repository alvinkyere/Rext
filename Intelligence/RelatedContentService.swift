import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// RelatedContentService.swift  (Rext Roadmap Phase 5/9 — Related Content)
//
// "More Like This" for a given item, powered by the deterministic SemanticIndex
// over the Universal Content Graph. Finds the most similar content the user has
// encountered (searched, viewed, saved, queued), excludes the item itself, and
// respects the active profile's parental controls. Surfaced on the detail screen.
// ---------------------------------------------------------------------------

public nonisolated struct RelatedItem: Identifiable, Sendable, Equatable {
    public let extensionID: String
    public let item: CatalogItem
    public let score: Double
    public var id: String { "\(extensionID)|\(item.id)" }
}

@MainActor
struct RelatedContentService {
    let context: ModelContext
    var index = SemanticIndex()
    /// Looser than duplicate detection (0.72): related content need only share some signal.
    var minimumSimilarity = 0.15
    var policy: ContentPolicy?
    private var resolvedPolicy: ContentPolicy { policy ?? ProfileManager.shared.contentPolicy }

    func related(to item: CatalogItem, extensionID: String, limit: Int = 12) -> [RelatedItem] {
        let graph = ContentGraph(context: context)
        // Make sure the subject is in the graph so it has a signature to compare.
        graph.ingest(item, extensionID: extensionID)
        let targetID = ContentID.provider(extensionID: extensionID, itemID: item.id)
        guard let target = graph.content(for: targetID) else { return [] }

        let targetSignature = index.signature(for: target)
        let candidateSignatures = graph.allContent()
            .filter { $0.id != targetID }
            .map(index.signature)

        let matches = index.mostSimilar(
            to: targetSignature, among: candidateSignatures,
            minimum: minimumSimilarity, limit: limit
        )

        let policy = resolvedPolicy
        var results: [RelatedItem] = []
        for match in matches {
            guard let content = graph.content(for: match.signature.id),
                  let providerID = content.availability.first?.extensionID,
                  let catalogItem = content.catalogItem(preferring: providerID),
                  policy.allows(catalogItem) else { continue }
            results.append(RelatedItem(extensionID: providerID, item: catalogItem, score: match.score))
        }
        return results
    }
}
