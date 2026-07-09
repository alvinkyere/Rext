import Foundation

// ---------------------------------------------------------------------------
// ExtensionPackageDocument.swift  (Rext Extension Platform — repository transport)
//
// The wire format for a downloadable extension: a single JSON document carrying
// the manifest, the entry-point JavaScript as text, and optional base64 assets.
// This is dependency-free (no zip unarchiver needed) and installs through the
// existing origin-agnostic `PackageInstaller` via `PackageDocumentSource`.
//
// A future zip/.aar package format is just another `PackageSource` — the
// installer never changes.
// ---------------------------------------------------------------------------

public nonisolated struct ExtensionPackageDocument: Sendable, Codable {
    public let manifest: ExtensionManifest
    /// UTF-8 source of the entry point named by `manifest.entryPoint`.
    public let entryPoint: String
    /// Optional package-relative assets, base64-encoded (e.g. `icon.png`).
    public let assets: [String: String]?

    public init(manifest: ExtensionManifest, entryPoint: String, assets: [String: String]? = nil) {
        self.manifest = manifest
        self.entryPoint = entryPoint
        self.assets = assets
    }

    public static func decode(from data: Data) throws -> ExtensionPackageDocument {
        do {
            return try JSONDecoder().decode(ExtensionPackageDocument.self, from: data)
        } catch {
            throw RuntimeError.downloadFailed(reason: "invalid package document: \(error)")
        }
    }
}

/// An in-memory `PackageSource` backed by a downloaded `ExtensionPackageDocument`.
/// Lets a repository download install through the same path as a directory on disk.
public nonisolated struct PackageDocumentSource: PackageSource {
    public let document: ExtensionPackageDocument
    public let origin: String

    public init(document: ExtensionPackageDocument, origin: String = "package-document") {
        self.document = document
        self.origin = origin
    }

    public func manifestData() throws -> Data {
        do {
            return try JSONEncoder().encode(document.manifest)
        } catch {
            throw RuntimeError.manifestUnreadable(reason: "\(error)")
        }
    }

    public func entryPointSource(named name: String) throws -> String {
        guard name == document.manifest.entryPoint else {
            throw RuntimeError.entryPointMissing(expected: name)
        }
        return document.entryPoint
    }

    public func fileExists(_ relativePath: String) -> Bool {
        relativePath == document.manifest.entryPoint || (document.assets?[relativePath] != nil)
    }
}
