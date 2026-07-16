import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// TasteProfile.swift  (Rext Roadmap Phase 2 — Priority 3: Recommendation Engine v1)
//
// The Intelligence Layer's deterministic model of what a user likes, derived
// entirely from local signals already captured by earlier phases:
//
//   Library (favorites / collections) ─┐
//   History (resume + completion)      ├─► TasteProfileBuilder ─► TasteProfile
//   PlaybackEvents (completed / kind)  ─┘
//
// The profile is a plain value type with no provider- or storage-specific
// knowledge, so the ranking engine (and, later, the Cloud + AI layers) can all
// consume the same neutral representation. No machine learning is involved: the
// weights are transparent, explainable sums the user could reason about.
// ---------------------------------------------------------------------------

public nonisolated struct TasteProfile: Sendable, Equatable {
    /// Canonical genre → affinity weight (higher means a stronger preference).
    public var genreScores: [String: Double]
    /// `CatalogKind` raw value → affinity weight (do they prefer movies? podcasts?).
    public var kindScores: [String: Double]
    /// Creator / studio / author → affinity weight.
    public var creatorScores: [String: Double]
    /// A representative title the user engaged with, per genre — powers the
    /// "Recommended because you watched …" explanation.
    public var genreExemplars: [String: String]
    /// Fraction of started items the user finished (0...1).
    public var completionRate: Double
    /// Number of distinct engagement signals that fed the profile.
    public var signalCount: Int

    public init(
        genreScores: [String: Double] = [:],
        kindScores: [String: Double] = [:],
        creatorScores: [String: Double] = [:],
        genreExemplars: [String: String] = [:],
        completionRate: Double = 0,
        signalCount: Int = 0
    ) {
        self.genreScores = genreScores
        self.kindScores = kindScores
        self.creatorScores = creatorScores
        self.genreExemplars = genreExemplars
        self.completionRate = completionRate
        self.signalCount = signalCount
    }

    /// A profile with no signals yields no recommendations (the engine stays quiet
    /// rather than guessing for a brand-new user).
    public var isEmpty: Bool { signalCount == 0 || genreScores.isEmpty }

    /// Genres ordered by descending affinity, ties broken alphabetically so the
    /// ordering is fully deterministic.
    public var topGenres: [String] {
        genreScores
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }
}

// ---------------------------------------------------------------------------
// Builder — the only piece that touches SwiftData. Kept on the MainActor because
// it reads the app's ModelContext; it emits an actor-agnostic value type.
// ---------------------------------------------------------------------------

@MainActor
struct TasteProfileBuilder {
    let context: ModelContext
    /// Only signals belonging to this profile feed the taste model (Phase 6).
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?
    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }

    /// Relative importance of each signal. Explicit favorites count most; a
    /// completed item counts more than one merely saved; passive history least.
    private enum Weight {
        static let favorite = 3.0
        static let completed = 2.5
        static let saved = 1.0
        static let history = 1.5
    }

    func build() -> TasteProfile {
        var profile = TasteProfile()
        applyLibrary(to: &profile)
        applyHistory(to: &profile)
        applyPlaybackEvents(to: &profile)
        return profile
    }

    // MARK: - Signal sources

    private func applyLibrary(to profile: inout TasteProfile) {
        let profileID = resolvedProfileID
        let items = (try? context.fetch(FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        // Process the strongest signals first so per-genre exemplars are drawn
        // from the items the user values most (favorites before plain saves).
        for item in items.sorted(by: { weight(for: $0.collection) > weight(for: $1.collection) }) {
            let w = weight(for: item.collection)
            add(genres: item.genres, weight: w, exemplar: item.title, to: &profile)
            profile.kindScores[item.kind, default: 0] += w
            profile.signalCount += 1
        }
    }

    private func weight(for collection: LibraryCollection) -> Double {
        switch collection {
        case .favorites: return Weight.favorite
        case .completed: return Weight.completed
        default: return Weight.saved
        }
    }

    private func applyHistory(to profile: inout TasteProfile) {
        let profileID = resolvedProfileID
        let entries = (try? context.fetch(FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        for entry in entries {
            // History rows carry no genres (they predate the metadata layer for
            // resume), but they still express a kind preference and count as a
            // signal — scaled by how far the user actually got.
            let weight = Weight.history * max(entry.progress, 0.1)
            profile.kindScores[entry.kind, default: 0] += weight
            profile.signalCount += 1
        }
    }

    private func applyPlaybackEvents(to profile: inout TasteProfile) {
        let store = PlaybackEventStore(context: context, profileID: resolvedProfileID)
        profile.completionRate = store.completionRate()
    }

    // MARK: - Helpers

    private func add(genres: [String], weight: Double, exemplar: String, to profile: inout TasteProfile) {
        for genre in genres {
            profile.genreScores[genre, default: 0] += weight
            // Keep the exemplar from the strongest-weighted contribution so the
            // "because you watched X" reason points at something the user values.
            if profile.genreExemplars[genre] == nil {
                profile.genreExemplars[genre] = exemplar
            }
        }
    }
}
