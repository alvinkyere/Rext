import Foundation

// ---------------------------------------------------------------------------
// SyncModels.swift  (Rext Roadmap Phase 7 — Cloud Platform)
//
// Provider-agnostic, Codable DTOs that describe the device's syncable state:
// profiles, library, history, the activity timeline, repositories (installed
// providers), and app preferences. A `SyncSnapshot` is the whole payload a
// backend pushes/pulls. Nothing here is transport-specific — the same snapshot
// serializes to a local file today and to a web API later.
// ---------------------------------------------------------------------------

public struct ProfileDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var kindRaw: String
    public var avatarSymbol: String
    public var colorHex: String
    public var createdAt: Date
    public var preferences: ProfilePreferences
    public var parentalControls: ParentalControls
}

public struct LibraryItemDTO: Codable, Sendable, Equatable {
    public var extensionID: String
    public var itemID: String
    public var title: String
    public var subtitle: String?
    public var artworkURL: String?
    public var kind: String
    public var collectionRaw: String
    public var genres: [String]
    public var addedAt: Date
    public var profileID: String
}

public struct HistoryEntryDTO: Codable, Sendable, Equatable {
    public var extensionID: String
    public var itemID: String
    public var title: String
    public var kind: String
    public var artworkURL: String?
    public var lastAccessed: Date
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var profileID: String
}

public struct ActivityEventDTO: Codable, Sendable, Equatable {
    public var id: UUID
    public var actionRaw: String
    public var extensionID: String?
    public var itemID: String?
    public var contentID: String?
    public var title: String?
    public var kindRaw: String?
    public var query: String?
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var timestamp: Date
    public var sessionID: String
    public var devicePlatform: String
    public var deviceSystemVersion: String
    public var appVersion: String
    public var profileID: String
}

public struct RepositoryDTO: Codable, Sendable, Equatable {
    public var url: String
    public var title: String?
    public var addedAt: Date
    public var isEnabled: Bool
}

public struct PreferencesDTO: Codable, Sendable, Equatable {
    public var defaultVideoQuality: String
    public var enableDebugLogging: Bool
}

/// The full syncable payload for one device at a point in time.
public struct SyncSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generatedAt: Date

    public var profiles: [ProfileDTO]
    public var library: [LibraryItemDTO]
    public var history: [HistoryEntryDTO]
    public var activity: [ActivityEventDTO]
    public var repositories: [RepositoryDTO]
    public var preferences: PreferencesDTO

    public init(
        schemaVersion: Int = SyncSnapshot.currentSchemaVersion,
        deviceID: String,
        generatedAt: Date = .now,
        profiles: [ProfileDTO] = [],
        library: [LibraryItemDTO] = [],
        history: [HistoryEntryDTO] = [],
        activity: [ActivityEventDTO] = [],
        repositories: [RepositoryDTO] = [],
        preferences: PreferencesDTO
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generatedAt = generatedAt
        self.profiles = profiles
        self.library = library
        self.history = history
        self.activity = activity
        self.repositories = repositories
        self.preferences = preferences
    }
}

/// Where the sync engine is in its lifecycle — drives the Settings UI.
public enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    case succeeded(Date)
    case failed(String)
}
