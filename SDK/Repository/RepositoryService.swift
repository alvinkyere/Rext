import Foundation
import CryptoKit

// ---------------------------------------------------------------------------
// RepositoryService.swift  (Rext Extension Platform — Phase 3)
//
// Discovers and installs extensions from a repository. The flow mirrors
// Aniyomi/Tachiyomi:
//
//   fetch repository.json → compare versions → download package
//   → verify checksum (SHA-256) → install through the engine → register
//
// Transport is dependency-free: an extension package is an ExtensionPackageDocument
// (JSON), fetched over URLSession. `file://` URLs are read directly, and a custom
// URL protocol (BundledRepositoryURLProtocol) serves the bundled sample repo so the
// whole pipeline runs offline without a server. Signature verification is a future
// milestone; checksums are verified today.
// ---------------------------------------------------------------------------

public nonisolated struct RepositoryService: Sendable {
    private let session: URLSession

    public init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.session = URLSession(configuration: sessionConfiguration)
    }

    // MARK: Discovery

    /// Fetch and parse a `repository.json` index.
    public func fetchRepository(at url: URL) async throws -> Repository {
        let data: Data
        do {
            data = try await loadData(from: url)
        } catch {
            throw RuntimeError.repositoryUnreachable(url: url.absoluteString)
        }

        let host = url.host ?? "This source"

        // Detect foreign repository formats and explain rather than dumping a
        // raw decoding error. The common case is an Aniyomi/Tachiyomi index — a
        // top-level array of Android (.apk) extensions Rext can't run.
        if let top = try? JSONSerialization.jsonObject(with: data), let array = top as? [Any] {
            let looksLikeAniyomi = (array.first as? [String: Any]).map { $0["apk"] != nil || $0["pkg"] != nil } ?? false
            let reason = looksLikeAniyomi
                ? "It looks like an Aniyomi/Tachiyomi repository, which ships Android (.apk) extensions that Rext can't run."
                : "Its index is a JSON array, not a Rext repository object."
            throw RuntimeError.repositoryIncompatible("\(host) isn't a Rext repository. \(reason)")
        }

        do {
            return try JSONDecoder().decode(Repository.self, from: data)
        } catch {
            throw RuntimeError.repositoryIncompatible("\(host) isn't a valid Rext repository (repository.json couldn't be read).")
        }
    }

    /// Listings whose latest version is newer than what is installed.
    public func availableUpdates(in repository: Repository, installed: [InstalledExtension]) -> [ExtensionListing] {
        let installedVersions = Dictionary(installed.map { ($0.id, $0.manifest.version) }) { first, _ in first }
        return repository.extensions.filter { listing in
            guard let current = installedVersions[listing.id], let latest = listing.latest?.version else { return false }
            return latest > current
        }
    }

    /// Listings not currently installed.
    public func availableInstalls(in repository: Repository, installed: [InstalledExtension]) -> [ExtensionListing] {
        let installedIDs = Set(installed.map(\.id))
        return repository.extensions.filter { !installedIDs.contains($0.id) }
    }

    // MARK: Install / update

    /// Download → verify → install a repository listing's version.
    @discardableResult
    public func install(_ version: RepositoryVersion, from listing: ExtensionListing, into engine: RuntimeEngine) async throws -> InstalledExtension {
        let source = try await packageSource(for: version, listing: listing)
        return try await engine.install(from: source)
    }

    /// Download → verify → update an installed listing to `version`.
    @discardableResult
    public func update(to version: RepositoryVersion, from listing: ExtensionListing, into engine: RuntimeEngine) async throws -> InstalledExtension {
        let source = try await packageSource(for: version, listing: listing)
        return try await engine.update(from: source)
    }

    /// Download + verify + decode a package WITHOUT installing — lets the UI show a
    /// permission review (from the real manifest) before the user commits.
    public func fetchPackage(_ version: RepositoryVersion, from listing: ExtensionListing) async throws -> ExtensionPackageDocument {
        let data = try await download(version)
        try verifyChecksum(data, against: version.checksum)
        return try ExtensionPackageDocument.decode(from: data)
    }

    private func packageSource(for version: RepositoryVersion, listing: ExtensionListing) async throws -> PackageDocumentSource {
        let document = try await fetchPackage(version, from: listing)
        return PackageDocumentSource(document: document, origin: "repository:\(listing.id)@\(version.version)")
    }

    // MARK: Download & integrity

    public func download(_ version: RepositoryVersion) async throws -> Data {
        guard let url = URL(string: version.downloadURL) else {
            throw RuntimeError.downloadFailed(reason: "invalid download URL '\(version.downloadURL)'")
        }
        do {
            return try await loadData(from: url)
        } catch let error as RuntimeError {
            throw error
        } catch {
            throw RuntimeError.downloadFailed(reason: error.localizedDescription)
        }
    }

    /// Verify a downloaded artifact against its recorded checksum. Only SHA-256 is
    /// supported today; an unsupported algorithm is a hard failure, never a skip.
    public func verifyChecksum(_ data: Data, against checksum: RepositoryChecksum) throws {
        let algorithm = checksum.algorithm.lowercased()
        guard algorithm == "sha256" || algorithm == "sha-256" else {
            throw RuntimeError.downloadFailed(reason: "unsupported checksum algorithm '\(checksum.algorithm)'")
        }
        let actual = Self.sha256Hex(data)
        guard actual.caseInsensitiveCompare(checksum.value) == .orderedSame else {
            throw RuntimeError.checksumMismatch(expected: checksum.value, actual: actual)
        }
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: URL loading

    private func loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
