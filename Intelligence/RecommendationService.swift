import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// RecommendationService.swift  (Rext Roadmap Phase 2 — Priority 3)
//
// Orchestrates a full recommendation pass for the UI:
//
//   1. Build a TasteProfile from local signals (library / history / events).
//   2. Source candidates cross-provider by searching the user's top genres via
//      RuntimeEngine.searchAll (results are already metadata-normalized).
//   3. Drop anything the user has already saved or watched.
//   4. Rank + explain via the deterministic engine.
//
// Candidate sourcing is intentionally separate from ranking: the pure engine is
// unit-tested in isolation, while this MainActor service handles I/O and dedup.
// A future Cloud/AI layer can swap the candidate source or the `recommender`
// without changing callers.
// ---------------------------------------------------------------------------

@MainActor
struct RecommendationService {
    let context: ModelContext
    var recommender: RecommendationRanking = DeterministicRecommender()
    var engine: RuntimeEngine = .shared
    /// How many top genres to search for candidates.
    var genreQueryLimit = 3
    /// The profile whose taste + owned items drive this pass (Phase 6).
    /// nil = the active profile (resolved lazily so this stays off the property initializer).
    var profileID: String?
    /// Parental-controls gate; nil = the active profile's policy.
    var policy: ContentPolicy?

    private var resolvedProfileID: String { profileID ?? ProfileManager.shared.currentProfileID }
    private var resolvedPolicy: ContentPolicy { policy ?? ProfileManager.shared.contentPolicy }

    func recommendations(limit: Int = 12) async -> [Recommendation] {
        let profileID = resolvedProfileID
        let policy = resolvedPolicy
        let profile = TasteProfileBuilder(context: context, profileID: profileID).build()
        guard !profile.isEmpty else { return [] }

        let queries = Array(profile.topGenres.prefix(genreQueryLimit))
        guard !queries.isEmpty else { return [] }

        let seen = seenKeys()
        var candidates: [RecommendationCandidate] = []
        var collected = Set<String>()

        for query in queries {
            for result in await MediaCatalog.shared.searchAll(query: query) {
                for item in result.items {
                    let key = "\(result.extensionID)|\(item.id)"
                    // Skip already-owned items, de-dup across genre queries, and
                    // enforce the active profile's parental controls.
                    if seen.contains(key) || !collected.insert(key).inserted { continue }
                    guard policy.allows(item) else { continue }
                    candidates.append(RecommendationCandidate(extensionID: result.extensionID, item: item))
                }
            }
        }

        return recommender.rank(candidates, against: profile, limit: limit)
    }

    /// Keys (`extensionID|itemID`) the profile has already saved or has history
    /// for, so recommendations never suggest something they already have.
    private func seenKeys() -> Set<String> {
        let profileID = resolvedProfileID
        var keys = Set<String>()
        let library = (try? context.fetch(FetchDescriptor<LibraryItem>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        for item in library { keys.insert("\(item.extensionID)|\(item.itemID)") }
        let history = (try? context.fetch(FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.profileID == profileID }
        ))) ?? []
        for entry in history { keys.insert("\(entry.extensionID)|\(entry.itemID)") }
        return keys
    }
}
