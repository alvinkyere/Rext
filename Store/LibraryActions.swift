import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// LibraryActions.swift  (Rext Phase 2)
//
// MainActor helpers that centralize SwiftData writes for the library and history,
// so views don't hand-roll fetch/insert/delete. Keyed upserts keep collections
// and resume positions idempotent.
// ---------------------------------------------------------------------------

@MainActor
enum LibraryActions {
    static func isSaved(_ item: CatalogItem, extensionID: String, in collection: LibraryCollection, context: ModelContext) -> Bool {
        let key = "\(extensionID)|\(item.id)|\(collection.rawValue)"
        let descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor).first) != nil
    }

    /// Add to a collection if absent, remove if present. Returns the new saved state.
    @discardableResult
    static func toggle(_ item: CatalogItem, extensionID: String, collection: LibraryCollection, context: ModelContext) -> Bool {
        let key = "\(extensionID)|\(item.id)|\(collection.rawValue)"
        let descriptor = FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            return false
        }
        context.insert(LibraryItem(
            extensionID: extensionID,
            itemID: item.id,
            title: item.title,
            subtitle: item.subtitle,
            artworkURL: item.artworkUrl,
            kind: item.kind.rawValue,
            collection: collection,
            genres: item.resolvedMetadata.genres
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
        let key = "\(extensionID)|\(item.id)"
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
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
            ))
        }
    }
}
