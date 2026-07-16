import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// ActivityEvent.swift  (Rext Roadmap Phase 4 — Activity Graph)
//
// A universal, provider-agnostic timeline of everything the user does: searches,
// views, playback, saves, favorites, and (architected for the future)
// subscriptions and follows. It replaces "simple history" as the record of
// interaction — `HistoryEntry` remains only the resume-position store powering
// Continue Watching, while this timeline powers the Intelligence Layer.
//
// Every event carries provider context (`extensionID`), a reference into the
// Universal Content Graph (`contentID`, Phase 3), a session id, device info, and
// a timestamp. Playback events are also recorded here (as the coarse timeline)
// while the fine-grained `PlaybackEvent` engine keeps its detailed analytics.
// ---------------------------------------------------------------------------

public enum ActivityAction: String, Codable, Sendable, CaseIterable {
    case search
    case view                 // opened content details
    case playbackStarted
    case playbackPaused
    case playbackResumed
    case playbackCompleted
    case playbackAbandoned
    case save
    case unsave
    case favorite
    case unfavorite
    case subscribe            // provider / channel subscription (future providers)
    case unsubscribe
    case follow               // creator follow (future providers)
    case unfollow
}

/// A Sendable description of an activity, decoupled from SwiftData so it can cross
/// actor boundaries and be recorded by any `ActivityRecording` sink.
public struct ActivityEventInput: Sendable {
    public let action: ActivityAction
    public let extensionID: String?
    public let itemID: String?
    public let title: String?
    public let kind: CatalogKind?
    public let query: String?
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let timestamp: Date

    public init(
        action: ActivityAction,
        extensionID: String? = nil,
        itemID: String? = nil,
        title: String? = nil,
        kind: CatalogKind? = nil,
        query: String? = nil,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0,
        timestamp: Date = .now
    ) {
        self.action = action
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.query = query
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
    }

    /// The canonical content id this activity refers to, when it targets content.
    public var contentID: ContentID? {
        guard let extensionID, let itemID else { return nil }
        return .provider(extensionID: extensionID, itemID: itemID)
    }

    // MARK: - Convenience builders

    public static func search(_ query: String, timestamp: Date = .now) -> ActivityEventInput {
        ActivityEventInput(action: .search, query: query, timestamp: timestamp)
    }

    /// An activity that targets a specific content item.
    public static func content(
        _ action: ActivityAction,
        extensionID: String,
        item: CatalogItem,
        positionSeconds: Double = 0,
        durationSeconds: Double = 0,
        timestamp: Date = .now
    ) -> ActivityEventInput {
        ActivityEventInput(
            action: action,
            extensionID: extensionID,
            itemID: item.id,
            title: item.title,
            kind: item.kind,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
            timestamp: timestamp
        )
    }
}

@Model
final class ActivityEvent {
    var id: UUID
    var actionRaw: String
    var extensionID: String?
    var itemID: String?
    /// Reference into the Universal Content Graph (nil for non-content activity).
    var contentID: String?
    var title: String?
    var kindRaw: String?
    var query: String?
    var positionSeconds: Double
    var durationSeconds: Double
    var timestamp: Date

    // Session & device context.
    var sessionID: String
    var devicePlatform: String
    var deviceSystemVersion: String
    var appVersion: String
    /// Owning user profile (Phase 6).
    var profileID: String = UserProfile.defaultProfileID

    init(input: ActivityEventInput, session: ActivitySession, profileID: String = UserProfile.defaultProfileID) {
        self.id = UUID()
        self.profileID = profileID
        self.actionRaw = input.action.rawValue
        self.extensionID = input.extensionID
        self.itemID = input.itemID
        self.contentID = input.contentID?.rawValue
        self.title = input.title
        self.kindRaw = input.kind?.rawValue
        self.query = input.query
        self.positionSeconds = input.positionSeconds
        self.durationSeconds = input.durationSeconds
        self.timestamp = input.timestamp
        self.sessionID = session.id.uuidString
        self.devicePlatform = session.device.platform
        self.deviceSystemVersion = session.device.systemVersion
        self.appVersion = session.device.appVersion
    }

    /// Full initializer used to restore an event from a sync snapshot (Phase 7).
    init(
        id: UUID, actionRaw: String, extensionID: String?, itemID: String?, contentID: String?,
        title: String?, kindRaw: String?, query: String?, positionSeconds: Double, durationSeconds: Double,
        timestamp: Date, sessionID: String, devicePlatform: String, deviceSystemVersion: String,
        appVersion: String, profileID: String
    ) {
        self.id = id
        self.actionRaw = actionRaw
        self.extensionID = extensionID
        self.itemID = itemID
        self.contentID = contentID
        self.title = title
        self.kindRaw = kindRaw
        self.query = query
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.devicePlatform = devicePlatform
        self.deviceSystemVersion = deviceSystemVersion
        self.appVersion = appVersion
        self.profileID = profileID
    }

    var action: ActivityAction { ActivityAction(rawValue: actionRaw) ?? .view }
    var kind: CatalogKind? { kindRaw.flatMap(CatalogKind.init(rawValue:)) }
    var progress: Double { durationSeconds > 0 ? min(max(positionSeconds / durationSeconds, 0), 1) : 0 }
}

extension PlaybackEventType {
    /// The coarse activity-timeline action for a fine-grained playback event, or
    /// `nil` for seek-level noise (skipped / replayed) that stays in the playback
    /// engine only.
    var activityAction: ActivityAction? {
        switch self {
        case .started: return .playbackStarted
        case .paused: return .playbackPaused
        case .resumed: return .playbackResumed
        case .completed: return .playbackCompleted
        case .abandoned: return .playbackAbandoned
        case .replayed, .skipped: return nil
        }
    }
}
