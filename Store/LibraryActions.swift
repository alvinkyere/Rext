import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// LibraryActions.swift  (Rext Phase 2, profile-scoped in Phase 6)
//
// MainActor helpers that centralize SwiftData writes for the library and history,
// so views don't hand-roll fetch/insert/delete. Keyed upserts keep collections
// and resume positions idempotent. All rows are scoped to the active user
// profile (Phase 6); keys embed the profile so the same item can live in more
// than one profile without colliding.
// ---------------------------------------------------------------------------

@MainActor
enum LibraryActions {
    private static var currentProfileID: String { ProfileManager.shared.currentProfileID }

    static func isSaved(_ item: CatalogItem, extensionID: String, in collection: LibraryCollection, context: ModelContext) -> Bool {
        let key = "\(currentProfileID)|\(extensionID)|\(item.id)|\(collection.rawValue)"
        let descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first) != nil
    }

    /// Add to a collection if absent, remove if present. Returns the new saved state.
    @discardableResult
    static func toggle(_ item: CatalogItem, extensionID: String, collection: LibraryCollection, context: ModelContext) -> Bool {
        let profileID = currentProfileID
        let key = "\(profileID)|\(extensionID)|\(item.id)|\(collection.rawValue)"
        let descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        let recorder = SwiftDataActivityRecorder(context: context)
        let isFavorites = collection == .favorites
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            recorder.record(.content(isFavorites ? .unfavorite : .unsave, extensionID: extensionID, item: item))
            return false
        }
        // Normalize into the Universal Content Graph (Phase 3) so the library row
        // references a canonical node rather than being the source of truth itself.
        ContentGraph(context: context).ingest(item, extensionID: extensionID)
        recorder.record(.content(isFavorites ? .favorite : .save, extensionID: extensionID, item: item))
        context.insert(LibraryItem(
            extensionID: extensionID,
            itemID: item.id,
            title: item.title,
            subtitle: item.subtitle,
            artworkURL: item.artworkUrl,
            kind: item.kind.rawValue,
            collection: collection,
            genres: item.resolvedMetadata.genres,
            profileID: profileID
        ))
        return true
    }

    /// Record or update playback/reading progress for resume + Continue.
    static func recordHistory(
        extensionID: String,
        item: CatalogItem,
        positionSeconds: Double,
        durationSeconds: Double,
        context: ModelContext
    ) {
        let profileID = currentProfileID
        let key = "\(profileID)|\(extensionID)|\(item.id)"
        // Keep the canonical graph in sync as content is played/read (Phase 3).
        ContentGraph(context: context).ingest(item, extensionID: extensionID)
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.positionSeconds = positionSeconds
            existing.durationSeconds = durationSeconds
            existing.lastAccessed = .now
        } else {
            context.insert(HistoryEntry(
                extensionID: extensionID,
                itemID: item.id,
                title: item.title,
                kind: item.kind.rawValue,
                artworkURL: item.artworkUrl,
                profileID: profileID,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
            ))
        }
    }
}
