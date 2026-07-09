import Foundation
import Observation

// ---------------------------------------------------------------------------
// ExtensionsController.swift  (Rext Phase 2 — Priority 1 & 2)
//
// The app-level façade the Extensions UI drives. It aggregates listings across
// every enabled repository, computes what's Available vs has Updates, and runs
// install/update/uninstall/reinstall through the engine while persisting packages
// on disk via InstalledPackageStore (so installs survive relaunch). Installs are
// gated behind a permission-review sheet built from the downloaded manifest.
// ---------------------------------------------------------------------------

/// A lightweight, value-type reference to a repository (decoupled from SwiftData).
struct RepoRef: Sendable, Hashable {
    let url: String
    let title: String?
}

@MainActor
@Observable
final class ExtensionsController {
    struct Entry: Identifiable {
        let listing: ExtensionListing
        let version: RepositoryVersion
        let repositoryName: String
        let isUpdate: Bool
        var id: String { listing.id }
    }

    struct PendingInstall: Identifiable {
        let id = UUID()
        let listing: ExtensionListing
        let version: RepositoryVersion
        let document: ExtensionPackageDocument
        let repositoryName: String
        let isUpdate: Bool
        var manifest: ExtensionManifest { document.manifest }
    }

    private let engine: RuntimeEngine
    private let repositoryService: RepositoryService
    private var lastRepositories: [RepoRef] = []

    var installed: [InstalledExtension] = []
    var available: [Entry] = []
    var updates: [Entry] = []
    var isBusy = false
    var errorMessage: String?
    var pendingInstall: PendingInstall?

    init(
        engine: RuntimeEngine = .shared,
        repositoryService: RepositoryService = RepositoryService(sessionConfiguration: SampleRepository.sessionConfiguration())
    ) {
        self.engine = engine
        self.repositoryService = repositoryService
    }

    func refresh(repositories: [RepoRef]) async {
        lastRepositories = repositories
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        installed = await engine.installedExtensions
        let installedIDs = Set(installed.map(\.id))
        let installedVersions = Dictionary(installed.map { ($0.id, $0.manifest.version) }) { first, _ in first }

        var availableEntries: [Entry] = []
        var updateEntries: [Entry] = []
        var seen = Set<String>()

        for repository in repositories {
            guard let url = URL(string: repository.url) else { continue }
            do {
                let index = try await repositoryService.fetchRepository(at: url)
                for listing in index.extensions {
                    guard let version = listing.latest, !seen.contains(listing.id) else { continue }
                    if installedIDs.contains(listing.id) {
                        if let current = installedVersions[listing.id], version.version > current {
                            updateEntries.append(Entry(listing: listing, version: version, repositoryName: index.metadata.name, isUpdate: true))
                            seen.insert(listing.id)
                        }
                    } else {
                        availableEntries.append(Entry(listing: listing, version: version, repositoryName: index.metadata.name, isUpdate: false))
                        seen.insert(listing.id)
                    }
                }
            } catch {
                errorMessage = describe(error)
            }
        }

        available = availableEntries.sorted { $0.listing.displayName < $1.listing.displayName }
        updates = updateEntries.sorted { $0.listing.displayName < $1.listing.displayName }
    }

    /// Download + verify a listing and present it for permission review.
    func requestInstall(_ entry: Entry) async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let document = try await repositoryService.fetchPackage(entry.version, from: entry.listing)
            pendingInstall = PendingInstall(
                listing: entry.listing,
                version: entry.version,
                document: document,
                repositoryName: entry.repositoryName,
                isUpdate: entry.isUpdate
            )
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Commit the reviewed install/update: persist to disk, then register.
    func confirmPending() async {
        guard let pending = pendingInstall else { return }
        pendingInstall = nil
        isBusy = true
        errorMessage = nil
        do {
            let staged = try InstalledPackageStore.stage(pending.document)
            if pending.isUpdate {
                _ = try await engine.update(from: staged)
            } else {
                _ = try await engine.install(from: staged)
            }
        } catch {
            errorMessage = describe(error)
        }
        isBusy = false
        await refresh(repositories: lastRepositories)
    }

    func cancelPending() {
        pendingInstall = nil
    }

    func uninstall(id: String) async {
        await engine.uninstall(id: id)
        InstalledPackageStore.remove(id: id)
        await refresh(repositories: lastRepositories)
    }

    func reinstall(id: String) async {
        isBusy = true
        errorMessage = nil
        if let dir = try? InstalledPackageStore.directory().appendingPathComponent("\(id).runtime", isDirectory: true) {
            await engine.uninstall(id: id)
            do {
                _ = try await engine.install(from: DirectoryPackageSource(directory: dir))
            } catch {
                errorMessage = describe(error)
            }
        }
        isBusy = false
        await refresh(repositories: lastRepositories)
    }

    func clearCache(id: String) async {
        await engine.clearStorage(of: id)
    }

    func storageBytes(of id: String) async -> Int {
        await engine.storageBytes(of: id)
    }

    func logs(of id: String) -> [LogEvent] {
        LogBus.shared.history(forExtension: id, limit: 200)
    }

    func installedExtension(id: String) -> InstalledExtension? {
        installed.first { $0.id == id }
    }

    private func describe(_ error: Error) -> String {
        (error as? RuntimeError)?.description ?? error.localizedDescription
    }
}
