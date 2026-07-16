import Foundation
import SwiftData
import Observation

// ---------------------------------------------------------------------------
// SyncEngine.swift  (Rext Roadmap Phase 7 — Cloud Platform)
//
// Orchestrates a sync pass and exposes observable status for the UI. A pass is
// push-then-pull-then-merge: upload this device's snapshot, fetch the
// authoritative remote, and merge it back locally (last-write-wins). The backend
// is injected, so the same engine works against the local-file backend today and
// a web-service backend later. All data stays local until a real backend exists.
// ---------------------------------------------------------------------------

@MainActor
@Observable
final class SyncEngine {
    private let backend: SyncBackend
    private let context: ModelContext

    private(set) var status: SyncStatus = .idle
    private(set) var lastSyncedAt: Date?

    private static let lastSyncedKey = "rext.lastSyncedAt"

    var backendName: String { backend.displayName }
    var isSyncing: Bool { if case .syncing = status { return true } else { return false } }

    init(context: ModelContext, backend: SyncBackend = LocalFileSyncBackend()) {
        self.context = context
        self.backend = backend
        self.lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// Run a full sync pass: export → push → pull → merge.
    func syncNow() async {
        guard !isSyncing else { return }
        status = .syncing
        let service = SyncService(context: context)
        do {
            try await backend.push(service.export())
            if let remote = try await backend.pull() {
                service.apply(remote)
            }
            let now = Date()
            lastSyncedAt = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncedKey)
            status = .succeeded(now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
