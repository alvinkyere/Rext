import Foundation

// ---------------------------------------------------------------------------
// RuntimeConfiguration.swift  (Runtime SDK v1)
//
// The security-relevant slice of a manifest that the execution layer
// (ConnectorRuntime) actually needs. Deriving this pure value keeps the bridge
// decoupled from the full manifest shape: the bridge enforces an allowlist and a
// byte budget without knowing anything about metadata, capabilities, or how the
// package was installed.
//
// Enforcement is total by construction — an extension with no network permission
// gets an empty allowlist, and one with no storage permission gets a zero budget.
// ---------------------------------------------------------------------------

public nonisolated struct RuntimeConfiguration: Sendable, Hashable {
    public let extensionID: String
    public let allowedDomains: Set<String>
    public let allowUserConfiguredHost: Bool
    public let storageMaxBytes: Int

    public init(
        extensionID: String,
        allowedDomains: Set<String>,
        allowUserConfiguredHost: Bool,
        storageMaxBytes: Int
    ) {
        self.extensionID = extensionID
        self.allowedDomains = allowedDomains
        self.allowUserConfiguredHost = allowUserConfiguredHost
        self.storageMaxBytes = storageMaxBytes
    }

    /// Derives the execution configuration from a manifest's declared permissions.
    public init(manifest: ExtensionManifest) {
        self.extensionID = manifest.id
        self.allowedDomains = Set(manifest.permissions.network?.domains ?? [])
        self.allowUserConfiguredHost = manifest.permissions.network?.allowUserConfiguredHost ?? false
        self.storageMaxBytes = manifest.permissions.storage?.maxBytes ?? 0
    }
}
