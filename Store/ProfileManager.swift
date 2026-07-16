import Foundation
import SwiftData
import Observation

// ---------------------------------------------------------------------------
// ProfileManager.swift  (Rext Roadmap Phase 6 — User Platform)
//
// The single source of truth for user identity: the list of local profiles, the
// active one, and switching / guest mode. `currentProfileID` is mirrored to
// UserDefaults so the write path (LibraryActions, recorders) can stamp the active
// profile synchronously without threading it through every call site, and so the
// active profile survives launches.
//
// One shared instance is injected into the SwiftUI environment *and* used by the
// write path, so both always agree.
// ---------------------------------------------------------------------------

@MainActor
@Observable
final class ProfileManager {
    static let shared = ProfileManager()

    private(set) var profiles: [UserProfile] = []
    private(set) var currentProfileID: String
    /// The profile active before entering guest mode, to restore on exit.
    private(set) var profileBeforeGuest: String?

    private var context: ModelContext?
    /// When false, the active profile lives only in memory (used by tests so a
    /// switch never leaks through the global UserDefaults key into other tests).
    private let persists: Bool
    private static let currentKey = "rext.currentProfileID"

    init(persists: Bool = true) {
        self.persists = persists
        currentProfileID = persists
            ? (UserDefaults.standard.string(forKey: Self.currentKey) ?? UserProfile.defaultProfileID)
            : UserProfile.defaultProfileID
    }

    /// The active profile, or nil before `bootstrap`.
    var current: UserProfile? { profiles.first { $0.id == currentProfileID } }

    /// The parental-controls gate for the active profile.
    var contentPolicy: ContentPolicy {
        guard let controls = current?.parentalControls else { return .unrestricted }
        return ContentPolicy(controls: controls)
    }

    var isGuestActive: Bool { current?.isGuest ?? false }

    // MARK: - Lifecycle

    /// Attach a context, seed the default profile on first launch, and validate
    /// the persisted active id. Call once at app start.
    func bootstrap(context: ModelContext) {
        self.context = context
        reload()
        if profiles.isEmpty {
            context.insert(UserProfile(
                id: UserProfile.defaultProfileID, name: "Me", kind: .adult,
                avatarSymbol: "person.crop.circle.fill", colorHex: "#3B82F6"
            ))
            try? context.save()
            reload()
        }
        if !profiles.contains(where: { $0.id == currentProfileID }) {
            setCurrent(profiles.first?.id ?? UserProfile.defaultProfileID)
        }
    }

    func reload() {
        guard let context else { return }
        profiles = (try? context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    // MARK: - CRUD

    @discardableResult
    func create(
        name: String,
        kind: UserProfileKind = .adult,
        avatarSymbol: String = "person.crop.circle.fill",
        colorHex: String = "#3B82F6",
        parentalControls: ParentalControls = ParentalControls()
    ) -> UserProfile {
        let profile = UserProfile(
            name: name, kind: kind, avatarSymbol: avatarSymbol,
            colorHex: colorHex, parentalControls: parentalControls
        )
        context?.insert(profile)
        try? context?.save()
        reload()
        return profile
    }

    /// Persist edits made to a profile's fields/preferences/controls.
    func save() {
        try? context?.save()
        reload()
    }

    /// Delete a profile and all of its scoped data. The default profile is
    /// protected so there is always at least one profile.
    func delete(_ profile: UserProfile) {
        guard profile.id != UserProfile.defaultProfileID else { return }
        deleteScopedData(profileID: profile.id)
        context?.delete(profile)
        try? context?.save()
        reload()
        if currentProfileID == profile.id {
            setCurrent(profiles.first?.id ?? UserProfile.defaultProfileID)
        }
    }

    // MARK: - Switching & guest mode

    func switchTo(_ profile: UserProfile) { setCurrent(profile.id) }

    /// Enter a fresh guest session: (re)create an empty guest profile, wiping any
    /// prior guest data, and switch to it. Guest data never mixes with a real
    /// profile's history or library.
    func enterGuestMode() {
        profileBeforeGuest = isGuestActive ? profileBeforeGuest : currentProfileID
        deleteScopedData(profileID: UserProfile.guestProfileID)
        if !profiles.contains(where: { $0.id == UserProfile.guestProfileID }) {
            context?.insert(UserProfile(
                id: UserProfile.guestProfileID, name: "Guest", kind: .guest,
                avatarSymbol: "person.crop.circle.badge.questionmark", colorHex: "#8E8E93"
            ))
            try? context?.save()
            reload()
        }
        setCurrent(UserProfile.guestProfileID)
    }

    /// Leave guest mode: wipe guest data and return to the previous profile.
    func exitGuestMode() {
        deleteScopedData(profileID: UserProfile.guestProfileID)
        setCurrent(profileBeforeGuest ?? UserProfile.defaultProfileID)
        profileBeforeGuest = nil
    }

    // MARK: - Internals

    private func setCurrent(_ id: String) {
        currentProfileID = id
        if persists { UserDefaults.standard.set(id, forKey: Self.currentKey) }
    }

    /// Remove every per-profile row (library, history, playback, activity) for the
    /// given profile. The shared Content Graph is left intact.
    private func deleteScopedData(profileID: String) {
        guard let context else { return }
        try? context.delete(model: LibraryItem.self, where: #Predicate { $0.profileID == profileID })
        try? context.delete(model: HistoryEntry.self, where: #Predicate { $0.profileID == profileID })
        try? context.delete(model: PlaybackEvent.self, where: #Predicate { $0.profileID == profileID })
        try? context.delete(model: ActivityEvent.self, where: #Predicate { $0.profileID == profileID })
        try? context.save()
    }
}
