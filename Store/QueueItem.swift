import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// QueueItem.swift  (Rext Roadmap Phase 9 — Experience Evolution: watch queue)
//
// A profile-scoped, ordered "Up Next" queue. Distinct from library collections:
// the queue is an explicit play order the user curates. Ordering is an integer
// `position`; appends take the current max + 1. Keyed per profile so the same
// item can be queued independently across profiles (Phase 6).
// ---------------------------------------------------------------------------

@Model
final class QueueItem {
    @Attribute(.unique) var key: String
    var extensionID: String
    var itemID: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var kind: String
    /// Reference into the Universal Content Graph (Phase 3).
    var contentID: String
    /// Sort order within the queue (ascending).
    var position: Int
    var addedAt: Date
    /// Owning user profile (Phase 6).
    var profileID: String

    init(
        extensionID: String,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        artworkURL: String? = nil,
        kind: String,
        position: Int,
        profileID: String = UserProfile.defaultProfileID,
        addedAt: Date = .now
    ) {
        self.key = "\(profileID)|\(extensionID)|\(itemID)"
        self.contentID = "\(extensionID)|\(itemID)"
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.kind = kind
        self.position = position
        self.profileID = profileID
        self.addedAt = addedAt
    }

    var contentKind: CatalogKind { CatalogKind(rawValue: kind) ?? .other }
}
