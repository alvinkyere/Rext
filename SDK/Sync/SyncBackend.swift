import Foundation

// ---------------------------------------------------------------------------
// SyncBackend.swift  (Rext Roadmap Phase 7 — Cloud Platform)
//
// The transport abstraction. The rest of the app only knows `SyncBackend`, so
// the local-file backend used today can be swapped for an HTTP/web-service
// backend later without touching the engine or UI. `push` uploads this device's
// snapshot; `pull` returns the authoritative remote snapshot to merge locally.
// ---------------------------------------------------------------------------

public protocol SyncBackend: Sendable {
    /// A short human-readable name for the active backend (shown in Settings).
    var displayName: String { get }

    /// Upload the device snapshot to the remote store.
    func push(_ snapshot: SyncSnapshot) async throws

    /// Fetch the latest remote snapshot, or nil if nothing has been synced yet.
    func pull() async throws -> SyncSnapshot?
}

/// A backend that persists the snapshot to a JSON file on disk, simulating a
/// cloud store end-to-end so sync is demonstrable and testable fully offline.
public struct LocalFileSyncBackend: SyncBackend {
    public let displayName = "On This Device (Local)"
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rext-sync-snapshot.json")
    }

    public func push(_ snapshot: SyncSnapshot) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func pull() async throws -> SyncSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncSnapshot.self, from: data)
    }
}

/// An in-memory backend for tests and previews.
public actor InMemorySyncBackend: SyncBackend {
    public nonisolated let displayName = "In Memory"
    private var stored: SyncSnapshot?

    public init(seed: SyncSnapshot? = nil) { self.stored = seed }

    public func push(_ snapshot: SyncSnapshot) async throws { stored = snapshot }
    public func pull() async throws -> SyncSnapshot? { stored }
}
