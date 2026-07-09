import Foundation

// ---------------------------------------------------------------------------
// InstalledPackageStore.swift  (Rext Phase 2 — persistent installs)
//
// Persists installed extension packages on disk so extensions installed from a
// repository survive relaunch (the engine's registry is in-memory). Packages are
// staged as directories under Application Support/Extensions/<id>.runtime and
// re-installed on launch. This is the on-disk half of the platform's install
// story; SwiftData holds user data, this holds the extensions themselves.
// ---------------------------------------------------------------------------

public enum InstalledPackageStore {
    private static let logger = RuntimeLogger(extensionID: "runtime.store")

    /// Application Support/Extensions (created on demand).
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("Extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Every staged package directory (those containing a manifest.json).
    public static func stagedSources() -> [DirectoryPackageSource] {
        guard let dir = try? directory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
              ) else { return [] }
        return entries
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
            .map { DirectoryPackageSource(directory: $0) }
    }

    /// Write a downloaded package to disk and return a source pointing at it.
    @discardableResult
    public static func stage(_ document: ExtensionPackageDocument) throws -> DirectoryPackageSource {
        let dir = try directory().appendingPathComponent("\(document.manifest.id).runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(document.manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try Data(document.entryPoint.utf8).write(to: dir.appendingPathComponent(document.manifest.entryPoint))
        return DirectoryPackageSource(directory: dir)
    }

    /// Delete a staged package (on uninstall).
    public static func remove(id: String) {
        guard let dir = try? directory() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).runtime"))
    }

    /// On launch: seed the bundled sample on first run, then install every staged
    /// package into the engine. Idempotent — already-installed ids are skipped.
    public static func bootstrap(into engine: RuntimeEngine = .shared) async {
        if stagedSources().isEmpty, let document = bundledSampleDocument() {
            _ = try? stage(document)
        }
        for source in stagedSources() {
            do {
                let installed = try await engine.install(from: source)
                logger.install("Restored installed extension", metadata: ["id": installed.id])
            } catch RuntimeError.duplicateExtensionID {
                continue
            } catch {
                logger.warning("Failed to restore \(source.origin): \(error)")
            }
        }
    }

    /// Build a package document from the bundled PodcastRSS package (first launch).
    private static func bundledSampleDocument() -> ExtensionPackageDocument? {
        let source = BundlePackageSource()
        guard let manifestData = try? source.manifestData(),
              let manifest = try? ManifestParser.parse(manifestData),
              let entryPoint = try? source.entryPointSource(named: manifest.entryPoint) else {
            return nil
        }
        return ExtensionPackageDocument(manifest: manifest, entryPoint: entryPoint)
    }
}
