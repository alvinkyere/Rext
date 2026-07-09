import Foundation

// ---------------------------------------------------------------------------
// PackageSource.swift  (Runtime SDK v1, Priority 1 & 9)
//
// Abstracts *where* an extension package comes from. The installer consumes a
// `PackageSource` and never cares whether the bytes came from a directory on
// disk, the app bundle, a future ZIP archive, or a downloaded repository entry.
// New origins are added by conforming a new type — the installer stays unchanged.
// ---------------------------------------------------------------------------

public protocol PackageSource: Sendable {
    /// A human-readable identifier for logs and errors (e.g. a file path).
    nonisolated var origin: String { get }
    /// Raw bytes of the package's `manifest.json`.
    nonisolated func manifestData() throws -> Data
    /// UTF-8 source of the package-relative entry point (e.g. `main.js`).
    nonisolated func entryPointSource(named name: String) throws -> String
    /// Whether a package-relative file exists (used to validate the entry point).
    nonisolated func fileExists(_ relativePath: String) -> Bool
}

// MARK: - Directory on disk

/// A package laid out as a directory, e.g. `.../PodcastRSS.runtime/`. This is the
/// canonical installable form and the shape repository downloads will stage into.
public nonisolated struct DirectoryPackageSource: PackageSource {
    public let directory: URL
    public let manifestFileName: String

    public init(directory: URL, manifestFileName: String = "manifest.json") {
        self.directory = directory
        self.manifestFileName = manifestFileName
    }

    public var origin: String { directory.path }

    public func manifestData() throws -> Data {
        let url = directory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeError.manifestMissing(packageOrigin: origin)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: error.localizedDescription)
        }
    }

    public func entryPointSource(named name: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeError.entryPointMissing(expected: name)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: "entry point '\(name)' unreadable: \(error.localizedDescription)")
        }
    }

    public func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
    }
}

// MARK: - App bundle

/// A package whose files ship inside an app bundle. Because bundles flatten
/// resources, files are resolved by name via `Bundle.url(forResource:withExtension:)`.
public nonisolated struct BundlePackageSource: PackageSource {
    public let bundle: Bundle
    public let manifestFileName: String

    public init(bundle: Bundle = .main, manifestFileName: String = "manifest.json") {
        self.bundle = bundle
        self.manifestFileName = manifestFileName
    }

    public var origin: String { "bundle:\(bundle.bundleIdentifier ?? bundle.bundlePath)" }

    private func url(for relativePath: String) -> URL? {
        let path = relativePath as NSString
        let base = path.deletingPathExtension
        let ext = path.pathExtension
        return bundle.url(forResource: base, withExtension: ext.isEmpty ? nil : ext)
    }

    public func manifestData() throws -> Data {
        guard let url = url(for: manifestFileName) else {
            throw RuntimeError.manifestMissing(packageOrigin: origin)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: error.localizedDescription)
        }
    }

    public func entryPointSource(named name: String) throws -> String {
        guard let url = url(for: name) else {
            throw RuntimeError.entryPointMissing(expected: name)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: "entry point '\(name)' unreadable: \(error.localizedDescription)")
        }
    }

    public func fileExists(_ relativePath: String) -> Bool {
        url(for: relativePath) != nil
    }
}
