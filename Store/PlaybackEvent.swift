import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// PlaybackEvent.swift  (Rext Roadmap Phase 1 — Playback Event Engine)
//
// A universal, provider-agnostic record of how the user interacts with playback.
// AVPlayer state changes are translated into these events, persisted via
// SwiftData, and later consumed by the Intelligence Layer (recommendations,
// smart collections). The engine is deliberately decoupled from any specific
// provider: an event only references the neutral extension/item identity.
//
//   AVPlayer → PlaybackObserver → PlaybackEventRecording → SwiftData → Intelligence
// ---------------------------------------------------------------------------

public enum PlaybackEventType: String, Codable, Sendable, CaseIterable {
    case started
    case paused
    case resumed
    case completed
    case abandoned
    case replayed
    case skipped
}

/// A Sendable description of a playback event, decoupled from SwiftData so it can
/// cross actor boundaries and be recorded by any `PlaybackEventRecording` sink.
public struct PlaybackEventInput: Sendable {
    public let type: PlaybackEventType
    public let extensionID: String
    public let itemID: String
    public let title: String
    public let kind: String
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let timestamp: Date

    public init(
        type: PlaybackEventType,
        extensionID: String,
        itemID: String,
        title: String,
        kind: String,
        positionSeconds: Double,
        durationSeconds: Double,
        timestamp: Date = .now
    ) {
        self.type = type
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
    }
}

@Model
final class PlaybackEvent {
    var id: UUID
    var typeRaw: String
    var extensionID: String
    var itemID: String
    var title: String
    var kind: String
    var positionSeconds: Double
    var durationSeconds: Double
    var timestamp: Date

    init(
        id: UUID = UUID(),
        type: PlaybackEventType,
        extensionID: String,
        itemID: String,
        title: String,
        kind: String,
        positionSeconds: Double,
        durationSeconds: Double,
        timestamp: Date = .now
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
    }

    convenience init(input: PlaybackEventInput) {
        self.init(
            type: input.type,
            extensionID: input.extensionID,
            itemID: input.itemID,
            title: input.title,
            kind: input.kind,
            positionSeconds: input.positionSeconds,
            durationSeconds: input.durationSeconds,
            timestamp: input.timestamp
        )
    }

    var type: PlaybackEventType { PlaybackEventType(rawValue: typeRaw) ?? .started }
    var contentKind: CatalogKind { CatalogKind(rawValue: kind) ?? .other }
    var progress: Double { durationSeconds > 0 ? min(max(positionSeconds / durationSeconds, 0), 1) : 0 }
}
