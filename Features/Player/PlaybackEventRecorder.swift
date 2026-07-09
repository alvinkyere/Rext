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

    init(context: ModelContext) {
        self.context = context
    }

    func record(_ input: PlaybackEventInput) {
        context.insert(PlaybackEvent(input: input))
    }
}

/// Read-side queries over recorded events — the foundation the Recommendation
/// Engine and Smart Collections (Phase 2) will consume.
@MainActor
struct PlaybackEventStore {
    let context: ModelContext

    func allEvents() -> [PlaybackEvent] {
        (try? context.fetch(FetchDescriptor<PlaybackEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        ))) ?? []
    }

    func events(itemID: String) -> [PlaybackEvent] {
        (try? context.fetch(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.itemID == itemID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        ))) ?? []
    }

    func count(of type: PlaybackEventType) -> Int {
        let raw = type.rawValue
        return (try? context.fetchCount(FetchDescriptor<PlaybackEvent>(
            predicate: #Predicate { $0.typeRaw == raw }
        ))) ?? 0
    }

    /// Completion rate across items the user has started (0...1).
    func completionRate() -> Double {
        let started = count(of: .started)
        guard started > 0 else { return 0 }
        return Double(count(of: .completed)) / Double(started)
    }
}
