import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// PlaybackEventRecorder.swift  (Rext Roadmap Phase 1 — Playback Event Engine)
//
// The sink that receives playback events and the read API the Intelligence Layer
// will build on. `PlaybackEventRecording` is a protocol so the recorder can be
// swapped (e.g. to also forward to a cloud sync engine or an in-process
// analytics pipeline) without touching the player.
// ---------------------------------------------------------------------------

@MainActor
protocol PlaybackEventRecording {
    func record(_ input: PlaybackEventInput)
}

/// Persists playback events into SwiftData.
@MainActor
final class SwiftDataPlaybackEventRecorder: PlaybackEventRecording {
    private let context: ModelContext
    /// nil = stamp the active profile at record time.
    private let profileID: String?

    init(context: ModelContext, profileID: String? = nil) {
        self.context = context
        self.profileID = profileID
    }

    func record(_ input: PlaybackEventInput) {
        let profileID = self.profileID ?? ProfileManager.shared.currentProfileID
        context.insert(PlaybackEvent(input: input, profileID: profileID))
    }
}

/// Read-side queries over recorded events, scoped to one profile (Phase 6) — the
/// foundation the Recommendation Engine and Smart Collections consume.
@MainActor
struct PlaybackEventStore {
    let context: ModelContext
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?
    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }

    func allEvents() -> [PlaybackEvent] {
        let profileID = resolvedProfileID
        return (try? context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        ))) ?? []
    }

    func events(itemID: String) -> [PlaybackEvent] {
        let profileID = resolvedProfileID
        return (try? context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.itemID == itemID && $0.profileID == profileID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        ))) ?? []
    }

    func count(of type: PlaybackEventType) -> Int {
        let raw = type.rawValue
        let profileID = resolvedProfileID
        return (try? context.fetchCount(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.typeRaw == raw && $0.profileID == profileID }
        ))) ?? 0
    }

    /// Completion rate across items the user has started (0...1).
    func completionRate() -> Double {
        let started = count(of: .started)
        guard started > 0 else { return 0 }
        return Double(count(of: .completed)) / Double(started)
    }
}
