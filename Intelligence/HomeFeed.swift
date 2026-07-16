import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// HomeFeed.swift  (Rext Roadmap Phase 9 — Experience Evolution: dynamic feed)
//
// Assembles the Home screen as an ordered list of personalized sections rather
// than a fixed layout. Every section is data-driven from local platform
// services — Continue Watching (history), Up Next (queue), the Phase 5 smart
// collections (Trending / affinity), and Recently Added (library) — and empty
// sections are omitted, so the feed fills in and reorders itself as the profile
// engages. Network-backed recommendations are layered in separately by the view.
// ---------------------------------------------------------------------------

public nonisolated struct HomeFeedItem: Identifiable, Sendable, Equatable {
    public let extensionID: String
    public let item: CatalogItem
    /// Resume progress in 0...1 when this item comes from history.
    public let progress: Double?

    public var id: String { "\(extensionID)|\(item.id)" }
}

public nonisolated struct HomeSection: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let items: [HomeFeedItem]
}

@MainActor
struct HomeFeedBuilder {
    let context: ModelContext
    var profileID: String?
    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }

    func build(now: Date = .now) -> [HomeSection] {
        var sections: [HomeSection] = []

        // 1. Continue Watching — in-progress history, most recent first.
        let continueItems = inProgressHistory().map {
            HomeFeedItem(extensionID: $0.extensionID, item: CatalogItem(history: $0), progress: $0.progress)
        }
        appendIfNonEmpty(&sections, id: "continue", title: "Continue Watching", subtitle: nil, items: continueItems)

        // 2. Up Next — the explicit watch queue.
        let queue = WatchQueue(context: context, profileID: resolvedProfileID).items().map {
            HomeFeedItem(extensionID: $0.extensionID, item: CatalogItem(queue: $0), progress: nil)
        }
        appendIfNonEmpty(&sections, id: "queue", title: "Up Next", subtitle: nil, items: queue)

        // 3. Smart collections — Trending Now + affinity rails (Phase 5).
        let collections = SmartCollectionsBuilder(context: context, profileID: resolvedProfileID).build(now: now)
        for collection in collections {
            let items = collection.items.map { HomeFeedItem(extensionID: $0.extensionID, item: $0.item, progress: nil) }
            appendIfNonEmpty(&sections, id: collection.id, title: collection.title, subtitle: collection.subtitle, items: items)
        }

        // 4. Favorites — the profile's starred titles.
        let favorites = library(in: .favorites).map {
            HomeFeedItem(extensionID: $0.extensionID, item: CatalogItem(library: $0), progress: nil)
        }
        appendIfNonEmpty(&sections, id: "favorites", title: "Your Favorites", subtitle: nil, items: favorites)

        // 5. Recently Added — the profile's newest library saves.
        let recent = recentLibrary().map {
            HomeFeedItem(extensionID: $0.extensionID, item: CatalogItem(library: $0), progress: nil)
        }
        appendIfNonEmpty(&sections, id: "recently-added", title: "Recently Added", subtitle: nil, items: recent)

        return sections
    }

    // MARK: - Helpers

    private func appendIfNonEmpty(_ sections: inout [HomeSection], id: String, title: String, subtitle: String?, items: [HomeFeedItem]) {
        guard !items.isEmpty else { return }
        sections.append(HomeSection(id: id, title: title, subtitle: subtitle, items: items))
    }

    private func inProgressHistory() -> [HistoryEntry] {
        let profileID = resolvedProfileID
        let entries = (try? context.fetch(FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.lastAccessed, order: .reverse)]
        ))) ?? []
        return entries.filter(\.isInProgress)
    }

    private func library(in collection: LibraryCollection) -> [LibraryItem] {
        let profileID = resolvedProfileID
        let raw = collection.rawValue
        return (try? context.fetch(FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.profileID == profileID && $0.collectionRaw == raw },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        ))) ?? []
    }

    private func recentLibrary(limit: Int = 12) -> [LibraryItem] {
        let profileID = resolvedProfileID
        var descriptor = FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
