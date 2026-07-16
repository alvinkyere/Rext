import Foundation
import SwiftData

// ---------------------------------------------------------------------------
// SyncService.swift  (Rext Roadmap Phase 7 — Cloud Platform)
//
// Bridges the local SwiftData store to the transport-agnostic `SyncSnapshot`.
// `export` gathers all device state into a snapshot; `apply` merges a snapshot
// back in with deterministic, last-write-wins conflict resolution:
//   • profiles / repositories — upsert by stable id/url, newest wins
//   • library — upsert by key
//   • history — upsert by key, keep the more-recently-accessed row
//   • activity — append-only, de-duplicated by event id
//   • preferences — last-write-wins into UserDefaults
// The shared Content Graph is device-local (a cache) and intentionally not synced.
// ---------------------------------------------------------------------------

@MainActor
struct SyncService {
    let context: ModelContext

    static let deviceIDKey = "rext.deviceID"
    static let qualityKey = "defaultVideoQuality"
    static let debugKey = "enableDebugLogging"

    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIDKey)
        return generated
    }

    // MARK: - Export

    func export() -> SyncSnapshot {
        SyncSnapshot(
            deviceID: Self.deviceID,
            profiles: fetch(UserProfile.self).map(profileDTO),
            library: fetch(LibraryItem.self).map(libraryDTO),
            history: fetch(HistoryEntry.self).map(historyDTO),
            activity: fetch(ActivityEvent.self).map(activityDTO),
            repositories: fetch(RepositorySource.self).map(repositoryDTO),
            preferences: preferencesDTO()
        )
    }

    // MARK: - Apply (merge)

    func apply(_ snapshot: SyncSnapshot) {
        snapshot.profiles.forEach(mergeProfile)
        snapshot.repositories.forEach(mergeRepository)
        snapshot.library.forEach(mergeLibraryItem)
        snapshot.history.forEach(mergeHistoryEntry)
        snapshot.activity.forEach(mergeActivityEvent)
        applyPreferences(snapshot.preferences)
        try? context.save()
    }

    // MARK: - Fetch helper

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: - Model → DTO

    private func profileDTO(_ p: UserProfile) -> ProfileDTO {
        ProfileDTO(id: p.id, name: p.name, kindRaw: p.kindRaw, avatarSymbol: p.avatarSymbol,
                   colorHex: p.colorHex, createdAt: p.createdAt,
                   preferences: p.preferences, parentalControls: p.parentalControls)
    }

    private func libraryDTO(_ i: LibraryItem) -> LibraryItemDTO {
        LibraryItemDTO(extensionID: i.extensionID, itemID: i.itemID, title: i.title, subtitle: i.subtitle,
                       artworkURL: i.artworkURL, kind: i.kind, collectionRaw: i.collectionRaw,
                       genres: i.genres, addedAt: i.addedAt, profileID: i.profileID)
    }

    private func historyDTO(_ h: HistoryEntry) -> HistoryEntryDTO {
        HistoryEntryDTO(extensionID: h.extensionID, itemID: h.itemID, title: h.title, kind: h.kind,
                        artworkURL: h.artworkURL, lastAccessed: h.lastAccessed,
                        positionSeconds: h.positionSeconds, durationSeconds: h.durationSeconds, profileID: h.profileID)
    }

    private func activityDTO(_ e: ActivityEvent) -> ActivityEventDTO {
        ActivityEventDTO(id: e.id, actionRaw: e.actionRaw, extensionID: e.extensionID, itemID: e.itemID,
                         contentID: e.contentID, title: e.title, kindRaw: e.kindRaw, query: e.query,
                         positionSeconds: e.positionSeconds, durationSeconds: e.durationSeconds,
                         timestamp: e.timestamp, sessionID: e.sessionID, devicePlatform: e.devicePlatform,
                         deviceSystemVersion: e.deviceSystemVersion, appVersion: e.appVersion, profileID: e.profileID)
    }

    private func repositoryDTO(_ r: RepositorySource) -> RepositoryDTO {
        RepositoryDTO(url: r.url, title: r.title, addedAt: r.addedAt, isEnabled: r.isEnabled)
    }

    private func preferencesDTO() -> PreferencesDTO {
        PreferencesDTO(
            defaultVideoQuality: UserDefaults.standard.string(forKey: Self.qualityKey) ?? "1080p",
            enableDebugLogging: UserDefaults.standard.bool(forKey: Self.debugKey)
        )
    }

    // MARK: - Merge (DTO → model, last-write-wins)

    private func mergeProfile(_ dto: ProfileDTO) {
        let id = dto.id
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == id })))?.first {
            existing.name = dto.name
            existing.kindRaw = dto.kindRaw
            existing.avatarSymbol = dto.avatarSymbol
            existing.colorHex = dto.colorHex
            existing.preferences = dto.preferences
            existing.parentalControls = dto.parentalControls
        } else {
            context.insert(UserProfile(
                id: dto.id, name: dto.name, kind: UserProfileKind(rawValue: dto.kindRaw) ?? .adult,
                avatarSymbol: dto.avatarSymbol, colorHex: dto.colorHex,
                preferences: dto.preferences, parentalControls: dto.parentalControls, createdAt: dto.createdAt
            ))
        }
    }

    private func mergeRepository(_ dto: RepositoryDTO) {
        let url = dto.url
        if let existing = (try? context.fetch(FetchDescriptor<RepositorySource>(predicate: #Predicate { $0.url == url })))?.first {
            existing.title = dto.title
            existing.isEnabled = dto.isEnabled
        } else {
            context.insert(RepositorySource(url: dto.url, title: dto.title, addedAt: dto.addedAt, isEnabled: dto.isEnabled))
        }
    }

    private func mergeLibraryItem(_ dto: LibraryItemDTO) {
        let key = "\(dto.profileID)|\(dto.extensionID)|\(dto.itemID)|\(dto.collectionRaw)"
        let exists = (try? context.fetchCount(FetchDescriptor<LibraryItem>(predicate: #Predicate { $0.key == key }))) ?? 0
        guard exists == 0 else { return }
        context.insert(LibraryItem(
            extensionID: dto.extensionID, itemID: dto.itemID, title: dto.title, subtitle: dto.subtitle,
            artworkURL: dto.artworkURL, kind: dto.kind,
            collection: LibraryCollection(rawValue: dto.collectionRaw) ?? .favorites,
            genres: dto.genres, profileID: dto.profileID, addedAt: dto.addedAt
        ))
    }

    private func mergeHistoryEntry(_ dto: HistoryEntryDTO) {
        let key = "\(dto.profileID)|\(dto.extensionID)|\(dto.itemID)"
        if let existing = (try? context.fetch(FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.key == key })))?.first {
            // Keep whichever device watched it more recently.
            guard dto.lastAccessed > existing.lastAccessed else { return }
            existing.positionSeconds = dto.positionSeconds
            existing.durationSeconds = dto.durationSeconds
            existing.lastAccessed = dto.lastAccessed
        } else {
            context.insert(HistoryEntry(
                extensionID: dto.extensionID, itemID: dto.itemID, title: dto.title, kind: dto.kind,
                artworkURL: dto.artworkURL, profileID: dto.profileID, lastAccessed: dto.lastAccessed,
                positionSeconds: dto.positionSeconds, durationSeconds: dto.durationSeconds
            ))
        }
    }

    private func mergeActivityEvent(_ dto: ActivityEventDTO) {
        let id = dto.id
        let exists = (try? context.fetchCount(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.id == id }))) ?? 0
        guard exists == 0 else { return }
        context.insert(ActivityEvent(
            id: dto.id, actionRaw: dto.actionRaw, extensionID: dto.extensionID, itemID: dto.itemID,
            contentID: dto.contentID, title: dto.title, kindRaw: dto.kindRaw, query: dto.query,
            positionSeconds: dto.positionSeconds, durationSeconds: dto.durationSeconds, timestamp: dto.timestamp,
            sessionID: dto.sessionID, devicePlatform: dto.devicePlatform, deviceSystemVersion: dto.deviceSystemVersion,
            appVersion: dto.appVersion, profileID: dto.profileID
        ))
    }

    private func applyPreferences(_ dto: PreferencesDTO) {
        UserDefaults.standard.set(dto.defaultVideoQuality, forKey: Self.qualityKey)
        UserDefaults.standard.set(dto.enableDebugLogging, forKey: Self.debugKey)
    }
}
