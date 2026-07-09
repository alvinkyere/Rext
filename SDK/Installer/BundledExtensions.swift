import Foundation

// ---------------------------------------------------------------------------
// BundledExtensions.swift  (Runtime SDK v1)
//
// Installs the extension packages that ship inside the app bundle. On launch it
// locates each bundled package, stages it into Application Support (the same
// on-disk location a future repository download would land in), and installs it
// through the engine's normal `install(from:)` path. This proves the whole
// pipeline — install from disk → validate → register → ready — end to end and is
// completely origin-agnostic, exactly as repository downloads will be.
// ---------------------------------------------------------------------------

public enum BundledExtensions {
    private static let logger = RuntimeLogger(extensionID: "runtime.bootstrap")

    /// Stage and install every bundled package. Failures are logged, never fatal;
    /// duplicates (already installed this launch) are ignored.
    public static func installAll(into engine: RuntimeEngine = .shared, bundle: Bundle = .main) async {
        for directory in locatePackageDirectories(in: bundle) {
            do {
                let staged = try stage(packageAt: directory)
                let installed = try await engine.install(from: staged)
                logger.install("Installed bundled extension", metadata: ["id": installed.id])
            } catch RuntimeError.duplicateExtensionID {
                continue
            } catch let error as RuntimeError {
                // Not every manifest.json in the bundle is one of ours; skip quietly
                // unless it looked installable and then failed.
                logger.warning("Skipped bundled package at \(directory.lastPathComponent): \(error.description)")
            } catch {
                logger.error("Failed to install bundled package: \(error.localizedDescription)")
            }
        }
    }

    /// Every directory in the bundle's resources that contains a `manifest.json`.
    /// Robust to bundle resource flattening — it finds the package wherever the
    /// build system placed it.
    private static func locatePackageDirectories(in bundle: Bundle) -> [URL] {
        guard let resourceURL = bundle.resourceURL else { return [] }
        var directories: [URL] = []
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent == "manifest.json" {
                directories.append(url.deletingLastPathComponent())
            }
        }
        return directories
    }

    /// Copy a package's manifest + entry point into Application Support and return
    /// a `DirectoryPackageSource` pointing at the writable staged copy.
    private static func stage(packageAt directory: URL) throws -> DirectoryPackageSource {
        let source = DirectoryPackageSource(directory: directory)
        let manifestData = try source.manifestData()
        let manifest = try ManifestParser.parse(manifestData)
        let entryPointSource = try source.entryPointSource(named: manifest.entryPoint)

        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let stagedDir = base
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent("\(manifest.id).runtime", isDirectory: true)
        try fileManager.createDirectory(at: stagedDir, withIntermediateDirectories: true)

        try manifestData.write(to: stagedDir.appendingPathComponent("manifest.json"))
        try Data(entryPointSource.utf8).write(to: stagedDir.appendingPathComponent(manifest.entryPoint))

        return DirectoryPackageSource(directory: stagedDir)
    }
}
