import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// PersistenceModels.swift  (Rext Phase 2 — local persistence)
//
// SwiftData models for the consumer app's local state: the repositories the user
// has added, their library/collections, and playback/reading history. Installed
// extension *packages* are persisted separately on disk (InstalledPackageStore);
// these models hold user data only. Nothing here is cloud-synced in this phase.
// ---------------------------------------------------------------------------

/// The collections a saved item can belong to (Priority 5).
public enum LibraryCollection: String, CaseIterable, Codable, Sendable {
    case watching
    case reading
    case listening
    case completed
    case favorites

    public var title: String {
        switch self {
        case .watching: return "Watching"
        case .reading: return "Reading"
        case .listening: return "Listening"
        case .completed: return "Completed"
        case .favorites: return "Favorites"
        }
    }

    public var systemImage: String {
        switch self {
        case .watching: return "play.tv"
        case .reading: return "book"
        case .listening: return "headphones"
        case .completed: return "checkmark.circle"
        case .favorites: return "star"
        }
    }
}

/// A repository URL the user has added (Priority 1).
@Model
final class RepositorySource {
    @Attribute(.unique) var url: String
    var title: String?
    var addedAt: Date
    var isEnabled: Bool

    init(url: String, title: String? = nil, addedAt: Date = .now, isEnabled: Bool = true) {
        self.url = url
        self.title = title
        self.addedAt = addedAt
        self.isEnabled = isEnabled
    }
}

/// An item the user saved into a collection (Priority 5).
@Model
final class LibraryItem {
    /// Unique per (extension, item, collection) so an item can live in several collections.
    @Attribute(.unique) var key: String
    var extensionID: String
    var itemID: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var kind: String
    var collectionRaw: String
    var addedAt: Date
    /// Normalized canonical genres, captured at save time for grouping/recommendations.
    var genres: [String] = []
    /// Reference to the canonical node in the Universal Content Graph (Phase 3).
    var contentID: String = ""
    /// Owning user profile (Phase 6). Defaults to the default profile so pre-Phase-6 rows are retained.
    var profileID: String = UserProfile.defaultProfileID

    init(
        extensionID: String,
        itemID: String,
        title: String,
        subtitle: String? = nil,
        artworkURL: String? = nil,
        kind: String,
        collection: LibraryCollection,
        genres: [String] = [],
        profileID: String = UserProfile.defaultProfileID,
        addedAt: Date = .now
    ) {
        self.key = "\(profileID)|\(extensionID)|\(itemID)|\(collection.rawValue)"
        self.contentID = "\(extensionID)|\(itemID)"
        self.profileID = profileID
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.kind = kind
        self.collectionRaw = collection.rawValue
        self.genres = genres
        self.addedAt = addedAt
    }

    var collection: LibraryCollection { LibraryCollection(rawValue: collectionRaw) ?? .favorites }
    var contentKind: CatalogKind { CatalogKind(rawValue: kind) ?? .other }
}

/// A watched/read/listened item with resume position (Priorities 4 & 7).
@Model
final class HistoryEntry {
    @Attribute(.unique) var key: String
    var extensionID: String
    var itemID: String
    var title: String
    var kind: String
    var artworkURL: String?
    var lastAccessed: Date
    var positionSeconds: Double
    var durationSeconds: Double
    /// Reference to the canonical node in the Universal Content Graph (Phase 3).
    var contentID: String = ""
    /// Owning user profile (Phase 6).
    var profileID: String = UserProfile.defaultProfileID

    init(
        extensionID: String,
        itemID: String,
        title: String,
        kind: String,
        artworkURL: String? = nil,
        profileID: String = UserProfile.defaultProfileID,
        lastAccessed: Date = .now,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0
    ) {
        self.key = "\(profileID)|\(extensionID)|\(itemID)"
        self.contentID = "\(extensionID)|\(itemID)"
        self.profileID = profileID
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.artworkURL = artworkURL
        self.lastAccessed = lastAccessed
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
    }

    /// Fractional progress in `0...1`.
    var progress: Double {
        durationSeconds > 0 ? min(max(positionSeconds / durationSeconds, 0), 1) : 0
    }

    var isInProgress: Bool { progress > 0.01 && progress < 0.95 }
    var contentKind: CatalogKind { CatalogKind(rawValue: kind) ?? .other }
}
