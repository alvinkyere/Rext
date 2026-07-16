import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// TrendingEngine.swift  (Rext Roadmap Phase 5 — Intelligence: trending)
//
// Deterministic "what's hot right now" derived from the Activity Graph (Phase 4).
// Each interaction with a piece of content contributes a weighted, time-decayed
// score; content is ranked by the sum. No global/server popularity is involved —
// this is the local user's own recent momentum, which is exactly the signal a
// single-user local platform can compute honestly before a Cloud layer exists.
// ---------------------------------------------------------------------------

/// A Sendable projection of one activity row — the neutral input the pure scorer
/// consumes, decoupled from the SwiftData @Model.
public nonisolated struct ActivitySnapshot: Sendable, Equatable {
    public let action: ActivityAction
    public let extensionID: String
    public let itemID: String
    public let title: String
    public let kind: CatalogKind
    public let timestamp: Date

    public init(action: ActivityAction, extensionID: String, itemID: String, title: String, kind: CatalogKind, timestamp: Date) {
        self.action = action
        self.extensionID = extensionID
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.timestamp = timestamp
    }

    public var contentID: ContentID { .provider(extensionID: extensionID, itemID: itemID) }
}

public nonisolated struct TrendingItem: Sendable, Identifiable, Equatable {
    public let contentID: ContentID
    public let extensionID: String
    public let itemID: String
    public let title: String
    public let kind: CatalogKind
    public let score: Double

    public var id: String { contentID.rawValue }
}

public nonisolated struct TrendingScorer: Sendable {
    /// Half-life of a signal, in days: a signal is worth half as much after this.
    public var halfLifeDays: Double
    public init(halfLifeDays: Double = 7) { self.halfLifeDays = halfLifeDays }

    /// How much each action contributes before time decay. Consumption signals
    /// (completing, favoriting) outweigh passive ones (viewing).
    private func weight(for action: ActivityAction) -> Double {
        switch action {
        case .playbackCompleted: return 3.0
        case .favorite: return 3.0
        case .save: return 2.0
        case .playbackStarted, .playbackResumed: return 1.5
        case .view: return 1.0
        case .subscribe, .follow: return 1.0
        default: return 0.0   // pauses, abandons, un-saves, searches: no trend lift
        }
    }

    /// Rank content by summed, time-decayed activity. `now` is injected for
    /// deterministic testing.
    public func rank(_ snapshots: [ActivitySnapshot], now: Date, limit: Int) -> [TrendingItem] {
        guard limit > 0 else { return [] }

        var scores: [String: Double] = [:]
        // Most recent descriptor per content, for display fields.
        var latest: [String: ActivitySnapshot] = [:]

        for snapshot in snapshots {
            let w = weight(for: snapshot.action)
            guard w > 0 else { continue }
            let ageDays = max(now.timeIntervalSince(snapshot.timestamp) / 86_400, 0)
            let decay = pow(0.5, ageDays / halfLifeDays)
            let key = snapshot.contentID.rawValue
            scores[key, default: 0] += w * decay
            if let existing = latest[key], existing.timestamp >= snapshot.timestamp {
                // keep the newer one
            } else {
                latest[key] = snapshot
            }
        }

        return scores
            .compactMap { key, score -> TrendingItem? in
                guard let s = latest[key] else { return nil }
                return TrendingItem(
                    contentID: s.contentID, extensionID: s.extensionID, itemID: s.itemID,
                    title: s.title, kind: s.kind, score: score
                )
            }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.id < rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }
}

// ---------------------------------------------------------------------------
// Builder — reads the Activity Graph and runs the pure scorer.
// ---------------------------------------------------------------------------

@MainActor
struct TrendingEngine {
    let context: ModelContext
    var scorer = TrendingScorer()
    /// Trending is computed from the active profile's own activity (Phase 6).
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?

    func trending(limit: Int = 12, now: Date = .now) -> [TrendingItem] {
        let resolvedProfileID = profileID ?? ProfileManager.shared.currentProfileID
        let events = ActivityLog(context: context, profileID: resolvedProfileID).recent()
        let snapshots: [ActivitySnapshot] = events.compactMap { event in
            guard let extensionID = event.extensionID, let itemID = event.itemID else { return nil }
            return ActivitySnapshot(
                action: event.action,
                extensionID: extensionID,
                itemID: itemID,
                title: event.title ?? "",
                kind: event.kind ?? .other,
                timestamp: event.timestamp
            )
        }
        return scorer.rank(snapshots, now: now, limit: limit)
    }
}
