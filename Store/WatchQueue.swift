import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// WatchQueue.swift  (Rext Roadmap Phase 9 — Experience Evolution)
//
// MainActor helpers for the profile-scoped watch queue: enqueue, dequeue,
// reorder, and read the ordered list. Centralized so views never hand-roll
// SwiftData writes, mirroring LibraryActions.
// ---------------------------------------------------------------------------

@MainActor
struct WatchQueue {
    let context: ModelContext
    var profileID: String?
    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }

    /// The queue in play order (ascending position).
    func items() -> [QueueItem] {
        let profileID = resolvedProfileID
        return (try? context.fetch(FetchDescriptor<QueueItem>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.position, order: .forward)]
        ))) ?? []
    }

    /// The next item to play.
    var next: QueueItem? { items().first }

    func contains(_ item: CatalogItem, extensionID: String) -> Bool {
        let key = "\(resolvedProfileID)|\(extensionID)|\(item.id)"
        return (try? context.fetchCount(FetchDescriptor<QueueItem>(predicate: #Predicate { $0.key == key }))) ?? 0 > 0
    }

    /// Enqueue if absent, remove if present. Returns the new queued state.
    @discardableResult
    func toggle(_ item: CatalogItem, extensionID: String) -> Bool {
        let profileID = resolvedProfileID
        let key = "\(profileID)|\(extensionID)|\(item.id)"
        if let existing = (try? context.fetch(FetchDescriptor<QueueItem>(predicate: #Predicate { $0.key == key })))?.first {
            context.delete(existing)
            reindex()
            return false
        }
        ContentGraph(context: context).ingest(item, extensionID: extensionID)
        let nextPosition = (items().map(\.position).max() ?? -1) + 1
        context.insert(QueueItem(
            extensionID: extensionID, itemID: item.id, title: item.title, subtitle: item.subtitle,
            artworkURL: item.artworkUrl, kind: item.kind.rawValue, position: nextPosition, profileID: profileID
        ))
        return true
    }

    /// Remove the front of the queue (e.g. after it starts playing).
    func removeFirst() {
        guard let first = next else { return }
        context.delete(first)
        reindex()
    }

    func remove(_ queueItem: QueueItem) {
        context.delete(queueItem)
        reindex()
    }

    func clear() {
        for item in items() { context.delete(item) }
    }

    /// Move the item at `source` offsets to `destination` (List onMove semantics),
    /// implemented without SwiftUI so the Store layer stays UI-free.
    func move(from source: IndexSet, to destination: Int) {
        var ordered = items()
        let moving = source.sorted().map { ordered[$0] }
        for index in source.sorted(by: >) { ordered.remove(at: index) }
        let adjusted = destination - source.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: min(max(adjusted, 0), ordered.count))
        for (index, item) in ordered.enumerated() { item.position = index }
    }

    /// Renumber positions to stay contiguous after a removal.
    private func reindex() {
        for (index, item) in items().enumerated() { item.position = index }
    }
}
