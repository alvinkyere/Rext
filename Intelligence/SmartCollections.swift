import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// SmartCollections.swift  (Rext Roadmap Phase 5 — Intelligence: smart collections)
//
// Auto-generated, deterministic groupings assembled from the Content Graph
// (Phase 3), the Activity Graph (Phase 4), and the TasteProfile. Unlike the
// user's own library collections, these are computed: "Trending Now" and per-
// affinity "More <Genre>" rails that fill in as the user engages. Every
// collection is a neutral value type the UI renders without any provider or
// storage knowledge.
// ---------------------------------------------------------------------------

public nonisolated struct SmartCollectionEntry: Sendable, Identifiable, Equatable {
    public let extensionID: String
    public let item: CatalogItem
    public var id: String { "\(extensionID)|\(item.id)" }

    public init(extensionID: String, item: CatalogItem) {
        self.extensionID = extensionID
        self.item = item
    }
}

public nonisolated struct SmartCollection: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let items: [SmartCollectionEntry]

    public init(id: String, title: String, subtitle: String?, items: [SmartCollectionEntry]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}

@MainActor
struct SmartCollectionsBuilder {
    let context: ModelContext
    var maxItemsPerCollection = 12
    /// A collection with fewer than this many items isn't worth surfacing.
    var minItemsPerCollection = 2
    var genreCollectionLimit = 3
    /// The active profile whose taste + owned items drive the collections (Phase 6).
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?
    /// Parental-controls gate; nil = the active profile's policy.
    var policy: ContentPolicy?

    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }
    private var resolvedPolicy: ContentPolicy { policy ?? ProfileManager.shared.contentPolicy }

    func build(now: Date = .now) -> [SmartCollection] {
        let profileID = resolvedProfileID
        let policy = resolvedPolicy
        let graph = ContentGraph(context: context)
        var collections: [SmartCollection] = []

        // 1. Trending Now — momentum from the activity timeline.
        let trending = TrendingEngine(context: context, profileID: profileID).trending(limit: maxItemsPerCollection, now: now)
        let excluded = completedOrFavorited()
        let trendingEntries = trending.compactMap { entry(forTrending: $0, graph: graph) }.filter { policy.allows($0.item) }
        if trendingEntries.count >= minItemsPerCollection {
            collections.append(SmartCollection(
                id: "trending", title: "Trending Now",
                subtitle: "Based on your recent activity", items: trendingEntries
            ))
        }

        // 2. Affinity collections — "More <Genre>" for the user's top genres,
        //    drawn from graph content they haven't already finished or favorited.
        let profile = TasteProfileBuilder(context: context, profileID: profileID).build()
        if !profile.isEmpty {
            let allContent = graph.allContent()
            for genre in profile.topGenres.prefix(genreCollectionLimit) {
                let entries = allContent
                    .filter { $0.metadata.genres.contains(genre) && !excluded.contains($0.id.rawValue) }
                    .sorted { $0.title < $1.title }
                    .compactMap(entry(for:))
                    .filter { policy.allows($0.item) }
                    .prefix(maxItemsPerCollection)
                if entries.count >= minItemsPerCollection {
                    collections.append(SmartCollection(
                        id: "genre-\(genre)", title: "More \(genre)", subtitle: nil, items: Array(entries)
                    ))
                }
            }
        }

        return collections
    }

    // MARK: - Helpers

    private func entry(for content: Content) -> SmartCollectionEntry? {
        guard let extensionID = content.availability.first?.extensionID,
              let item = content.catalogItem(preferring: extensionID) else { return nil }
        return SmartCollectionEntry(extensionID: extensionID, item: item)
    }

    private func entry(forTrending trending: TrendingItem, graph: ContentGraph) -> SmartCollectionEntry? {
        // Prefer the richer graph node; fall back to the trending fields.
        if let content = graph.content(for: trending.contentID), let entry = entry(for: content) {
            return entry
        }
        let item = CatalogItem(
            id: trending.itemID, title: trending.title, subtitle: nil,
            artworkUrl: nil, kind: trending.kind, metadata: nil
        )
        return SmartCollectionEntry(extensionID: trending.extensionID, item: item)
    }

    /// contentID.rawValue values the user has already completed or favorited, so
    /// affinity rails don't re-surface finished content.
    private func completedOrFavorited() -> Set<String> {
        let profileID = resolvedProfileID
        var ids = Set<String>()
        let library = (try? context.fetch(FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        for item in library where item.collection == .completed || item.collection == .favorites {
            ids.insert(item.contentID)
        }
        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        for entry in history where entry.progress > 0.95 {
            ids.insert(entry.contentID)
        }
        return ids
    }
}
