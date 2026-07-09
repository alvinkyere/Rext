import Foundation

// ---------------------------------------------------------------------------
// RepositoryModels.swift  (Runtime SDK v1, Priority 6 — models only)
//
// The data model for a future extension repository. NO downloading, discovery,
// or signature verification is implemented in this milestone — these types exist
// so that when repositories arrive, the on-disk/over-the-wire `repository.json`
// format is already stable and the installer can consume downloaded packages
// without a redesign.
//
// Shape mirrors the intended index:
//
//   repository.json
//     └─ metadata            (name, description, updatedAt)
//     └─ publisher           (identity + optional public key + verified flag)
//     └─ extensions[]        (listing per extension)
//          └─ versions[]     (per-version download URL + checksum + signature)
//
// The runtime is designed to support multiple repositories (official, personal,
// company, university), each with its own publisher and, later, signature-based
// verification.
// ---------------------------------------------------------------------------

/// Integrity digest for a downloaded package artifact.
public nonisolated struct RepositoryChecksum: Sendable, Codable, Hashable {
    /// e.g. `sha256`.
    public let algorithm: String
    /// Hex-encoded digest value.
    public let value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

/// Detached signature over a package artifact, verifiable against a publisher's
/// public key (verification is a future milestone).
public nonisolated struct RepositorySignature: Sendable, Codable, Hashable {
    /// e.g. `ed25519`.
    public let algorithm: String
    /// Base64-encoded signature value.
    public let value: String
    /// The `Publisher.id` that produced the signature.
    public let signedBy: String

    public init(algorithm: String, value: String, signedBy: String) {
        self.algorithm = algorithm
        self.value = value
        self.signedBy = signedBy
    }
}

/// One downloadable version of an extension.
public nonisolated struct RepositoryVersion: Sendable, Codable, Hashable {
    public let version: SemanticVersion
    /// Where the packaged extension (directory archive) can be fetched.
    public let downloadURL: String
    public let checksum: RepositoryChecksum
    public let signature: RepositorySignature?
    public let minimumRuntimeVersion: SemanticVersion?
    public let publishedAt: Date?

    public init(
        version: SemanticVersion,
        downloadURL: String,
        checksum: RepositoryChecksum,
        signature: RepositorySignature? = nil,
        minimumRuntimeVersion: SemanticVersion? = nil,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.checksum = checksum
        self.signature = signature
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.publishedAt = publishedAt
    }
}

/// A published extension as advertised by a repository (distinct from the
/// installed `ExtensionManifest`, which is authoritative once installed).
public nonisolated struct ExtensionListing: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let category: ExtensionCategory
    public let author: String?
    public let iconURL: String?
    public let versions: [RepositoryVersion]

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        category: ExtensionCategory = .other,
        author: String? = nil,
        iconURL: String? = nil,
        versions: [RepositoryVersion]
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.category = category
        self.author = author
        self.iconURL = iconURL
        self.versions = versions
    }

    /// The highest semantic version offered, if any.
    public var latest: RepositoryVersion? {
        versions.max { $0.version < $1.version }
    }
}

/// The identity behind a repository's extensions. `verified` and `publicKey`
/// back future publisher verification.
public nonisolated struct Publisher: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let website: String?
    /// Base64-encoded public key used to verify `RepositorySignature`s.
    public let publicKey: String?
    public let verified: Bool

    public init(
        id: String,
        displayName: String,
        website: String? = nil,
        publicKey: String? = nil,
        verified: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.website = website
        self.publicKey = publicKey
        self.verified = verified
    }
}

/// Human-facing information about a repository.
public nonisolated struct RepositoryMetadata: Sendable, Codable, Hashable {
    public let name: String
    public let description: String?
    public let url: String?
    public let updatedAt: Date?

    public init(name: String, description: String? = nil, url: String? = nil, updatedAt: Date? = nil) {
        self.name = name
        self.description = description
        self.url = url
        self.updatedAt = updatedAt
    }
}

/// The root of a `repository.json` index. Multiple repositories can be
/// aggregated by the runtime in a future milestone.
public nonisolated struct Repository: Sendable, Codable, Hashable, Identifiable {
    /// Format version of the repository index itself, for forward compatibility.
    public let schemaVersion: Int
    public let metadata: RepositoryMetadata
    public let publisher: Publisher
    public let extensions: [ExtensionListing]

    public var id: String { publisher.id }

    public init(
        schemaVersion: Int = 1,
        metadata: RepositoryMetadata,
        publisher: Publisher,
        extensions: [ExtensionListing]
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.publisher = publisher
        self.extensions = extensions
    }
}
